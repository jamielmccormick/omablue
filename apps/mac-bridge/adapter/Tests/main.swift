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
    let events = sync["events"] as? [[String: Any]]
    check(conversations?.count == 2, "conversation count")
    check(messages?.count == 2, "message count")
    check(events?.isEmpty == true, "event count")
    check(conversations?[1]["service"] is NSNull, "unknown service remains null")
    check(conversations?[1]["unread_count"] is NSNull, "missing unread remains null")

    var contactChats = try fixture("rpc-chats.json")
    var contactChatRows = contactChats["chats"] as? [[String: Any]] ?? []
    contactChatRows[1]["display_name"] = ""
    contactChatRows[1]["name"] = ""
    contactChats["chats"] = contactChatRows

    let namedSync = try translateSync(
        requestID: "req-sync-contacts",
        source: source,
        chatsResult: contactChats,
        messagesResult: try fixture("rpc-messages-after.json"),
        contactNames: [
            "phone:5550000002": "Sam Contact",
            "phone:5550000003": "Pat Contact",
        ]
    )
    let namedConversations = namedSync["conversations"] as? [[String: Any]]
    let namedTitle = namedConversations?[1]["title"] as? String
    check(namedTitle == "Sam Contact, Pat Contact", "group contact title")
    let namedParticipants = namedConversations?[1]["participants"] as? [[String: Any]]
    check(namedParticipants?[0]["display_name"] as? String == "Sam Contact", "first contact participant")
    check(namedParticipants?[1]["display_name"] as? String == "Pat Contact", "second contact participant")

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
