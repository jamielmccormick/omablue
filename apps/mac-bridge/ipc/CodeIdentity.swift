import Darwin
import Foundation
import Security

struct CodeIdentity: Equatable {
    let identifier: String
    let teamIdentifier: String?

    static func current() throws -> CodeIdentity {
        var code: SecCode?
        let status = SecCodeCopySelf([], &code)
        guard status == errSecSuccess, let code else {
            throw BridgeSocketError.codeSigning(status: status)
        }
        return try read(code)
    }

    static func atPath(_ path: String) throws -> CodeIdentity {
        var code: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(
            URL(fileURLWithPath: path) as CFURL,
            [],
            &code
        )
        guard createStatus == errSecSuccess, let code else {
            throw BridgeSocketError.codeSigning(status: createStatus)
        }
        let validityStatus = SecStaticCodeCheckValidity(code, [], nil)
        guard validityStatus == errSecSuccess else {
            throw BridgeSocketError.codeSigning(status: validityStatus)
        }
        return try read(staticCode: code)
    }

    func matchesPeer(_ descriptor: Int32) throws -> Bool {
        var pid: pid_t = 0
        var length = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(descriptor, 0, LOCAL_PEERPID, &pid, &length) == 0 else {
            throw BridgeSocketError.syscall(operation: "getsockopt", code: errno)
        }

        let attributes: CFDictionary = [
            kSecGuestAttributePid as String: NSNumber(value: pid),
        ] as CFDictionary
        var guest: SecCode?
        let guestStatus = SecCodeCopyGuestWithAttributes(nil, attributes, [], &guest)
        guard guestStatus == errSecSuccess, let guest else {
            throw BridgeSocketError.codeSigning(status: guestStatus)
        }

        return try CodeIdentity.read(guestCode: guest) == self
    }

    private static func read(_ code: SecCode) throws -> CodeIdentity {
        var staticCode: SecStaticCode?
        let status = SecCodeCopyStaticCode(code, [], &staticCode)
        guard status == errSecSuccess, let staticCode else {
            throw BridgeSocketError.codeSigning(status: status)
        }
        return try read(staticCode: staticCode)
    }

    private static func read(guestCode code: SecCode) throws -> CodeIdentity {
        try read(code)
    }

    private static func read(staticCode code: SecStaticCode) throws -> CodeIdentity {
        var information: CFDictionary?
        let status = SecCodeCopySigningInformation(code, [], &information)
        guard status == errSecSuccess, let information else {
            throw BridgeSocketError.codeSigning(status: status)
        }
        let values = information as NSDictionary
        guard let identifier = values[kSecCodeInfoIdentifier as String] as? String else {
            throw BridgeSocketError.unauthorizedPeer
        }
        let teamIdentifier = values[kSecCodeInfoTeamIdentifier as String] as? String
        return CodeIdentity(identifier: identifier, teamIdentifier: teamIdentifier)
    }
}
