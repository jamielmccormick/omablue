import Darwin
import Foundation

enum BridgeSocketError: Error, CustomStringConvertible {
    case invalidPath
    case syscall(operation: String, code: Int32)
    case unsafeEndpoint
    case unauthorizedPeer
    case codeSigning(status: OSStatus)

    var description: String {
        switch self {
        case .invalidPath: "invalid Unix socket path"
        case let .syscall(operation, code): "\(operation) failed with errno \(code)"
        case .unsafeEndpoint: "unsafe Unix socket endpoint"
        case .unauthorizedPeer: "unauthorized Unix socket peer"
        case let .codeSigning(status): "code-signing inspection failed with status \(status)"
        }
    }
}

enum UnixSocket {
    private static let pathCapacity = MemoryLayout.size(ofValue: sockaddr_un().sun_path)

    static func create() throws -> Int32 {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw BridgeSocketError.syscall(operation: "socket", code: errno)
        }

        var noSigPipe: Int32 = 1
        guard setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSigPipe,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw BridgeSocketError.syscall(operation: "setsockopt", code: code)
        }

        guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) >= 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw BridgeSocketError.syscall(operation: "fcntl", code: code)
        }
        return descriptor
    }

    static func bind(_ descriptor: Int32, path: String) throws {
        var address = try makeAddress(path: path)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            throw BridgeSocketError.syscall(operation: "bind", code: errno)
        }
    }

    static func connect(path: String) throws -> Int32 {
        let descriptor = try create()
        do {
            var address = try makeAddress(path: path)
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard result == 0 else {
                throw BridgeSocketError.syscall(operation: "connect", code: errno)
            }
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    static func peerUID(_ descriptor: Int32) throws -> uid_t {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(descriptor, &uid, &gid) == 0 else {
            throw BridgeSocketError.syscall(operation: "getpeereid", code: errno)
        }
        return uid
    }

    static func sendAll(_ descriptor: Int32, data: Data) throws {
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.send(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    buffer.count - offset,
                    0
                )
                if count > 0 {
                    offset += count
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    throw BridgeSocketError.syscall(operation: "send", code: errno)
                }
            }
        }
    }

    static func receive(_ descriptor: Int32, maximumBytes: Int = 16_384) throws -> Data? {
        var buffer = [UInt8](repeating: 0, count: maximumBytes)
        while true {
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.recv(descriptor, rawBuffer.baseAddress, rawBuffer.count, 0)
            }
            if count > 0 { return Data(buffer.prefix(count)) }
            if count == 0 { return nil }
            if errno == EINTR { continue }
            throw BridgeSocketError.syscall(operation: "recv", code: errno)
        }
    }

    private static func makeAddress(path: String) throws -> sockaddr_un {
        let bytes = Array(path.utf8)
        guard !bytes.isEmpty, bytes.count < pathCapacity, !bytes.contains(0) else {
            throw BridgeSocketError.invalidPath
        }

        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
            for (index, byte) in bytes.enumerated() {
                rawBuffer[index] = byte
            }
            rawBuffer[bytes.count] = 0
        }
        return address
    }
}
