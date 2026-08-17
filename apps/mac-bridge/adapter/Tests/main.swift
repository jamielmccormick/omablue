import Foundation

private func fixture(_ name: String) throws -> [String: Any] {
    let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let data = try Data(contentsOf: directory.appendingPathComponent(name))
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw AdapterFailure(code: "invalid_test_fixture", retryable: false)
    }
    return object
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("test failed: \(message)\n".utf8))
        exit(1)
    }
}

do {
    let source = SourceIdentity(instance: "source-example", databaseGeneration: "generation-example-a")
    let status = try translateStatus(
        requestID: "req-status-example",
        source: source,
        result: try fixture("rpc-status.json")
    )
    let capabilities = status["capabilities"] as? [String: Any]
    check(capabilities?["read_messages"] as? Bool == true, "read capability")
    check(capabilities?["send_text"] as? Bool == false, "send remains disabled")

    let sync = try translateSync(
        requestID: "req-sync-example",
        source: source,
        chatsResult: try fixture("rpc-chats.json"),
        messagesResult: try fixture("rpc-messages-after.json")
    )
    let conversations = sync["conversations"] as? [[String: Any]]
    let messages = sync["messages"] as? [[String: Any]]
    check(conversations?.count == 2, "conversation count")
    check(messages?.count == 2, "message count")
    check(conversations?[1]["service"] is NSNull, "unknown service remains null")
    check(conversations?[1]["unread_count"] is NSNull, "missing unread remains null")

    let attachments = messages?[1]["attachments"] as? [[String: Any]]
    check(attachments?.first?["id"] is NSNull, "attachment id remains null")
    check(attachments?.first?["display_name"] as? String == "example.png", "path is reduced")

    let validRequest = Data(#"{"type":"sync","request_id":"req","protocol_version":1,"cursor":null,"limit":100}"#.utf8)
    _ = try parseRequest(validRequest)
    let invalidRequest = Data(#"{"type":"status","request_id":"req","protocol_version":1,"command":"shell"}"#.utf8)
    do {
        _ = try parseRequest(invalidRequest)
        check(false, "unknown request field accepted")
    } catch let failure as AdapterFailure {
        check(failure.code == "unknown_request_field", "unknown field error")
    }

    print("OmaBlue adapter translation tests passed.")
} catch {
    FileHandle.standardError.write(Data("test failed: \(error)\n".utf8))
    exit(1)
}
