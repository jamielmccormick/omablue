import Foundation
import ServiceManagement

private let agentPlist = "com.jamielmccormick.omablue.feasibility-agent.plist"
private let service = SMAppService.agent(plistName: agentPlist)

private func statusName(_ status: SMAppService.Status) -> String {
    switch status {
    case .notRegistered:
        return "notRegistered"
    case .enabled:
        return "enabled"
    case .requiresApproval:
        return "requiresApproval"
    case .notFound:
        return "notFound"
    @unknown default:
        return "unknown"
    }
}

private func printStatus() {
    print(statusName(service.status))
}

let command = CommandLine.arguments.dropFirst().first ?? "status"

do {
    switch command {
    case "register":
        if service.status == .notRegistered || service.status == .notFound {
            try service.register()
        }
        printStatus()
    case "unregister":
        if service.status != .notRegistered {
            try service.unregister()
        }
        printStatus()
    case "status":
        printStatus()
    case "open-settings":
        SMAppService.openSystemSettingsLoginItems()
        printStatus()
    default:
        FileHandle.standardError.write(
            Data("usage: OmaBlueFeasibility [register|unregister|status|open-settings]\n".utf8)
        )
        exit(64)
    }
} catch {
    let nsError = error as NSError
    FileHandle.standardError.write(
        Data("service error: \(nsError.domain) \(nsError.code)\n".utf8)
    )
    exit(1)
}
