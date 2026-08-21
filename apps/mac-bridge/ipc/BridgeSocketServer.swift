import Darwin
import Foundation

private let bridgeDebug = ProcessInfo.processInfo.environment["OMABLUE_BRIDGE_DEBUG"] == "1"

private func debugLog(_ message: String) {
    guard bridgeDebug else { return }
    FileHandle.standardError.write(Data("[bridge] \(message)\n".utf8))
}

final class BridgeSocketServer: @unchecked Sendable {
    private let socketPath: String
    private let adapterURL: URL
    private let expectedIdentity: CodeIdentity
    private let stateLock = NSLock()
    private var listener: Int32 = -1
    private var lockFile: Int32 = -1
    private let sessionSlot = DispatchSemaphore(value: 1)
    private var stopped = false

    init(socketPath: String, adapterURL: URL) throws {
        self.socketPath = socketPath
        self.adapterURL = adapterURL
        self.expectedIdentity = try CodeIdentity.current()
    }

    func start() throws {
        var descriptor: Int32 = -1
        do {
            try prepareDirectory()
            try acquireLock()
            try validateAdapter()
            try removeStaleSocket()

            descriptor = try UnixSocket.create()
            let previousMask = umask(0o177)
            defer { umask(previousMask) }
            try UnixSocket.bind(descriptor, path: socketPath)
            guard chmod(socketPath, 0o600) == 0 else {
                throw BridgeSocketError.syscall(operation: "chmod", code: errno)
            }
            guard Darwin.listen(descriptor, 4) == 0 else {
                throw BridgeSocketError.syscall(operation: "listen", code: errno)
            }
            try validateSocket()
            listener = descriptor
            descriptor = -1
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.acceptLoop()
            }
        } catch {
            if descriptor >= 0 { Darwin.close(descriptor) }
            removeSocketIfOwned()
            releaseLock()
            throw error
        }
    }

    func stop() {
        stateLock.lock()
        stopped = true
        let descriptor = listener
        listener = -1
        stateLock.unlock()

        if descriptor >= 0 {
            Darwin.shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
        }
        removeSocketIfOwned()
        releaseLock()
    }

    private func acceptLoop() {
        while true {
            stateLock.lock()
            let descriptor = listener
            let shouldStop = stopped
            stateLock.unlock()
            if shouldStop || descriptor < 0 { return }

            let client = Darwin.accept(descriptor, nil, nil)
            if client < 0 {
                debugLog("accept failed errno=\(errno)")
                if errno == EINTR { continue }
                return
            }
            _ = fcntl(client, F_SETFD, FD_CLOEXEC)

            do {
                guard try UnixSocket.peerUID(client) == geteuid() else {
                    throw BridgeSocketError.unauthorizedPeer
                }
                guard try expectedIdentity.matchesPeer(client) else {
                    debugLog("peer identity mismatch")
                    throw BridgeSocketError.unauthorizedPeer
                }
            } catch {
                debugLog("peer rejected: \(error)")
                Darwin.close(client)
                continue
            }

            // Serialize sessions with a bounded wait instead of dropping
            // concurrent clients, so a slow in-flight request never surfaces
            // as a silent EOF on the helper side.
            let waitResult = sessionSlot.wait(timeout: .now() + Self.slotWaitSeconds)
            guard waitResult == .success else {
                debugLog("session slot timeout; closing client")
                Darwin.close(client)
                continue
            }
            debugLog("accepted client fd=\(client)")

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.serve(client)
            }
        }
    }

    private func serve(_ client: Int32) {
        defer {
            Darwin.close(client)
            sessionSlot.signal()
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = adapterURL
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            debugLog("adapter spawn failed: \(error)")
            return
        }
        debugLog("adapter spawned pid=\(process.processIdentifier)")

        let terminationLock = NSLock()
        var terminated = false
        let terminate = { [adapterPID = process.processIdentifier] in
            terminationLock.lock()
            if !terminated {
                terminated = true
                debugLog("terminate; adapter=\(adapterPID)")
                if process.isRunning { process.terminate() }
                Darwin.shutdown(client, SHUT_RDWR)
            }
            terminationLock.unlock()
        }

        // Hard cap so a wedged adapter can never pin activeSession forever.
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + Self.maxSessionSeconds
        ) {
            terminate()
        }
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + Self.maxSessionSeconds + 5
        ) {
            terminationLock.lock()
            if !terminated && process.isRunning {
                debugLog("escalate to SIGKILL; adapter=\(process.processIdentifier)")
                _ = Darwin.kill(process.processIdentifier, SIGKILL)
            }
            terminationLock.unlock()
        }

        let pumps = DispatchGroup()
        pumps.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer {
                try? input.fileHandleForWriting.close()
                pumps.leave()
            }
            var gracefulInputClose = false
            do {
                while let data = try UnixSocket.receive(client) {
                    debugLog("input \(data.count)B")
                    if let marker = data.firstIndex(of: 0x04) {
                        guard marker == data.index(before: data.endIndex) else {
                            throw BridgeSocketError.unauthorizedPeer
                        }
                        let payload = data[..<marker]
                        if !payload.isEmpty {
                            try input.fileHandleForWriting.write(contentsOf: payload)
                        }
                        gracefulInputClose = true
                        break
                    }
                    try input.fileHandleForWriting.write(contentsOf: data)
                }
                if !gracefulInputClose {
                    debugLog("input EOF without EOT")
                }
            } catch {
                debugLog("input error: \(error)")
            }
            if !gracefulInputClose {
                terminate()
            }
        }

        pumps.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { pumps.leave() }
            do {
                while let data = try output.fileHandleForReading.read(upToCount: 16_384), !data.isEmpty {
                    debugLog("output \(data.count)B")
                    try UnixSocket.sendAll(client, data: data)
                }
                debugLog("output EOF")
            } catch {
                debugLog("output error: \(error)")
            }
            terminate()
        }

        pumps.wait()
        terminate()
        process.waitUntilExit()
        debugLog("session ended; adapter exit=\(process.terminationStatus)")
    }

    private static let maxSessionSeconds: TimeInterval = 180
    private static let slotWaitSeconds: DispatchTimeInterval = .seconds(30)

    private func prepareDirectory() throws {
        let directory = URL(fileURLWithPath: socketPath).deletingLastPathComponent().path
        if pathInfo(directory) == nil {
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        guard let info = pathInfo(directory),
              info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == geteuid(),
              info.st_mode & 0o077 == 0
        else {
            throw BridgeSocketError.unsafeEndpoint
        }
    }

    private func acquireLock() throws {
        let lockPath = URL(fileURLWithPath: socketPath)
            .deletingLastPathComponent()
            .appendingPathComponent("bridge.lock").path
        let descriptor = Darwin.open(lockPath, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else {
            throw BridgeSocketError.syscall(operation: "open", code: errno)
        }
        guard let info = fstatInfo(descriptor),
              info.st_uid == geteuid(),
              info.st_mode & 0o077 == 0,
              flock(descriptor, LOCK_EX | LOCK_NB) == 0
        else {
            let code = errno
            Darwin.close(descriptor)
            if code == EWOULDBLOCK || code == EAGAIN {
                throw BridgeSocketError.unsafeEndpoint
            }
            throw BridgeSocketError.syscall(operation: "flock", code: code)
        }
        lockFile = descriptor
    }

    private func removeStaleSocket() throws {
        guard let info = pathInfo(socketPath) else { return }
        guard info.st_mode & S_IFMT == S_IFSOCK,
              info.st_uid == geteuid(),
              info.st_mode & 0o077 == 0
        else {
            throw BridgeSocketError.unsafeEndpoint
        }

        do {
            let descriptor = try UnixSocket.connect(path: socketPath)
            Darwin.close(descriptor)
            throw BridgeSocketError.unsafeEndpoint
        } catch let error as BridgeSocketError {
            guard case let .syscall(_, code) = error, code == ECONNREFUSED else {
                throw error
            }
        }
        guard unlink(socketPath) == 0 else {
            throw BridgeSocketError.syscall(operation: "unlink", code: errno)
        }
    }

    private func validateAdapter() throws {
        guard try CodeIdentity.atPath(adapterURL.path) == expectedIdentity else {
            throw BridgeSocketError.unauthorizedPeer
        }
    }

    private func validateSocket() throws {
        guard let info = pathInfo(socketPath),
              info.st_mode & S_IFMT == S_IFSOCK,
              info.st_uid == geteuid(),
              info.st_mode & 0o077 == 0
        else {
            throw BridgeSocketError.unsafeEndpoint
        }
    }

    private func removeSocketIfOwned() {
        guard let info = pathInfo(socketPath),
              info.st_mode & S_IFMT == S_IFSOCK,
              info.st_uid == geteuid()
        else { return }
        _ = unlink(socketPath)
    }

    private func releaseLock() {
        guard lockFile >= 0 else { return }
        _ = flock(lockFile, LOCK_UN)
        Darwin.close(lockFile)
        lockFile = -1
    }

    private func pathInfo(_ path: String) -> stat? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return info
    }

    private func fstatInfo(_ descriptor: Int32) -> stat? {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { return nil }
        return info
    }
}
