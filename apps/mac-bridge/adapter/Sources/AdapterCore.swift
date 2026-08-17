import Foundation

let omaBlueProtocolVersion = 1
let omaBlueServerVersion = "0.1.0"
let omaBlueMaxSyncLimit = 500

struct SourceIdentity {
    let instance: String
    let databaseGeneration: String

    var json: [String: Any] {
        [
            "instance": instance,
            "database_generation": databaseGeneration,
        ]
    }
}

enum AdapterRequest {
    case status(requestID: String)
    case sync(requestID: String, cursor: [String: Any]?, limit: Int)
    case watch(requestID: String, cursor: [String: Any])

    var requestID: String {
        switch self {
        case let .status(requestID), let .sync(requestID, _, _), let .watch(requestID, _):
            requestID
        }
    }
}

struct AdapterFailure: Error {
    let code: String
    let retryable: Bool
}

func parseRequest(_ data: Data) throws -> AdapterRequest {
    guard data.count <= 65_536 else {
        throw AdapterFailure(code: "request_too_large", retryable: false)
    }
    guard
        let object = try? JSONSerialization.jsonObject(with: data),
        let request = object as? [String: Any],
        let type = request["type"] as? String,
        let requestID = request["request_id"] as? String,
        !requestID.isEmpty,
        let version = integer(request["protocol_version"]),
        version == omaBlueProtocolVersion
    else {
        throw AdapterFailure(code: "invalid_request", retryable: false)
    }

    switch type {
    case "status":
        guard Set(request.keys) == Set(["type", "request_id", "protocol_version"]) else {
            throw AdapterFailure(code: "unknown_request_field", retryable: false)
        }
        return .status(requestID: requestID)
    case "sync":
        let allowed = Set(["type", "request_id", "protocol_version", "cursor", "limit"])
        guard Set(request.keys).isSubset(of: allowed), let limit = integer(request["limit"]),
              (1...omaBlueMaxSyncLimit).contains(limit)
        else {
            throw AdapterFailure(code: "invalid_sync_request", retryable: false)
        }
        let cursor: [String: Any]?
        if request["cursor"] is NSNull || request["cursor"] == nil {
            cursor = nil
        } else if let value = request["cursor"] as? [String: Any] {
            guard Set(value.keys) == ["source_instance", "database_generation", "rowid"] else {
                throw AdapterFailure(code: "invalid_cursor", retryable: false)
            }
            cursor = value
        } else {
            throw AdapterFailure(code: "invalid_cursor", retryable: false)
        }
        return .sync(requestID: requestID, cursor: cursor, limit: limit)
    case "watch":
        guard Set(request.keys) == Set(["type", "request_id", "protocol_version", "cursor"]),
              let cursor = request["cursor"] as? [String: Any],
              Set(cursor.keys) == Set(["source_instance", "database_generation", "rowid"])
        else {
            throw AdapterFailure(code: "invalid_watch_request", retryable: false)
        }
        return .watch(requestID: requestID, cursor: cursor)
    default:
        throw AdapterFailure(code: "unsupported_request", retryable: false)
    }
}

func errorResponse(requestID: String?, failure: AdapterFailure) -> [String: Any] {
    [
        "type": "error",
        "request_id": jsonValue(requestID),
        "protocol_version": omaBlueProtocolVersion,
        "code": failure.code,
        "retryable": failure.retryable,
    ]
}

func translateStatus(
    requestID: String,
    source: SourceIdentity,
    result: [String: Any]
) throws -> [String: Any] {
    guard result["version"] is String, let methods = result["methods"] as? [String] else {
        throw AdapterFailure(code: "invalid_upstream_status", retryable: true)
    }
    let methodSet = Set(methods)
    var messages = [[String: Any]]()
    var events = [[String: Any]]()
    for rawMessage in rawMessages {
        if rawMessage["is_reaction"] as? Bool == true {
            events.append(try translateReactionEvent(rawMessage, source: source))
        } else {
            messages.append(try translateMessage(rawMessage))
        }
    }

    return [
        "request_id": requestID,
        "protocol_version": omaBlueProtocolVersion,
        "server_version": omaBlueServerVersion,
        "source": source.json,
        "capabilities": [
            "read_messages": methodSet.contains("messages.after"),
            "watch_messages": methodSet.contains("watch.subscribe"),
            "send_text": false,
            "send_attachments": false,
            "send_reactions": false,
        ],
    ]
}

func translateSync(
    requestID: String,
    source: SourceIdentity,
    chatsResult: [String: Any],
    messagesResult: [String: Any]
) throws -> [String: Any] {
    guard
        let rawChats = chatsResult["chats"] as? [[String: Any]],
        let rawMessages = messagesResult["messages"] as? [[String: Any]],
        let nextRowID = unsignedInteger(messagesResult["next_rowid"]),
        let hasMore = messagesResult["has_more"] as? Bool
    else {
        throw AdapterFailure(code: "invalid_upstream_sync", retryable: true)
    }

    return [
        "request_id": requestID,
        "protocol_version": omaBlueProtocolVersion,
        "source": source.json,
        "conversations": try rawChats.map(translateChat),
        "messages": messages,
        "events": events,
        "next_cursor": [
            "source_instance": source.instance,
            "database_generation": source.databaseGeneration,
            "rowid": nextRowID,
        ],
        "has_more": hasMore,
    ]
}

func validateCursor(_ cursor: [String: Any], source: SourceIdentity) throws -> UInt64 {
    guard
        cursor["source_instance"] as? String == source.instance,
        cursor["database_generation"] as? String == source.databaseGeneration,
        let rowID = unsignedInteger(cursor["rowid"])
    else {
        throw AdapterFailure(code: "resync_required", retryable: false)
    }
    return rowID
}

private func translateChat(_ chat: [String: Any]) throws -> [String: Any] {
    guard
        let id = integer(chat["id"]),
        let rawService = chat["service"] as? String,
        let participants = chat["participants"] as? [String],
        let lastMessageAt = chat["last_message_at"] as? String
    else {
        throw AdapterFailure(code: "invalid_upstream_chat", retryable: true)
    }

    let contactName = nonemptyString(chat["contact_name"])
    let title = nonemptyString(chat["display_name"])
        ?? contactName
        ?? nonemptyString(chat["name"])
    let isGroup = (chat["is_group"] as? Bool) ?? (participants.count > 1)
    let participantModels: [[String: Any]] = participants.map { participant in
        [
            "id": participant,
            "display_name": !isGroup && participants.count == 1
                ? jsonValue(contactName)
                : NSNull(),
            "avatar_id": NSNull(),
        ]
    }

    return [
        "id": "chat:\(id)",
        "title": jsonValue(title),
        "service": jsonValue(service(rawService)),
        "participants": participantModels,
        "unread_count": jsonValue(integer(chat["unread_count"])),
        "last_message_at": jsonValue(nonempty(lastMessageAt)),
    ]
}

func translateMessage(_ message: [String: Any]) throws -> [String: Any] {
    guard
        let rowID = unsignedInteger(message["id"]),
        let chatID = integer(message["chat_id"]),
        let fromMe = message["is_from_me"] as? Bool,
        let createdAt = message["created_at"] as? String,
        let attachments = message["attachments"] as? [[String: Any]],
        let reactions = message["reactions"] as? [[String: Any]]
    else {
        throw AdapterFailure(code: "invalid_upstream_message", retryable: true)
    }

    let guid = nonemptyString(message["guid"])
    let sender = nonemptyString(message["sender"])
    return [
        "id": guid ?? "rowid:\(rowID)",
        "source_rowid": rowID,
        "conversation_id": "chat:\(chatID)",
        "direction": fromMe ? "outgoing" : "incoming",
        "sender_id": fromMe ? NSNull() : jsonValue(sender),
        "text": jsonValue(nonemptyString(message["text"])),
        "sent_at": createdAt,
        "delivered_at": NSNull(),
        "read_at": jsonValue(nonemptyString(message["date_read"])),
        "reply_to": jsonValue(
            nonemptyString(message["thread_originator_guid"])
                ?? nonemptyString(message["reply_to_guid"])
        ),
        "attachments": try attachments.map(translateAttachment),
        "reactions": try reactions.map(translateReaction),
    ]
}

func translateReactionEvent(
    _ message: [String: Any],
    source: SourceIdentity
) throws -> [String: Any] {
    guard
        let rowID = unsignedInteger(message["id"]),
        let target = nonemptyString(message["reacted_to_guid"]),
        let active = message["is_reaction_add"] as? Bool
    else {
        throw AdapterFailure(code: "invalid_upstream_reaction_event", retryable: true)
    }
    let rawType = nonemptyString(message["reaction_type"]) ?? "custom"
    let reaction: [String: Any]
    if rawType == "custom" {
        guard let emoji = nonemptyString(message["reaction_emoji"]) else {
            throw AdapterFailure(code: "invalid_upstream_reaction_event", retryable: true)
        }
        reaction = ["type": "emoji", "value": emoji]
    } else {
        reaction = ["type": rawType]
    }
    return [
        "protocol_version": omaBlueProtocolVersion,
        "event_id": "reaction:\(source.instance):\(source.databaseGeneration):\(rowID)",
        "cursor": [
            "source_instance": source.instance,
            "database_generation": source.databaseGeneration,
            "rowid": rowID,
        ],
        "recorded_at": ISO8601DateFormatter().string(from: Date()),
        "event_type": "reaction_changed",
        "message_id": target,
        "actor_id": jsonValue(nonemptyString(message["sender"])),
        "kind": reaction,
        "active": active,
    ]
}

func translateMessageEvent(
    _ rawMessage: [String: Any],
    source: SourceIdentity
) throws -> [String: Any] {
    guard let rowID = unsignedInteger(rawMessage["id"]) else {
        throw AdapterFailure(code: "invalid_upstream_message", retryable: true)
    }
    if rawMessage["is_reaction"] as? Bool == true {
        return try translateReactionEvent(rawMessage, source: source)
    }
    return [
        "protocol_version": omaBlueProtocolVersion,
        "event_id": "message:\(source.instance):\(source.databaseGeneration):\(rowID)",
        "cursor": [
            "source_instance": source.instance,
            "database_generation": source.databaseGeneration,
            "rowid": rowID,
        ],
        "recorded_at": ISO8601DateFormatter().string(from: Date()),
        "event_type": "message_upsert",
        "message": try translateMessage(rawMessage),
        "conversation": try translateConversationFromMessage(rawMessage),
    ]
}

func resyncRequiredEvent(cursor: [String: Any], source: SourceIdentity) -> [String: Any] {
    [
        "protocol_version": omaBlueProtocolVersion,
        "event_id": "resync:\(source.instance):\(source.databaseGeneration)",
        "cursor": cursor,
        "recorded_at": ISO8601DateFormatter().string(from: Date()),
        "event_type": "resync_required",
        "reason": "database_generation_changed",
    ]
}

private func translateConversationFromMessage(_ message: [String: Any]) throws -> [String: Any] {
    guard
        let chatID = integer(message["chat_id"]),
        let participants = message["participants"] as? [String],
        let createdAt = message["created_at"] as? String
    else {
        throw AdapterFailure(code: "invalid_upstream_message_chat", retryable: true)
    }
    let participantModels: [[String: Any]] = participants.map {
        ["id": $0, "display_name": NSNull(), "avatar_id": NSNull()]
    }
    return [
        "id": "chat:\(chatID)",
        "title": jsonValue(nonemptyString(message["chat_name"])),
        "service": NSNull(),
        "participants": participantModels,
        "unread_count": NSNull(),
        "last_message_at": createdAt,
    ]
}

private func translateAttachment(_ attachment: [String: Any]) throws -> [String: Any] {
    guard
        let byteCount = unsignedInteger(attachment["total_bytes"]),
        let missing = attachment["missing"] as? Bool
    else {
        throw AdapterFailure(code: "invalid_upstream_attachment", retryable: true)
    }
    let transferName = nonemptyString(attachment["transfer_name"])
    let storedName = nonemptyString(attachment["filename"])
        .map { URL(fileURLWithPath: $0).lastPathComponent }
    return [
        "id": NSNull(),
        "media_type": jsonValue(nonemptyString(attachment["mime_type"])),
        "byte_count": byteCount,
        "display_name": jsonValue(transferName ?? storedName),
        "available": !missing,
    ]
}

private func translateReaction(_ reaction: [String: Any]) throws -> [String: Any] {
    guard let rawType = reaction["type"] as? String else {
        throw AdapterFailure(code: "invalid_upstream_reaction", retryable: true)
    }
    let kind: [String: Any]
    switch rawType.lowercased() {
    case "love", "like", "dislike", "laugh", "emphasis", "question":
        kind = ["type": rawType.lowercased()]
    case "custom":
        guard let emoji = nonemptyString(reaction["emoji"]) else {
            throw AdapterFailure(code: "invalid_upstream_reaction", retryable: true)
        }
        kind = ["type": "emoji", "value": emoji]
    default:
        throw AdapterFailure(code: "unsupported_upstream_reaction", retryable: true)
    }
    return [
        "actor_id": jsonValue(nonemptyString(reaction["sender"])),
        "kind": kind,
    ]
}

private func service(_ value: String) -> String? {
    switch value.lowercased() {
    case "imessage": "imessage"
    case "sms": "sms"
    default: nil
    }
}

private func integer(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
        return nil
    }
    return number.intValue
}

private func unsignedInteger(_ value: Any?) -> UInt64? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.int64Value >= 0
    else {
        return nil
    }
    return number.uint64Value
}

private func nonemptyString(_ value: Any?) -> String? {
    guard let string = value as? String else { return nil }
    return nonempty(string)
}

private func nonempty(_ value: String) -> String? {
    value.isEmpty ? nil : value
}

private func jsonValue<T>(_ value: T?) -> Any {
    if let value { return value }
    return NSNull()
}
