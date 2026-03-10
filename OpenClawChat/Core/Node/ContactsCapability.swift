import Foundation
import Contacts

enum ContactsCapability {

    struct ContactResult: Encodable {
        let givenName: String
        let familyName: String
        let fullName: String
        let phoneNumbers: [String]
        let emailAddresses: [String]
        let organization: String?
    }

    struct AddContactResult: Encodable {
        let ok: Bool
        let identifier: String
    }

    enum ContactsError: LocalizedError {
        case denied
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .denied: return "Contacts permission denied"
            case .failed(let msg): return msg
            }
        }
    }

    static func search(query: String, limit: Int = 20) async throws -> [ContactResult] {
        let store = CNContactStore()

        // Request access
        let authorized = try await store.requestAccess(for: .contacts)
        guard authorized else { throw ContactsError.denied }

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        ]

        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        let lowercaseQuery = query.lowercased()

        var results: [ContactResult] = []

        try store.enumerateContacts(with: request) { contact, stop in
            let fullName = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
            let matchesName = fullName.lowercased().contains(lowercaseQuery)
            let matchesOrg = contact.organizationName.lowercased().contains(lowercaseQuery)
            let matchesEmail = contact.emailAddresses.contains { ($0.value as String).lowercased().contains(lowercaseQuery) }
            let matchesPhone = contact.phoneNumbers.contains { $0.value.stringValue.contains(query) }

            if matchesName || matchesOrg || matchesEmail || matchesPhone {
                results.append(ContactResult(
                    givenName: contact.givenName,
                    familyName: contact.familyName,
                    fullName: fullName,
                    phoneNumbers: contact.phoneNumbers.map(\.value.stringValue),
                    emailAddresses: contact.emailAddresses.map { $0.value as String },
                    organization: contact.organizationName.isEmpty ? nil : contact.organizationName
                ))
            }

            if results.count >= limit {
                stop.pointee = true
            }
        }

        return results
    }

    static func addContact(
        givenName: String?,
        familyName: String?,
        phoneNumber: String?,
        email: String?,
        organization: String?
    ) async throws -> AddContactResult {
        let store = CNContactStore()

        let authorized = try await store.requestAccess(for: .contacts)
        guard authorized else { throw ContactsError.denied }

        let contact = CNMutableContact()
        if let givenName { contact.givenName = givenName }
        if let familyName { contact.familyName = familyName }
        if let phoneNumber {
            contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: phoneNumber))]
        }
        if let email {
            contact.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: email as NSString)]
        }
        if let organization { contact.organizationName = organization }

        let saveRequest = CNSaveRequest()
        saveRequest.add(contact, toContainerWithIdentifier: nil)
        try store.execute(saveRequest)

        return AddContactResult(ok: true, identifier: contact.identifier)
    }
}

// MARK: - Params

struct ContactsSearchParams: Decodable {
    let query: String
    let limit: Int?
}

struct ContactsAddParams: Decodable {
    let givenName: String?
    let familyName: String?
    let phoneNumber: String?
    let email: String?
    let organization: String?
}
