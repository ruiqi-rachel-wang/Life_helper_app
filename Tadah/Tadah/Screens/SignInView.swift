//  SignInView.swift
//
//  Sign in / create account (Part 3, phase 1). Sign in with Apple is the whole
//  flow for now: native, free, no password to manage, and the document never
//  leaves the phone — it fits Tadah's on-device privacy stance. Google + email
//  are planned (see future_features.md Part 3) but need an SDK / a backend, so
//  they're noted as coming, not shown as dead buttons.
//
//  Signing in is purely retention: it doesn't change what the app can do, it just
//  means your saved items survive sign-out/sign-in (and, later, a new phone).
//

import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .top) {
            Color.paper.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                closeBar

                Spacer(minLength: 12)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Sign in").font(.serifTitle).tracking(-0.8).foregroundStyle(Color.ink)
                    Text("Create a free account so your items are never lost — they'll survive signing out and, later, moving to a new phone. Everything still stays private to you.")
                        .font(.body14).foregroundStyle(Color.faded).lineSpacing(3)
                }
                .padding(.horizontal, 6)

                Spacer(minLength: 28)

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handle(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if let errorMessage {
                    Text(errorMessage)
                        .font(.subline).foregroundStyle(Color.bad).lineSpacing(2)
                        .padding(.top, 12)
                }

                Text("More ways to sign in (Google, email) are coming soon.")
                    .font(.subline).foregroundStyle(Color.faint)
                    .padding(.top, 14)

                Spacer()

                Text("Signing in is free and only stores your name and email to keep your data with you. It doesn't unlock anything else yet.")
                    .font(.subline).foregroundStyle(Color.faint).lineSpacing(2)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
        }
    }

    private var closeBar: some View {
        HStack {
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 28))
                    .foregroundStyle(Color.faint)
            }
            .buttonStyle(.plain).accessibilityLabel("Close")
        }
        .padding(.top, 8)
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = String(localized: "Couldn't sign in. Please try again.")
                return
            }
            let name = [cred.fullName?.givenName, cred.fullName?.familyName]
                .compactMap { $0 }.joined(separator: " ")
            account.signIn(Account(userID: cred.user, provider: .apple,
                                   name: name, email: cred.email ?? ""))
            dismiss()
        case .failure(let error):
            // A user-cancelled sheet isn't an error worth surfacing.
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                errorMessage = nil
            } else {
                #if DEBUG
                // Dev builds surface the real reason — the usual one is the
                // "Sign in with Apple" capability not being enabled yet (error
                // 1000 / "not handled"), which the CLI can't turn on.
                errorMessage = String(localized: "Couldn't sign in.") + " (\(error.localizedDescription))"
                #else
                errorMessage = String(localized: "Couldn't sign in. Please try again.")
                #endif
            }
        }
    }
}
