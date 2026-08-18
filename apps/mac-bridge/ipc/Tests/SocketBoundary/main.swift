import Darwin
import Foundation

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("test failed: \(message)\n".utf8))
        exit(1)
    }
}

let directory = URL(fileURLWithPath: "/tmp")
    .appendingPathComponent("ob-\(UUID().uuidString)", isDirectory: true)
let socketURL = directory.appendingPathComponent("bridge.sock")
let server: BridgeSocketServer

do {
    server = try BridgeSocketServer(
        socketPath: socketURL.path,
        adapterURL: URL(fileURLWithPath: CommandLine.arguments[1])
    )
    try server.start()
    defer {
        server.stop()
        try? FileManager.default.removeItem(at: directory)
    }

    let socket = try UnixSocket.connect(path: socketURL.path)
    let peerUID = try UnixSocket.peerUID(socket)
    check(peerUID == geteuid(), "peer UID")
    let payload = Data(repeating: 0x41, count: 128 * 1024)
    try UnixSocket.sendAll(socket, data: payload)

    var received = Data()
    while let data = try UnixSocket.receive(socket) {
        received.append(data)
    }
    Darwin.close(socket)

    check(received == payload, "bounded bidirectional stream")
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: socketURL.path),
          let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
    else {
        FileHandle.standardError.write(Data("test failed: socket metadata\n".utf8))
        exit(1)
    }
    check(permissions == 0o600, "socket permissions")
    print("OmaBlue Unix socket boundary tests passed.")
} catch {
    FileHandle.standardError.write(Data("test failed: \(error)\n".utf8))
    exit(1)
}
