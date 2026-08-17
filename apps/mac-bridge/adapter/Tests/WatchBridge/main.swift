import Foundation

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("test failed: \(message)\n".utf8))
        exit(1)
    }
}

let source = SourceIdentity(instance: "source-example", databaseGeneration: "generation-example")
let cursor: [String: Any] = [
    "source_instance": source.instance,
    "database_generation": source.databaseGeneration,
    "rowid": 10,
]
var eventIDs = [String]()
setenv("OMABLUE_FAKE_MODE", "watch", 1)

let bridge = WatchBridge(
    executable: URL(fileURLWithPath: CommandLine.arguments[1]),
    initialSource: source,
    initialCursor: cursor,
    emit: { event in
        if let eventID = event["event_id"] as? String {
            eventIDs.append(eventID)
        }
        if eventIDs.count == 3 {
            throw AdapterFailure(code: "test_complete", retryable: false)
        }
    },
    loadSource: { source }
)

do {
    try bridge.run()
    check(false, "watch unexpectedly completed")
} catch let failure as AdapterFailure {
    check(failure.code == "test_complete", "unexpected watch failure")
}

check(eventIDs.count == 3, "event count")
check(eventIDs[0].hasSuffix(":11"), "initial catchup")
check(eventIDs[1].hasSuffix(":12"), "live message")
check(eventIDs[2].hasSuffix(":13"), "overflow catchup")
print("OmaBlue watch recovery tests passed.")
