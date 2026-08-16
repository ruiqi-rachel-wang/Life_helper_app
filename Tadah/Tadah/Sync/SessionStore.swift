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
    private static let sessionAccount = "session"
    // Legacy single-field items, cleared on sign-out so an old build's leftovers
    // can't linger.
    private static let tokenAccount = "sessionToken"
    private static let userAccount = "sessionUserID"

    static var token: String? { session?.token }
    static var userID: String? { session?.userID }
    static var isAuthenticated: Bool { session != nil }

    // ADOPT a freshly-issued session: ONE Keychain write, checked.
    //
    // This used to be three separate writes — a UserDefaults gate, then a token
    // item, then a user-id item — with every Keychain status ignored. That is not
    // a transaction: any of the three could fail (or UserDefaults could still be
    // pending) and leave a usable credential with nothing guarding it.
    //
    // Now the token, the user id and the setup phase live in a SINGLE Keychain
    // value, so the session literally cannot exist without its `setupComplete:
    // false` marker attached. The UserDefaults gate is still written first as the
    // fast path the sync loop reads, but it is no longer what makes this safe.
    //
    // THROWS, so a failed write is a failed sign-in rather than a half-adopted one.
    struct Session: Codable, Equatable {
        var token: String
        var userID: String
        var setupComplete: Bool
    }

    enum StoreError: Error { case keychain(OSStatus) }

    static func adopt(token: String, userID: String) throws {
        ReconciliationGate.block(.setupIncomplete, for: userID)
        try writeSession(Session(token: token, userID: userID, setupComplete: false))
    }

    static var session: Session? {
        guard let data = readData(sessionAccount) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    // Sign-in setup finished — stamp it on the same single Keychain value.
    //
    // Called as the last step of a completed reconciliation, alongside clearing
    // ReconciliationGate. The two must move together: the gate is the fast path,
    // this is the durable backstop.
    static func markSetupComplete() {
        guard var s = session, !s.setupComplete else { return }
        s.setupComplete = true
        try? writeSession(s)
    }

    // Is there a session that was issued but never finished setting up?
    //
    // ⚠️ THIS IS THE BACKSTOP FOR THE GATE, and it is not redundant with it.
    // `ReconciliationGate` lives in UserDefaults, which is written back to disk
    // lazily; the Keychain write below is synchronous. A hard kill in that window
    // can therefore lose the gate while KEEPING the credential — and the relaunch
    // would come up authenticated with nothing blocking a cross-account upload,
    // the exact scenario the gate exists to prevent. Because this flag is written
    // in the SAME value as the token, a session can never outlive its own marker.
    static var isSetupIncomplete: Bool {
        guard let s = session else { return false }
        return !s.setupComplete
    }

    // Non-throwing convenience, used by tests and the legacy path.
    static func save(token: String, userID: String) {
        try? writeSession(Session(token: token, userID: userID, setupComplete: true))
    }

    static func clear() {
        delete(sessionAccount)
        delete(tokenAccount)      // legacy single-field items from older builds
        delete(userAccount)
    }

    private static func writeSession(_ s: Session) throws {
        let data = try JSONEncoder().encode(s)
        let status = writeChecked(data, account: sessionAccount)
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
    }

    // MARK: - Keychain

    private static func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    @discardableResult
    private static func writeChecked(_ data: Data, account: String) -> OSStatus {
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(baseQuery(account) as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery(account)
            add.merge(attrs) { $1 }
            return SecItemAdd(add as CFDictionary, nil)
        }
        return status
    }

    private static func readData(_ account: String) -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
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
