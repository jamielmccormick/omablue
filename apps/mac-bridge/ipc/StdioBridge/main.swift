import Darwin
import Foundation

private func socketPath() -> String {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/OmaBlue/bridge.sock")
        .path
}

guard CommandLine.arguments.count == 1,
      ProcessInfo.processInfo.environment["SSH_ORIGINAL_COMMAND", default: ""].isEmpty
else {
    exit(64)
}

do {
    let socket = try UnixSocket.connect(path: socketPath())
    defer { Darwin.close(socket) }

    guard try UnixSocket.peerUID(socket) == geteuid() else {
        throw BridgeSocketError.unauthorizedPeer
    }

    let pumps = DispatchGroup()
    pumps.enter()
    DispatchQueue.global(qos: .userInitiated).async {
        defer {
            try? UnixSocket.sendAll(socket, data: Data([0x04]))
            Darwin.shutdown(socket, SHUT_WR)
            pumps.leave()
        }
        do {
            while let data = try FileHandle.standardInput.read(upToCount: 16_384), !data.isEmpty {
                try UnixSocket.sendAll(socket, data: data)
            }
        } catch {}
    }

    pumps.enter()
    DispatchQueue.global(qos: .userInitiated).async {
        defer {
            try? FileHandle.standardInput.close()
            pumps.leave()
        }
        do {
            while let data = try UnixSocket.receive(socket) {
                try FileHandle.standardOutput.write(contentsOf: data)
            }
        } catch {}
    }

    pumps.wait()
} catch {
    FileHandle.standardError.write(Data("bridge stdio failed: \(error)\n".utf8))
    exit(1)
}
