import Foundation

private func imsgURL() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["OMABLUE_IMSG_PATH"] {
        return URL(fileURLWithPath: override)
    }
    guard let resources = Bundle.main.resourceURL else {
        throw AdapterFailure(code: "upstream_unavailable", retryable: true)
    }
    return resources.appendingPathComponent("imsg/imsg")
}

private func rpcRequest(id: String, method: String, params: [String: Any] = [:]) -> [String: Any] {
    ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
}

private func runRequest(_ request: AdapterRequest) throws -> [String: Any] {
    let source = try loadSourceIdentity()
    let rpc = IMsgRPC(executable: try imsgURL())

    switch request {
    case let .status(requestID):
        let responses = try rpc.call([rpcRequest(id: "status", method: "status")])
        guard let status = responses["status"] else {
            throw AdapterFailure(code: "missing_upstream_response", retryable: true)
        }
        return try translateStatus(requestID: requestID, source: source, result: status)

    case let .sync(requestID, cursor, limit):
        let sinceRowID = try cursor.map { try validateCursor($0, source: source) } ?? 0
        let responses = try rpc.call([
            rpcRequest(id: "chats", method: "chats.list", params: ["limit": 100]),
            rpcRequest(
                id: "messages",
                method: "messages.after",
                params: [
                    "since_rowid": sinceRowID,
                    "limit": limit,
                    "attachments": true,
                    "convert_attachments": false,
                    "include_reactions": true,
                ]
            ),
        ])
        guard let chats = responses["chats"], let messages = responses["messages"] else {
            throw AdapterFailure(code: "missing_upstream_response", retryable: true)
        }
        return try translateSync(
            requestID: requestID,
            source: source,
            chatsResult: chats,
            messagesResult: messages
        )
    case .watch:
        throw AdapterFailure(code: "watch_requires_stream", retryable: false)
    }
}

private func runWatch(_ request: AdapterRequest) throws {
    guard case let .watch(_, cursor) = request else {
        throw AdapterFailure(code: "invalid_watch_request", retryable: false)
    }
    let source = try loadSourceIdentity()
    let bridge = WatchBridge(
        executable: try imsgURL(),
        initialSource: source,
        initialCursor: cursor
    ) { event in
        let data = try JSONSerialization.data(withJSONObject: event, options: [.sortedKeys])
        try FileHandle.standardOutput.write(contentsOf: data + Data([0x0A]))
    }
    try bridge.run()
}

do {
    guard let input = try FileHandle.standardInput.read(upToCount: 65_537), !input.isEmpty else {
        throw AdapterFailure(code: "invalid_request", retryable: false)
    }
    let request = try parseRequest(input)
    if case .watch = request {
        try runWatch(request)
    } else {
        let response = try runRequest(request)
        let data = try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
        try FileHandle.standardOutput.write(contentsOf: data + Data([0x0A]))
    }
} catch let failure as AdapterFailure {
    let data = try JSONSerialization.data(
        withJSONObject: errorResponse(requestID: nil, failure: failure),
        options: [.sortedKeys]
    )
    try FileHandle.standardOutput.write(contentsOf: data + Data([0x0A]))
    exit(1)
} catch {
    let failure = AdapterFailure(code: "internal_error", retryable: false)
    let data = try JSONSerialization.data(
        withJSONObject: errorResponse(requestID: nil, failure: failure),
        options: [.sortedKeys]
    )
    try FileHandle.standardOutput.write(contentsOf: data + Data([0x0A]))
    exit(1)
}
