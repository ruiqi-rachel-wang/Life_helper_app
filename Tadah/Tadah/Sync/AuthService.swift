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

    enum AuthError: Error { case notConfigured, badToken, server(Int), decode }

    // `identityToken` is the raw JWT bytes from
    // ASAuthorizationAppleIDCredential.identityToken. On success the session is
    // saved to the Keychain and returned (hasServerData drives Phase 3 login
    // reconciliation: seed-from-local vs pull-and-merge).
    @discardableResult
    static func authenticate(identityToken: Data, deviceID: String) async throws -> Session {
        guard let endpoint = BackendConfig.authEndpoint else { throw AuthError.notConfigured }
        guard let jwt = String(data: identityToken, encoding: .utf8) else { throw AuthError.badToken }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !BackendConfig.proxyToken.isEmpty {
            req.setValue(BackendConfig.proxyToken, forHTTPHeaderField: "X-Cuevi-Token")
        }
        req.httpBody = try JSONEncoder().encode(Request(idToken: jwt, deviceId: deviceID))

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AuthError.server(-1) }
        guard (200..<300).contains(http.statusCode) else { throw AuthError.server(http.statusCode) }
        guard let payload = try? JSONDecoder().decode(Response.self, from: data) else { throw AuthError.decode }

        SessionStore.save(token: payload.token, userID: payload.userID)
        return Session(token: payload.token, userID: payload.userID,
                       plus: payload.plus, hasServerData: payload.hasServerData)
    }

    private struct Request: Encodable { let idToken: String; let deviceId: String }
    private struct Response: Decodable { let token: String; let userID: String; let plus: Bool; let hasServerData: Bool }
}
