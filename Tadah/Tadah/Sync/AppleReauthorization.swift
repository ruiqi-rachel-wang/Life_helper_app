//  AppleReauthorization.swift
//
//  Runs Sign in with Apple again, on demand, to obtain a fresh AUTHORIZATION CODE.
//
//  WHY: deleting a Tadah account has to revoke the Sign-in-with-Apple grant, not
//  just delete our own rows (Apple TN3194). Revocation requires an authorization
//  code exchanged server-side — and the code from the ORIGINAL sign-in is
//  single-use and long expired by the time someone deletes their account. So the
//  delete flow asks Apple for a fresh one at the moment of deletion.
//
//  It doubles as a confirmation step: the user re-authenticates with Face ID /
//  their Apple ID immediately before an irreversible action.
//

import Foundation
import AuthenticationServices

@MainActor
final class AppleReauthorization: NSObject {

    enum ReauthError: Error {
        case cancelled
        case noAuthorizationCode
        case failed(String)
    }

    private var continuation: CheckedContinuation<String, Error>?
    // Held for the lifetime of the request: ASAuthorizationController does not
    // retain its own delegate, and letting this deallocate mid-flight silently
    // drops the callback and hangs the continuation forever.
    private var controller: ASAuthorizationController?

    // Returns the authorization code as a UTF-8 string.
    func authorizationCode() async throws -> String {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        // No scopes: we're not collecting the name/email again, only proving the
        // person is present and getting a code we can revoke with.
        request.requestedScopes = []

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<String, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        controller = nil
    }
}

extension AppleReauthorization: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithAuthorization authorization: ASAuthorization) {
        let code = (authorization.credential as? ASAuthorizationAppleIDCredential)
            .flatMap(\.authorizationCode)
            .flatMap { String(data: $0, encoding: .utf8) }
        Task { @MainActor in
            if let code, !code.isEmpty {
                self.finish(.success(code))
            } else {
                self.finish(.failure(ReauthError.noAuthorizationCode))
            }
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithError error: Error) {
        Task { @MainActor in
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                self.finish(.failure(ReauthError.cancelled))
            } else {
                self.finish(.failure(ReauthError.failed(error.localizedDescription)))
            }
        }
    }
}

extension AppleReauthorization: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            return scene?.keyWindow ?? ASPresentationAnchor()
        }
    }
}
