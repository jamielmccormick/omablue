import AppKit
import Foundation
import Contacts
import ServiceManagement

private let agentPlist = "com.jamielmccormick.omablue.agent.plist"
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

private func contactsStatusName(_ status: CNAuthorizationStatus) -> String {
    switch status {
    case .authorized:
        return "authorized"
    case .notDetermined:
        return "notDetermined"
    case .denied:
        return "denied"
    case .restricted:
        return "restricted"
    @unknown default:
        return "unknown"
    }
}

private func requestContacts() {
    let store = CNContactStore()
    guard CNContactStore.authorizationStatus(for: .contacts) == .notDetermined else {
        print(contactsStatusName(CNContactStore.authorizationStatus(for: .contacts)))
        return
    }

    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    store.requestAccess(for: .contacts) { _, _ in
        DispatchQueue.main.async {
            print(contactsStatusName(CNContactStore.authorizationStatus(for: .contacts)))
            application.terminate(nil)
        }
    }
    application.run()
}

let command = CommandLine.arguments.dropFirst().first ?? "request-contacts"

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
    case "request-contacts":
        requestContacts()
    case "open-settings":
        SMAppService.openSystemSettingsLoginItems()
        printStatus()
    default:
        FileHandle.standardError.write(
            Data("usage: OmaBlueController [register|unregister|status|open-settings]\n".utf8)
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
