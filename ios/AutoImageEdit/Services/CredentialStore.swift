import Foundation
import Security

/// Keychain-backed storage for the Apple identity token used as the backend bearer token.
final class CredentialStore {
    static let shared = CredentialStore()

    private let service = "com.hanlinsunn.imageedit.identity"
    private let account = "apple-identity-token"

    var identityToken: String? {
        get { read() }
        set {
            if let newValue {
                write(newValue)
            } else {
                delete()
            }
        }
    }

    private func read() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ token: String) {
        delete()
        var query = baseQuery()
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    private func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
