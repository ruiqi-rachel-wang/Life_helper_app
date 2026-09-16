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
import RevenueCat

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
    // Kept beside the account blob rather than inside it: adding a field to a
    // Codable that is already on disk fails to decode on upgrade, which would
    // sign everyone out.
    private static let verifiedKey = "tadah.account.emailVerified"
    private let defaults: UserDefaults

    private(set) var account: Account?
    /// Whether the address on this account has been verified. Only Tadah Calls
    /// depends on it; everything else works unverified.
    private(set) var emailVerified = false
    var isSignedIn: Bool { account != nil }

    // Run after EVERY sign-out, however it happened. There are three routes out —
    // the person taps Log out, the server revokes the session, or the account is
    // deleted — and anything that must be forgotten has to be forgotten on all
    // three. Wiring it at one call site is how two of them get missed.
    //
    // Today this clears PlusStore, which otherwise keeps showing the departed
    // user's plan and renewal date to whoever holds the phone next. Set once at
    // launch; AccountStore stays unaware of what it is clearing.
    var didSignOut: (@MainActor () -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        emailVerified = defaults.bool(forKey: Self.verifiedKey)
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
    // user's data is still here when they sign back in. LocalDataOwner keeps
    // pointing at this account, which is what lets the next sign-in notice if a
    // DIFFERENT person signs in on the same phone.
    //
    // Synchronous, for the paths that can't await (and as the local half of
    // signOutEverywhere). Prefer signOutEverywhere: this leaves the server session
    // alive until it expires.
    func signOut() {
        account = nil
        setEmailVerified(false)
        SessionStore.clear()
        save()
    }

    /// From sign-in, or from the verification sheet. Cleared on sign-out, so
    /// the next person on this phone doesn't inherit someone else's proof.
    func setEmailVerified(_ verified: Bool) {
        emailVerified = verified
        defaults.set(verified, forKey: Self.verifiedKey)
    }

    // Sign out properly: revoke the session on the SERVER first, then clear it
    // locally, then tell RevenueCat this device is no longer that user.
    //
    // The local sign-out happens even if the network call fails — someone who taps
    // "log out" must end up logged out on the device regardless. Revocation is
    // retried implicitly by the session's own expiry.
    func signOutEverywhere() async {
        try? await AuthService.logout()
        signOut()
        // RevenueCat keeps the identified user until told otherwise, so without
        // this the next person on this phone can inherit the previous user's
        // entitlement (or the previous user's purchases follow a new account).
        _ = try? await Purchases.shared.logOut()
        didSignOut?()
    }

    // Signed out WITHOUT the user asking: the server revoked this session (a free
    // account signed in on another device), or sign-in setup failed and the
    // session was handed back.
    //
    // These paths used to call the plain `signOut()`, which leaves RevenueCat still
    // identified as the departed user — so the phone kept their Plus entitlement,
    // and whoever used it next got paid features they never bought. The reason the
    // session ended doesn't change what has to be cleaned up.
    func signOutAfterSessionEnded() async {
        signOut()
        _ = try? await Purchases.shared.logOut()
        didSignOut?()
    }

    // Delete the whole account: the backend verifies the password, deletes the
    // RevenueCat subscriber, then deletes our rows.
    //
    // Throws when any of that fails, so the caller can say "we couldn't delete your
    // account" instead of falsely confirming it. The local identity is cleared only
    // AFTER the server confirms — clearing first would leave someone believing
    // their data was gone while the backend still held all of it.
    //
    // Local items are NOT deleted here; the confirmation copy says so, and the
    // ownership claim deliberately stays (see LocalDataOwner) so a different
    // account signing in later can't silently adopt them.
    func deleteAccountEverywhere(password: String) async throws {
        try await AuthService.deleteAccount(password: password, email: account?.email)
        account = nil
        SessionStore.clear()
        save()
        _ = try? await Purchases.shared.logOut()
        didSignOut?()
    }

    // Let the user edit their own name/email on the Account Details screen.
    func updateProfile(name: String? = nil, email: String? = nil) {
        guard var a = account else { return }
        if let name { a.name = name }
        if let email { a.email = email }
        account = a
        save()
    }

    // Local-only half of deletion, kept for the no-backend case (simulator dev with
    // no Worker configured, where there is genuinely nothing on a server).
    // Everything else must go through deleteAccountEverywhere.
    func forgetLocally() {
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
