import Foundation

func loadSourceIdentity() throws -> SourceIdentity {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let stateDirectory = home.appendingPathComponent(
        "Library/Application Support/OmaBlue",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: stateDirectory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )

    let instanceURL = stateDirectory.appendingPathComponent("source-instance")
    let instance: String
    if let stored = try? String(contentsOf: instanceURL, encoding: .utf8),
       UUID(uuidString: stored.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    {
        instance = stored.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    } else {
        instance = UUID().uuidString.lowercased()
        try Data("\(instance)\n".utf8).write(to: instanceURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: instanceURL.path
        )
    }

    let databasePath = home.appendingPathComponent("Library/Messages/chat.db").path
    let attributes: [FileAttributeKey: Any]
    do {
        attributes = try FileManager.default.attributesOfItem(atPath: databasePath)
    } catch {
        throw AdapterFailure(code: "database_unavailable", retryable: true)
    }
    guard
        let device = attributes[.systemNumber] as? NSNumber,
        let inode = attributes[.systemFileNumber] as? NSNumber
    else {
        throw AdapterFailure(code: "database_identity_unavailable", retryable: true)
    }
    let generation = String(format: "%llx:%llx", device.uint64Value, inode.uint64Value)
    return SourceIdentity(instance: instance, databaseGeneration: generation)
}
