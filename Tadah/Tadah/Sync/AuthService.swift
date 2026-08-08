//  AuthService.swift
//
//  Exchanges a Sign-in-with-Apple identity token for a Tadah server session
//  (Part 3). The Worker verifies the Apple token, checks the account's tier via
//  RevenueCat, enforces the free = 1-device rule, and returns a session token,
//  which we persist to the Keychain (SessionStore).
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
        let hasServerData: Bool   // did the account already have tasks on the server?
    }

    enum AuthError: Error { case notConfigured, badToken, noSession, server(Int), decode }

    // `identityToken` is the raw JWT bytes from
    // ASAuthorizationAppleIDCredential.identityToken. `nonce` is the RAW random
    // string whose SHA-256 was put in the authorization request — the Worker
    // re-derives the hash, compares it to the token's `nonce` claim, and burns it,
    // so an intercepted token can't be replayed to mint extra sessions.
    //
    // On success the session is saved to the Keychain and returned (hasServerData
    // drives login reconciliation: seed-from-local vs pull-and-merge).
    @discardableResult
    static func authenticate(identityToken: Data, deviceID: String, nonce: String) async throws -> Session {
        guard let endpoint = BackendConfig.authEndpoint else { throw AuthError.notConfigured }
        guard let jwt = String(data: identityToken, encoding: .utf8) else { throw AuthError.badToken }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !BackendConfig.proxyToken.isEmpty {
            req.setValue(BackendConfig.proxyToken, forHTTPHeaderField: "X-Cuevi-Token")
        }
        req.httpBody = try JSONEncoder().encode(
            Request(idToken: jwt, deviceId: deviceID, nonce: nonce))

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AuthError.server(-1) }
        guard (200..<300).contains(http.statusCode) else { throw AuthError.server(http.statusCode) }
        guard let payload = try? JSONDecoder().decode(Response.self, from: data) else { throw AuthError.decode }

        SessionStore.save(token: payload.token, userID: payload.userID)
        return Session(token: payload.token, userID: payload.userID,
                       plus: payload.plus, hasServerData: payload.hasServerData)
    }

    // Sign out on the SERVER, so the session token stops working the moment the
    // user signs out rather than staying valid until it expires. Throws so the
    // caller can decide; the local sign-out proceeds regardless (a user who taps
    // "log out" must always end up logged out on the device).
    static func logout() async throws {
        guard let endpoint = BackendConfig.logoutEndpoint else { throw AuthError.notConfigured }
        guard let token = SessionStore.token else { return }   // nothing to revoke
        _ = try await send(to: endpoint, session: token)
    }

    // Delete the account and ALL of its server data (tasks, profiles, sessions).
    // Apple requires an in-app path that deletes the account itself, not just the
    // local copy of it, so unlike logout this one's failure MUST be surfaced —
    // telling someone their account is gone when the server still has it is worse
    // than telling them to try again.
    static func deleteAccount() async throws {
        guard let endpoint = BackendConfig.accountDeleteEndpoint else { throw AuthError.notConfigured }
        guard let token = SessionStore.token else { throw AuthError.noSession }
        _ = try await send(to: endpoint, session: token)
    }

    private static func send(to endpoint: URL, session: String) async throws -> Data {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(session, forHTTPHeaderField: "X-Tadah-Session")
        if !BackendConfig.proxyToken.isEmpty {
            req.setValue(BackendConfig.proxyToken, forHTTPHeaderField: "X-Cuevi-Token")
        }
        req.httpBody = Data("{}".utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AuthError.server(-1) }
        // 401 means the session is already gone server-side — for both logout and
        // delete that's the desired end state, not a failure to report.
        guard (200..<300).contains(http.statusCode) || http.statusCode == 401 else {
            throw AuthError.server(http.statusCode)
        }
        return data
    }

    private struct Request: Encodable { let idToken: String; let deviceId: String; let nonce: String }
    private struct Response: Decodable { let token: String; let userID: String; let plus: Bool; let hasServerData: Bool }
}
