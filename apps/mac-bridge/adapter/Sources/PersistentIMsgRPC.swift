import Foundation

private enum StoredResponse {
    case success([String: Any])
    case failure(AdapterFailure)
}

final class PersistentIMsgRPC: @unchecked Sendable {
    private static let maximumLineBytes = 4 * 1024 * 1024
    private static let maximumNotifications = 64
    private static let maximumNotificationBytes = 8 * 1024 * 1024
    private static let maximumPendingRequests = 8

    private let condition = NSCondition()
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var lineBuffer = Data()
    private var responses = [String: StoredResponse]()
    private var pending = Set<String>()
    private var notifications = [(value: [String: Any], bytes: Int)]()
    private var notificationBytes = 0
    private var terminalFailure: AdapterFailure?
    private var outputClosed = false
    private var processTerminated = false

    init(executable: URL) throws {
        process.executableURL = executable
        process.arguments = ["rpc"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            self?.markProcessTerminated()
        }
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            throw AdapterFailure(code: "upstream_unavailable", retryable: true)
        }
    }

    func call(
        id: String,
        method: String,
        params: [String: Any] = [:],
        timeout: TimeInterval = 15
    ) throws -> [String: Any] {
        condition.lock()
        guard terminalFailure == nil, !id.isEmpty, !pending.contains(id),
              pending.count < Self.maximumPendingRequests
        else {
            condition.unlock()
            throw AdapterFailure(code: "rpc_busy", retryable: true)
        }
        pending.insert(id)
        condition.unlock()

        do {
            var data = try JSONSerialization.data(withJSONObject: [
                "jsonrpc": "2.0",
                "id": id,
                "method": method,
                "params": params,
            ])
            data.append(0x0A)
            try input.fileHandleForWriting.write(contentsOf: data)
        } catch {
            condition.lock()
            pending.remove(id)
            condition.unlock()
            throw AdapterFailure(code: "upstream_write_failed", retryable: true)
        }

        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer {
            pending.remove(id)
            responses.removeValue(forKey: id)
            condition.unlock()
        }
        while responses[id] == nil, terminalFailure == nil {
            if !condition.wait(until: deadline) {
                throw AdapterFailure(code: "upstream_timeout", retryable: true)
            }
        }
        if let failure = terminalFailure { throw failure }
        guard let response = responses[id] else {
            throw AdapterFailure(code: "missing_upstream_response", retryable: true)
        }
        switch response {
        case let .success(result): return result
        case let .failure(failure): throw failure
        }
    }

    func nextNotification(timeout: TimeInterval = 30) throws -> [String: Any]? {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while notifications.isEmpty, terminalFailure == nil {
            if !condition.wait(until: deadline) { return nil }
        }
        if let failure = terminalFailure { throw failure }
        guard !notifications.isEmpty else { return nil }
        let notification = notifications.removeFirst()
        notificationBytes -= notification.bytes
        return notification.value
    }

    func stop() {
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }

    private func consume(_ data: Data) {
        condition.lock()
        defer { condition.unlock() }
        if data.isEmpty {
            outputClosed = true
            finishIfClosed()
            return
        }
        guard terminalFailure == nil else { return }
        lineBuffer.append(data)

        while let newline = lineBuffer.firstIndex(of: 0x0A) {
            guard lineBuffer.distance(from: lineBuffer.startIndex, to: newline)
                <= Self.maximumLineBytes
            else {
                fail(AdapterFailure(code: "upstream_line_too_large", retryable: true))
                return
            }
            let line = Data(lineBuffer[..<newline])
            lineBuffer.removeSubrange(...newline)
            if line.isEmpty { continue }
            do {
                try consumeLine(line)
            } catch let failure as AdapterFailure {
                fail(failure)
                return
            } catch {
                fail(AdapterFailure(code: "invalid_upstream_output", retryable: true))
                return
            }
        }
        if lineBuffer.count > Self.maximumLineBytes {
            fail(AdapterFailure(code: "upstream_line_too_large", retryable: true))
        }
    }

    private func consumeLine(_ line: Data) throws {
        guard
            let object = try JSONSerialization.jsonObject(with: line) as? [String: Any]
        else {
            throw AdapterFailure(code: "invalid_upstream_output", retryable: true)
        }

        if let id = object["id"] as? String {
            guard pending.contains(id) else {
                throw AdapterFailure(code: "unexpected_upstream_response", retryable: true)
            }
            if object["error"] != nil {
                responses[id] = .failure(
                    AdapterFailure(code: "upstream_rpc_error", retryable: true)
                )
            } else if let result = object["result"] as? [String: Any] {
                responses[id] = .success(result)
            } else {
                throw AdapterFailure(code: "invalid_upstream_output", retryable: true)
            }
            condition.broadcast()
            return
        }

        guard object["method"] is String else {
            throw AdapterFailure(code: "invalid_upstream_output", retryable: true)
        }
        guard notifications.count < Self.maximumNotifications,
              notificationBytes + line.count <= Self.maximumNotificationBytes
        else {
            throw AdapterFailure(code: "local_notification_overflow", retryable: true)
        }
        notifications.append((object, line.count))
        notificationBytes += line.count
        condition.broadcast()
    }

    private func markProcessTerminated() {
        condition.lock()
        processTerminated = true
        finishIfClosed()
        condition.unlock()
    }

    private func finishIfClosed() {
        guard outputClosed, processTerminated, terminalFailure == nil else { return }
        if !lineBuffer.isEmpty {
            fail(AdapterFailure(code: "truncated_upstream_output", retryable: true))
        } else {
            fail(AdapterFailure(code: "upstream_terminated", retryable: true))
        }
    }

    private func fail(_ failure: AdapterFailure) {
        terminalFailure = failure
        condition.broadcast()
    }
}
