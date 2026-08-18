import Contacts
import Foundation

final class ContactDirectory {
    private let store = CNContactStore()

    func namesByHandle() -> [String: String] {
        guard requestAccessIfNeeded() else { return [:] }

        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var result = [String: String]()

        do {
            try store.enumerateContacts(with: request) { contact, _ in
                let name = Self.displayName(for: contact)
                guard !name.isEmpty else { return }

                for phone in contact.phoneNumbers {
                    for key in normalizedContactKeys(phone.value.stringValue) where result[key] == nil {
                        result[key] = name
                    }
                }
                for email in contact.emailAddresses {
                    for key in normalizedContactKeys(String(email.value)) where result[key] == nil {
                        result[key] = name
                    }
                }
            }
        } catch {
            return [:]
        }
        return result
    }

    private func requestAccessIfNeeded() -> Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            return true
        case .notDetermined:
            let semaphore = DispatchSemaphore(value: 0)
            var granted = false
            store.requestAccess(for: .contacts) { value, _ in
                granted = value
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 15)
            return granted
        default:
            return false
        }
    }

    private static func displayName(for contact: CNContact) -> String {
        let name = [contact.givenName, contact.familyName]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
        if !name.isEmpty { return name }
        if !contact.nickname.isEmpty { return contact.nickname }
        return contact.organizationName
    }
}
