import AppKit
import Foundation

private struct ProbeStatus: Codable {
    let schemaVersion: Int
    let checkedAt: String
    let processID: Int32
    let effectiveUserID: UInt32
    let databaseReadable: Bool
    let databaseErrorDomain: String?
    let databaseErrorCode: Int?
    let messagesAutomationSucceeded: Bool
    let messagesAutomationErrorCode: Int?
    let imsgAvailable: Bool
    let imsgVersion: String?
    let imsgDatabaseReady: Bool?
    let imsgExitStatus: Int32?
}

private let iso8601 = ISO8601DateFormatter()

private func databaseProbe() -> (Bool, String?, Int?) {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Messages/chat.db")

    do {
        let handle = try FileHandle(forReadingFrom: url)
        try handle.close()
        return (true, nil, nil)
    } catch {
        let nsError = error as NSError
        return (false, nsError.domain, nsError.code)
    }
}

private func automationProbe() -> (Bool, Int?) {
    guard let script = NSAppleScript(
        source: "tell application \"Messages\" to get version"
    ) else {
        return (false, nil)
    }

    var errorInfo: NSDictionary?
    _ = script.executeAndReturnError(&errorInfo)
    let code = errorInfo?[NSAppleScript.errorNumber] as? Int
    return (errorInfo == nil, code)
}

private func imsgProbe() -> (Bool, String?, Bool?, Int32?) {
    guard let resources = Bundle.main.resourceURL else {
        return (false, nil, nil, nil)
    }
    let executable = resources.appendingPathComponent("imsg/imsg")

    guard FileManager.default.isExecutableFile(atPath: executable.path) else {
        return (false, nil, nil, nil)
    }

    let process = Process()
    let output = Pipe()
    let finished = DispatchSemaphore(value: 0)
    process.executableURL = executable
    process.arguments = ["status", "--json"]
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    process.terminationHandler = { _ in
        finished.signal()
    }

    do {
        try process.run()
        if finished.wait(timeout: .now() + 5) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 1)
            return (true, nil, nil, nil)
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return (true, nil, nil, process.terminationStatus)
        }

        let database = object["database"] as? [String: Any]
        return (
            true,
            object["version"] as? String,
            database?["ready"] as? Bool,
            process.terminationStatus
        )
    } catch {
        return (true, nil, nil, nil)
    }
}

private func statusURL() throws -> URL {
    let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/OmaBlue", isDirectory: true)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
    return directory.appendingPathComponent("feasibility-status.json")
}

private func runProbe() {
    let database = databaseProbe()
    let automation = automationProbe()
    let imsg = imsgProbe()
    let status = ProbeStatus(
        schemaVersion: 1,
        checkedAt: iso8601.string(from: Date()),
        processID: ProcessInfo.processInfo.processIdentifier,
        effectiveUserID: geteuid(),
        databaseReadable: database.0,
        databaseErrorDomain: database.1,
        databaseErrorCode: database.2,
        messagesAutomationSucceeded: automation.0,
        messagesAutomationErrorCode: automation.1,
        imsgAvailable: imsg.0,
        imsgVersion: imsg.1,
        imsgDatabaseReady: imsg.2,
        imsgExitStatus: imsg.3
    )

    do {
        let data = try JSONEncoder().encode(status)
        let url = try statusURL()
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    } catch {
        let nsError = error as NSError
        FileHandle.standardError.write(
            Data("probe write failed: \(nsError.domain) \(nsError.code)\n".utf8)
        )
    }
}

while true {
    runProbe()
    Thread.sleep(forTimeInterval: 30)
}
