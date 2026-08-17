import Foundation

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("test failed: \(message)\n".utf8))
        exit(1)
    }
}

do {
    let rpc = try PersistentIMsgRPC(executable: URL(fileURLWithPath: CommandLine.arguments[1]))
    let status = try rpc.call(id: "status", method: "status")
    check(status["version"] as? String == "0.14.1", "status response")

    let page = try rpc.call(id: "page", method: "messages.after")
    check((page["next_rowid"] as? NSNumber)?.intValue == 10, "page response")

    let notification = try rpc.nextNotification(timeout: 1)
    check(notification?["method"] as? String == "message", "interleaved notification")

    let subscription = try rpc.call(id: "watch", method: "watch.subscribe")
    check((subscription["subscription"] as? NSNumber)?.intValue == 7, "subscribe response")
    rpc.stop()
    print("OmaBlue persistent RPC tests passed.")
} catch {
    FileHandle.standardError.write(Data("test failed: \(error)\n".utf8))
    exit(1)
}
