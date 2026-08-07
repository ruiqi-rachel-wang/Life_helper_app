//  Account.swift
//
//  The signed-in identity (Part 3, phase 1 — free accounts). Deliberately small:
//  an account is pure RETENTION, not a paid feature. Its only job right now is to
//  let a user's data survive sign-out/sign-in on this device — one profile, one
//  device. Family sharing (multi-profile) and cloud sync (multi-device / new
//  phone) come later and are the Tadah Plus line.
//
//  Sign-out NEVER deletes the on-device items — signing back in re-associates them
//  (trivially, since it's one device). So "your data survives" is just: keep the
//  local store, only clear the stored identity.
//
//  Storage: a single Codable blob in UserDefaults. The provider user id is an
//  opaque identifier (not a password or token), so UserDefaults is acceptable for
//  now; move to the Keychain if we ever store real credentials.
//

import Foundation
import Observation

// A signed-in identity from one auth provider. `name`/`email` can be empty —
// Sign in with Apple only hands them over on the FIRST authorization, so we store
// whatever we get and never assume they're present.
struct Account: Codable, Equatable {
    enum Provider: String, Codable { case apple, google, email }

    var userID: String          // stable, provider-scoped identifier
    var provider: Provider
    var name: String            // may be "" (Apple gives it once, at first sign-in)
    var email: String           // may be "" or an Apple private-relay address

    // A friendly label for the profile row: the name, else the email, else a
    // generic fallback (an Apple account that shared neither).
    var displayName: String {
        if !name.isEmpty { return name }
        if !email.isEmpty { return email }
        return String(localized: "Signed in")
    }

    // Two-letter avatar initials from the name, else the email's first letter.
    var initials: String {
        let source = !name.isEmpty ? name : email
        let parts = source.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "•" : letters.uppercased()
    }
}

@MainActor
@Observable
final class AccountStore {
    private static let storageKey = "tadah.account.v1"
    private let defaults: UserDefaults

    private(set) var account: Account?
    var isSignedIn: Bool { account != nil }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // Sign in (or refresh the stored identity after a re-authorization). Apple
    // may return an empty name/email on later sign-ins even though we captured
    // them the first time — so keep any earlier non-empty value rather than
    // overwriting it with a blank.
    func signIn(_ incoming: Account) {
        if let existing = account, existing.userID == incoming.userID {
            var merged = incoming
            if merged.name.isEmpty { merged.name = existing.name }
            if merged.email.isEmpty { merged.email = existing.email }
            account = merged
        } else {
            account = incoming
        }
        save()
    }

    // Clear the identity only — the local SwiftData items are untouched, so the
    // user's data is still here when they sign back in. Also drops the server
    // session credential (Part 3); RevenueCat is logged out at the UI layer.
    func signOut() {
        account = nil
        SessionStore.clear()
        save()
    }

    // Let the user edit their own name/email on the Account Details screen.
    func updateProfile(name: String? = nil, email: String? = nil) {
        guard var a = account else { return }
        if let name { a.name = name }
        if let email { a.email = email }
        account = a
        save()
    }

    // For the free, local tier there's no server record to delete — "delete
    // account" just forgets the stored identity on this device (and the server
    // session credential; RevenueCat is logged out at the UI layer).
    func deleteAccount() {
        account = nil
        SessionStore.clear()
        save()
    }

    // MARK: persistence

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode(Account.self, from: data) else { return }
        account = decoded
    }

    private func save() {
        if let account, let data = try? JSONEncoder().encode(account) {
            defaults.set(data, forKey: Self.storageKey)
        } else {
            defaults.removeObject(forKey: Self.storageKey)
        }
    }
}
