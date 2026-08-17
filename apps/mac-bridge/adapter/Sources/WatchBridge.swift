import Foundation

struct WatchBridge {
    let executable: URL
    let initialSource: SourceIdentity
    let initialCursor: [String: Any]
    let emit: ([String: Any]) throws -> Void
    var loadSource: () throws -> SourceIdentity = loadSourceIdentity

    func run() throws {
        var cursor = try validateCursor(initialCursor, source: initialSource)
        var restartDelay: TimeInterval = 1

        while true {
            let source = try loadSource()
            guard source.instance == initialSource.instance,
                  source.databaseGeneration == initialSource.databaseGeneration
            else {
                try emit(resyncRequiredEvent(cursor: cursorJSON(cursor), source: source))
                return
            }

            var rpc: PersistentIMsgRPC?
            do {
                let child = try PersistentIMsgRPC(executable: executable)
                rpc = child
                _ = try child.call(
                    id: "initialize",
                    method: "initialize",
                    params: ["protocol_version": 1]
                )
                cursor = try catchUp(rpc: child, cursor: cursor, source: source)
                let subscription = try subscribe(rpc: child, cursor: cursor, source: source)
                restartDelay = 1

                while true {
                    guard let notification = try child.nextNotification(timeout: 30) else {
                        guard sameGeneration(source) else {
                            try emit(resyncRequiredEvent(cursor: cursorJSON(cursor), source: try loadSource()))
                            return
                        }
                        continue
                    }
                    guard let method = notification["method"] as? String,
                          let params = notification["params"] as? [String: Any]
                    else {
                        throw AdapterFailure(code: "invalid_watch_notification", retryable: true)
                    }

                    if method == "message" {
                        guard integerValue(params["subscription"]) == subscription,
                              let message = params["message"] as? [String: Any],
                              let rowID = unsignedValue(message["id"])
                        else {
                            throw AdapterFailure(code: "invalid_watch_message", retryable: true)
                        }
                        try emit(try translateMessageEvent(message, source: source))
                        cursor = max(cursor, rowID)
                    } else if method == "watch.overflow" {
                        guard integerValue(params["subscription"]) == subscription,
                              let resume = unsignedValue(params["resume_after_rowid"])
                        else {
                            throw AdapterFailure(code: "invalid_watch_overflow", retryable: true)
                        }
                        cursor = resume
                        break
                    } else if method == "watch.error" {
                        throw AdapterFailure(code: "upstream_watch_failed", retryable: true)
                    } else {
                        throw AdapterFailure(code: "unknown_watch_notification", retryable: true)
                    }
                }
                child.stop()
            } catch let failure as AdapterFailure {
                rpc?.stop()
                if failure.code == "database_generation_changed" {
                    try emit(
                        resyncRequiredEvent(cursor: cursorJSON(cursor), source: try loadSource())
                    )
                    return
                }
                if !failure.retryable { throw failure }
                guard sameGeneration(source) else {
                    try emit(resyncRequiredEvent(cursor: cursorJSON(cursor), source: try loadSource()))
                    return
                }
                Thread.sleep(forTimeInterval: restartDelay)
                restartDelay = min(restartDelay * 2, 30)
            }
        }
    }

    private func catchUp(
        rpc: PersistentIMsgRPC,
        cursor: UInt64,
        source: SourceIdentity
    ) throws -> UInt64 {
        var nextCursor = cursor
        while true {
            guard sameGeneration(source) else {
                throw AdapterFailure(code: "database_generation_changed", retryable: false)
            }
            let page = try rpc.call(
                id: "catchup-\(nextCursor)",
                method: "messages.after",
                params: [
                    "since_rowid": nextCursor,
                    "limit": 100,
                    "attachments": true,
                    "convert_attachments": false,
                    "include_reactions": true,
                ]
            )
            guard sameGeneration(source),
                  let messages = page["messages"] as? [[String: Any]],
                  let authoritativeCursor = unsignedValue(page["next_rowid"]),
                  let hasMore = page["has_more"] as? Bool
            else {
                throw AdapterFailure(code: "invalid_upstream_sync", retryable: true)
            }
            for message in messages {
                try emit(try translateMessageEvent(message, source: source))
            }
            nextCursor = authoritativeCursor
            if !hasMore { return nextCursor }
        }
    }

    private func subscribe(
        rpc: PersistentIMsgRPC,
        cursor: UInt64,
        source: SourceIdentity
    ) throws -> Int {
        let result = try rpc.call(
            id: "subscribe-\(cursor)",
            method: "watch.subscribe",
            params: [
                "since_rowid": cursor,
                "attachments": true,
                "include_reactions": true,
                "buffer_limit": 64,
                "debounce_ms": 500,
            ]
        )
        guard sameGeneration(source), let subscription = integerValue(result["subscription"]) else {
            throw AdapterFailure(code: "invalid_watch_subscription", retryable: true)
        }
        return subscription
    }

    private func sameGeneration(_ source: SourceIdentity) -> Bool {
        guard let current = try? loadSource() else { return false }
        return current.instance == source.instance
            && current.databaseGeneration == source.databaseGeneration
    }

    private func cursorJSON(_ rowID: UInt64) -> [String: Any] {
        [
            "source_instance": initialSource.instance,
            "database_generation": initialSource.databaseGeneration,
            "rowid": rowID,
        ]
    }
}

private func integerValue(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber else { return nil }
    return number.intValue
}

private func unsignedValue(_ value: Any?) -> UInt64? {
    guard let number = value as? NSNumber, number.int64Value >= 0 else { return nil }
    return number.uint64Value
}
