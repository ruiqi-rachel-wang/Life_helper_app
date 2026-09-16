//  AuthService.swift
//
//  Talks to the Worker about accounts: register, sign in, sign out, reset a
//  password, delete. The Worker checks the tier via RevenueCat, enforces the
//  free = 1-device rule, and returns a session token, which we persist to the
//  Keychain (SessionStore).
//
//  Best-effort by design: if no Worker is configured (simulator dev) or it's
//  unreachable, this throws and the caller ignores it — local sign-in still works
//  and the app stays fully on-device until sync is available.
//

import Foundation

enum AuthService {
    struct Session {
        let token: String
        let userID: String
        let plus: Bool
        /// Whether the address on the account has been verified. Tadah Calls
        /// refuses an unverified address, and nothing else depends on it.
        let verified: Bool
        let hasServerData: Bool   // did the account already have tasks on the server?
    }

    enum AuthError: Error { case notConfigured, badToken, noSession, server(Int), decode }

    // Sign in with Apple was REMOVED on 2026-08-15 (see SignInView for why: it
    // authenticates the device's Apple ID, so a family member could never reach a
    // shared account). No Apple account can exist — accounts never shipped — so
    // there is nothing to keep a compatibility path for.

    // Sign out on the SERVER, so the session token stops working the moment the
    // user signs out rather than staying valid until it expires. Throws so the
    // caller can decide; the local sign-out proceeds regardless (a user who taps
    // "log out" must always end up logged out on the device).
    static func logout() async throws {
        guard let token = SessionStore.token else { return }   // nothing to revoke
        try await logout(token: token)
    }

    // Revoke a SPECIFIC token. Needed when sign-in setup fails: the session has to
    // be cleared from the Keychain *first* (so nothing can use it, even after a
    // relaunch), which means the token is no longer readable from SessionStore by
    // the time we get to revoke it. The caller keeps it and passes it here.
    static func logout(token: String) async throws {
        guard let endpoint = BackendConfig.logoutEndpoint else { throw AuthError.notConfigured }
        // 401 is FINE here: it means the session is already dead server-side, which
        // is exactly what logging out is trying to achieve.
        _ = try await send(to: endpoint, session: token, treat401AsDone: true)
    }

    // Delete the account and ALL of its server data (tasks, profiles, sessions).
    // Apple requires an in-app path that deletes the account itself, not just the
    // local copy of it.
    //
    // Re-authenticates with the PASSWORD: deleting is irreversible and takes every
    // to-do with it, so it must not be possible with a borrowed unlocked phone.
    static func deleteAccount(password: String, email: String?) async throws {
        guard let endpoint = BackendConfig.accountDeleteEndpoint else { throw AuthError.notConfigured }
        guard let token = SessionStore.token else { throw AuthError.noSession }

        // Derived here, exactly as at sign-in — the password never travels.
        let address = (email ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let body = ["derivedKey": try await Task.detached(priority: .userInitiated) {
            try PasswordCrypto.derive(password: password, email: address)
        }.value]

        // 401 is NOT success here. An expired session, or a wrong password, means
        // the server authenticated nobody and therefore deleted NOTHING —
        // reporting that as done would tell someone their data is gone while we
        // still hold all of it.
        _ = try await send(to: endpoint, session: token,
                           body: body, treat401AsDone: false)
    }

    // MARK: - email verification

    // An unverified address is an unowned one: anyone can type a stranger's. Tadah
    // Calls hands that person an agent that phones real businesses and speaks as
    // them, so it refuses to call until the address is proved. Both routes are
    // authenticated by the SESSION, never by a typed address, so a code can only
    // ever go to the address already on the account.

    /// Ask for a six-digit code. Returns true when the address was already
    /// verified, in which case nothing was sent.
    @discardableResult
    static func requestEmailVerification() async throws -> Bool {
        guard let endpoint = BackendConfig.verifyRequestEndpoint else { throw AuthError.notConfigured }
        guard let token = SessionStore.token else { throw AuthError.noSession }
        let data = try await send(to: endpoint, session: token, treat401AsDone: false)
        return (try? JSONDecoder().decode(VerifyResponse.self, from: data))?.verified ?? false
    }

    /// Hand the code back. Returns true once the address is verified.
    static func confirmEmailVerification(code: String) async throws -> Bool {
        guard let endpoint = BackendConfig.verifyConfirmEndpoint else { throw AuthError.notConfigured }
        guard let token = SessionStore.token else { throw AuthError.noSession }
        let data = try await send(to: endpoint, session: token,
                                  body: ["code": code.trimmingCharacters(in: .whitespacesAndNewlines)],
                                  treat401AsDone: false)
        return (try? JSONDecoder().decode(VerifyResponse.self, from: data))?.verified ?? false
    }

    // MARK: - email + password

    // Create an account, or sign into an existing one. Everything downstream (SessionStore, the
    // reconciliation gate, sync) only ever cared about a token and a user id, so
    // swapping the auth method touches nothing beyond this file and the sign-in
    // screen.
    //
    // `password` is derived HERE and never sent — see PasswordCrypto for why the
    // expensive part runs on the phone.
    @discardableResult
    static func register(email: String, password: String, deviceID: String) async throws -> Session {
        try await emailAuth(endpoint: BackendConfig.registerEndpoint,
                            email: email, password: password, deviceID: deviceID,
                            includeIterations: true)
    }

    @discardableResult
    static func logIn(email: String, password: String, deviceID: String) async throws -> Session {
        try await emailAuth(endpoint: BackendConfig.loginEndpoint,
                            email: email, password: password, deviceID: deviceID,
                            includeIterations: false)
    }

    // Ask for a reset code. Succeeds whether or not the address is registered —
    // the Worker answers identically on purpose, so this can't be used to find out
    // who has an account. The UI must say "if that address has an account…"
    // rather than "we've sent you a code".
    static func requestPasswordReset(email: String) async throws {
        guard let endpoint = BackendConfig.resetRequestEndpoint else { throw AuthError.notConfigured }
        _ = try await postJSON(endpoint, [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
        ])
    }

    // Use the emailed code to set a new password. Every session is revoked
    // server-side, so the user signs in again afterwards — including on this
    // device, which is the point of resetting.
    static func confirmPasswordReset(email: String, code: String, newPassword: String) async throws {
        guard let endpoint = BackendConfig.resetConfirmEndpoint else { throw AuthError.notConfigured }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let derived = try await Task.detached(priority: .userInitiated) {
            try PasswordCrypto.derive(password: newPassword, email: address)
        }.value
        _ = try await postJSON(endpoint, [
            "email": address,
            "code": code.trimmingCharacters(in: .whitespacesAndNewlines),
            "derivedKey": derived,
            "iterations": PasswordCrypto.iterations,
        ])
    }

    // Unauthenticated POST — the reset routes run before there's a session.
    @discardableResult
    private static func postJSON(_ endpoint: URL, _ payload: [String: Any]) async throws -> Data {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !BackendConfig.proxyToken.isEmpty {
            req.setValue(BackendConfig.proxyToken, forHTTPHeaderField: "X-Cuevi-Token")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AuthError.server(-1) }
        guard (200..<300).contains(http.statusCode) else { throw AuthError.server(http.statusCode) }
        return data
    }

    private static func emailAuth(endpoint: URL?,
                                  email: String,
                                  password: String,
                                  deviceID: String,
                                  includeIterations: Bool) async throws -> Session {
        guard let endpoint else { throw AuthError.notConfigured }
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // 600k iterations of PBKDF2 — hundreds of milliseconds. Off the main
        // thread, or the sign-in button visibly freezes the app.
        let derived = try await Task.detached(priority: .userInitiated) {
            try PasswordCrypto.derive(password: password, email: normalizedEmail)
        }.value

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !BackendConfig.proxyToken.isEmpty {
            req.setValue(BackendConfig.proxyToken, forHTTPHeaderField: "X-Cuevi-Token")
        }
        var payload: [String: Any] = [
            "email": normalizedEmail, "derivedKey": derived, "deviceId": deviceID,
        ]
        // Recorded against the account at registration so the cost can be raised
        // later without locking out everyone enrolled at the old setting.
        if includeIterations { payload["iterations"] = PasswordCrypto.iterations }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AuthError.server(-1) }
        guard (200..<300).contains(http.statusCode) else { throw AuthError.server(http.statusCode) }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw AuthError.decode
        }

        // Same ordering rule as `authenticate`: block BEFORE the credential
        // becomes durable, so process death can't leave an authenticated device
        // with nothing guarding a cross-account upload.
        try SessionStore.adopt(token: decoded.token, userID: decoded.userID)
        return Session(token: decoded.token, userID: decoded.userID,
                       plus: decoded.plus, verified: decoded.verified ?? false,
                       hasServerData: decoded.hasServerData)
    }

    private static func send(to endpoint: URL,
                             session: String,
                             body: [String: String] = [:],
                             treat401AsDone: Bool) async throws -> Data {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(session, forHTTPHeaderField: "X-Tadah-Session")
        if !BackendConfig.proxyToken.isEmpty {
            req.setValue(BackendConfig.proxyToken, forHTTPHeaderField: "X-Cuevi-Token")
        }
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AuthError.server(-1) }
        if http.statusCode == 401 && treat401AsDone { return data }
        guard (200..<300).contains(http.statusCode) else { throw AuthError.server(http.statusCode) }
        return data
    }

    // `verified` is optional so a build can talk to a Worker that predates it.
    private struct Response: Decodable { let token: String; let userID: String; let plus: Bool; let verified: Bool?; let hasServerData: Bool }
    private struct VerifyResponse: Decodable { let ok: Bool?; let verified: Bool? }
}
