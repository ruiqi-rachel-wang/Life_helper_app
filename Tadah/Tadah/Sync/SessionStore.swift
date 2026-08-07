//  SessionStore.swift
//
//  Where the server session token lives. It's a real credential (it authorizes
//  /sync for this user), so it goes in the KEYCHAIN — not UserDefaults, which is
//  where the plain identity blob (Account) lives. Stored with
//  kSecAttrAccessibleAfterFirstUnlock so a background sync can read it.
//
//  The token is opaque and revocable server-side: signing in on another free
//  device revokes it, and the next /sync returns 401 (we then clear it here).
//

import Foundation
import Security

enum SessionStore {
    private static let service = "com.ruiqiwang.cuevi.session"
    private static let tokenAccount = "sessionToken"
    private static let userAccount = "sessionUserID"

    static var token: String? { read(tokenAccount) }
    static var userID: String? { read(userAccount) }
    static var isAuthenticated: Bool { token != nil }

    static func save(token: String, userID: String) {
        write(token, account: tokenAccount)
        write(userID, account: userAccount)
    }

    static func clear() {
        delete(tokenAccount)
        delete(userAccount)
    }

    // MARK: - Keychain (generic password items, one per field)

    private static func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func write(_ value: String, account: String) {
        let attrs: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(baseQuery(account) as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery(account)
            add.merge(attrs) { $1 }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private static func read(_ account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }
}
