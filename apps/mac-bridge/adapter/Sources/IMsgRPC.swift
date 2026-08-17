import Foundation

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Data()

    func append(_ data: Data) {
        lock.lock()
        value.append(data)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

struct IMsgRPC {
    let executable: URL

    func call(_ requests: [[String: Any]], timeout: TimeInterval = 15) throws -> [String: [String: Any]] {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let outputData = LockedData()
        let outputClosed = DispatchSemaphore(value: 0)
        let terminated = DispatchSemaphore(value: 0)

        process.executableURL = executable
        process.arguments = ["rpc"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in terminated.signal() }
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                outputClosed.signal()
            } else {
                outputData.append(data)
            }
        }

        do {
            try process.run()
            for request in requests {
                var data = try JSONSerialization.data(withJSONObject: request)
                data.append(0x0A)
                try input.fileHandleForWriting.write(contentsOf: data)
            }
            try input.fileHandleForWriting.close()

            if terminated.wait(timeout: .now() + timeout) == .timedOut {
                process.terminate()
                _ = terminated.wait(timeout: .now() + 1)
                throw AdapterFailure(code: "upstream_timeout", retryable: true)
            }
            _ = outputClosed.wait(timeout: .now() + 1)
            output.fileHandleForReading.readabilityHandler = nil
            guard process.terminationStatus == 0 else {
                throw AdapterFailure(code: "upstream_failed", retryable: true)
            }
            return try parseResponses(outputData.snapshot())
        } catch let failure as AdapterFailure {
            output.fileHandleForReading.readabilityHandler = nil
            throw failure
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { process.terminate() }
            throw AdapterFailure(code: "upstream_unavailable", retryable: true)
        }
    }
}

private func parseResponses(_ data: Data) throws -> [String: [String: Any]] {
    guard let text = String(data: data, encoding: .utf8) else {
        throw AdapterFailure(code: "invalid_upstream_output", retryable: true)
    }
    var responses = [String: [String: Any]]()
    for line in text.split(separator: "\n") {
        guard
            let lineData = String(line).data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: lineData),
            let response = object as? [String: Any],
            let id = response["id"] as? String
        else {
            throw AdapterFailure(code: "invalid_upstream_output", retryable: true)
        }
        if response["error"] != nil {
            throw AdapterFailure(code: "upstream_rpc_error", retryable: true)
        }
        guard let result = response["result"] as? [String: Any] else {
            throw AdapterFailure(code: "invalid_upstream_output", retryable: true)
        }
        responses[id] = result
    }
    return responses
}
