import Foundation
import Security

struct TokenStore {
    private let service = "com.local.CopilotAICMenu"
    private let account = "github-fine-grained-token"

    private var identity: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func load() throws -> String? {
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8)
        else { throw TokenStoreError(status: status) }
        return token
    }

    func save(_ token: String) throws {
        let data = Data(token.utf8)
        let status = SecItemUpdate(identity as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = identity
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw TokenStoreError(status: addStatus) }
        } else if status != errSecSuccess {
            throw TokenStoreError(status: status)
        }
    }

    func remove() throws {
        let status = SecItemDelete(identity as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenStoreError(status: status)
        }
    }
}

private struct TokenStoreError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return "Keychain error: \(detail)"
    }
}
