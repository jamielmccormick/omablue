import Foundation

private func emit(_ object: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: object)
    FileHandle.standardOutput.write(data + Data([0x0A]))
}

private func message(_ id: Int) -> [String: Any] {
    [
        "id": id,
        "chat_id": 7,
        "guid": "message-\(id)",
        "sender": "+15550000001",
        "is_from_me": false,
        "text": "synthetic",
        "created_at": "2026-08-16T12:00:00Z",
        "attachments": [],
        "reactions": [],
        "chat_identifier": "+15550000001",
        "chat_guid": "iMessage;-;+15550000001",
        "chat_name": "Synthetic",
        "participants": ["+15550000001"],
        "is_group": false,
    ]
}

let mode = ProcessInfo.processInfo.environment["OMABLUE_FAKE_MODE"] ?? "persistent"

while let line = readLine() {
    guard
        let data = line.data(using: .utf8),
        let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let id = request["id"] as? String,
        let method = request["method"] as? String
    else {
        exit(1)
    }

    switch method {
    case "initialize":
        emit([
            "jsonrpc": "2.0",
            "id": id,
            "result": ["version": "0.14.1", "methods": ["messages.after", "watch.subscribe"]],
        ])
    case "status":
        emit([
            "jsonrpc": "2.0",
            "id": id,
            "result": ["version": "0.14.1", "methods": ["messages.after", "watch.subscribe"]],
        ])
    case "messages.after":
        if mode == "watch" {
            let params = request["params"] as? [String: Any]
            let since = (params?["since_rowid"] as? NSNumber)?.intValue ?? 0
            let next = since == 10 ? 11 : 13
            emit([
                "jsonrpc": "2.0",
                "id": id,
                "result": ["messages": [message(next)], "next_rowid": next, "has_more": false],
            ])
        } else {
            emit([
                "jsonrpc": "2.0",
                "method": "message",
                "params": ["subscription": 7, "message": ["id": 11]],
            ])
            emit([
                "jsonrpc": "2.0",
                "id": id,
                "result": ["messages": [], "next_rowid": 10, "has_more": false],
            ])
        }
    case "watch.subscribe":
        emit([
            "jsonrpc": "2.0",
            "id": id,
            "result": ["subscription": 7, "buffer_limit": 64],
        ])
        if mode == "watch" {
            emit([
                "jsonrpc": "2.0",
                "method": "message",
                "params": ["subscription": 7, "message": message(12)],
            ])
            emit([
                "jsonrpc": "2.0",
                "method": "watch.overflow",
                "params": [
                    "subscription": 7,
                    "resume_after_rowid": 12,
                    "reason": "buffer_limit_exceeded",
                    "terminal": true,
                ],
            ])
        }
    default:
        emit([
            "jsonrpc": "2.0",
            "id": id,
            "error": ["code": -32601, "message": "synthetic"],
        ])
    }
}
