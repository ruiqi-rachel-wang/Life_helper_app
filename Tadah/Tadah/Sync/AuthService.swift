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
        // 401 is FINE here: it means the session is already dead server-side, which
        // is exactly what logging out is trying to achieve.
        _ = try await send(to: endpoint, session: token, treat401AsDone: true)
    }

    // Delete the account and ALL of its server data (tasks, profiles, sessions),
    // and revoke the Sign-in-with-Apple grant. Apple requires an in-app path that
    // deletes the account itself, not just the local copy of it.
    //
    // `authorizationCode` comes from the fresh Apple re-authorization the delete
    // flow performs; the Worker exchanges it with Apple and calls Apple's token
    // revocation endpoint. Deletion is refused without it, because "delete my
    // account" that leaves Tadah listed under Settings ▸ Apple ID ▸ Sign in with
    // Apple hasn't actually deleted the connection.
    static func deleteAccount(authorizationCode: String) async throws {
        guard let endpoint = BackendConfig.accountDeleteEndpoint else { throw AuthError.notConfigured }
        guard let token = SessionStore.token else { throw AuthError.noSession }
        // 401 is NOT success here. An expired or already-revoked session means the
        // server authenticated nobody and therefore deleted NOTHING — reporting
        // that as done would tell someone their data is gone while we still hold
        // all of it. Make them re-authenticate instead.
        _ = try await send(to: endpoint, session: token,
                           body: ["authorizationCode": authorizationCode],
                           treat401AsDone: false)
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

    private struct Request: Encodable { let idToken: String; let deviceId: String; let nonce: String }
    private struct Response: Decodable { let token: String; let userID: String; let plus: Bool; let hasServerData: Bool }
}
