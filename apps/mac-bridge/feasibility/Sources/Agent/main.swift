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
    let result = script.executeAndReturnError(&errorInfo)
    let code = errorInfo?[NSAppleScript.errorNumber] as? Int
    return (result != nil, code)
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
    let status = ProbeStatus(
        schemaVersion: 1,
        checkedAt: iso8601.string(from: Date()),
        processID: ProcessInfo.processInfo.processIdentifier,
        effectiveUserID: geteuid(),
        databaseReadable: database.0,
        databaseErrorDomain: database.1,
        databaseErrorCode: database.2,
        messagesAutomationSucceeded: automation.0,
        messagesAutomationErrorCode: automation.1
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

runProbe()

let timer = Timer(timeInterval: 30, repeats: true) { _ in
    runProbe()
}
RunLoop.main.add(timer, forMode: .common)
RunLoop.main.run()
