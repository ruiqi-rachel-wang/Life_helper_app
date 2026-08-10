//  SignInView.swift
//
//  Sign in / create account (Part 3, phase 1). Sign in with Apple is the whole
//  flow for now: native, free, no password to manage, and the document never
//  leaves the phone. Google + email
//  are planned (see future_features.md Part 3) but need an SDK / a backend, so
//  they're noted as coming, not shown as dead buttons.
//
//  Signing in is purely retention: it doesn't change what the app can do, it just
//  means your saved items survive sign-out/sign-in (and, later, a new phone).
//

import SwiftUI
import SwiftData
import AuthenticationServices
import CryptoKit
import RevenueCat

struct SignInView: View {
    // Sign-in has two halves that can succeed independently, and conflating them
    // is how the app came to claim "signed in" with no backup at all:
    //   1. Apple authorizes you on THIS DEVICE (always works offline).
    //   2. The Worker confirms it and issues a backup session (needs network).
    // Only `backedUp` means your to-dos are actually going somewhere.
    private enum Phase: Equatable {
        case idle
        case authorizing          // waiting on the Worker after Apple said yes
        case backedUp             // signed in AND backup confirmed
        case localOnly(String)    // signed in on this device; backup unavailable
    }

    @Environment(AccountStore.self) private var account
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var errorMessage: String?
    @State private var phase: Phase = .idle
    // Kept so "Try again" can retry the BACKUP half without making the person
    // repeat the whole Apple authorization.
    @State private var pendingToken: Data?
    @State private var pendingNonce: String?

    var body: some View {
        ZStack(alignment: .top) {
            Color.paper.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                closeBar

                Spacer(minLength: 12)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Sign in").font(.serifTitle).tracking(-0.8).foregroundStyle(Color.ink)
                    Text("Create a free account so your items are never lost — they're backed up to your account and come with you to a new phone.")
                        .font(.body14).foregroundStyle(Color.faded).lineSpacing(3)
                }
                .padding(.horizontal, 6)

                Spacer(minLength: 28)

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                    // Replay protection: Apple puts this hash in the identity
                    // token, and the Worker checks it against the raw value and
                    // then burns it, so the token can't be presented twice.
                    let raw = Self.randomNonce()
                    pendingNonce = raw
                    request.nonce = Self.sha256(raw)
                } onCompletion: { result in
                    handle(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .disabled(phase == .authorizing)

                statusBanner

                if let errorMessage {
                    Text(errorMessage)
                        .font(.subline).foregroundStyle(Color.bad).lineSpacing(2)
                        .padding(.top, 12)
                }

                Text("More ways to sign in (Google, email) are coming soon.")
                    .font(.subline).foregroundStyle(Color.faint)
                    .padding(.top, 14)

                Spacer()

                Text("Signing in is free. Your items are backed up to your account so you don't lose them, and a free account is used on one device at a time.")
                    .font(.subline).foregroundStyle(Color.faint).lineSpacing(2)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
        }
    }

    // Says which of the two halves actually happened. The old screen dismissed
    // immediately no matter what, so a failed backup looked identical to a working
    // one — the user believed their to-dos were safe when nothing had been saved.
    @ViewBuilder
    private var statusBanner: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .authorizing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Setting up your backup…").font(.subline).foregroundStyle(Color.faded)
            }
            .padding(.top, 12)
        case .backedUp:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.ok)
                Text("Signed in. Your to-dos are backed up.")
                    .font(.subline).foregroundStyle(Color.faded)
            }
            .padding(.top, 12)
        case .localOnly(let reason):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.warn)
                    Text("Signed in on this phone only").font(.body14.weight(.semibold))
                        .foregroundStyle(Color.ink)
                }
                Text("We couldn't reach Tadah to set up your backup, so your to-dos are saved on this phone but not to your account yet. \(reason)")
                    .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
                // "Try again" clears the state and puts the Apple button back —
                // retrying means authorizing again, because the server consumes
                // each sign-in nonce and a replay can never succeed.
                HStack(spacing: 10) {
                    Button("Try again") { retryBackup() }
                        .font(.body14.weight(.semibold)).foregroundStyle(Color.accent)
                    Button("Continue anyway") { dismiss() }
                        .font(.body14).foregroundStyle(Color.faded)
                }
            }
            .padding(.top, 14)
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
            errorMessage = nil
            pendingToken = cred.identityToken

            guard let identityToken = cred.identityToken, let nonce = pendingNonce else {
                phase = .localOnly(String(localized: "Apple didn't return a sign-in token."))
                return
            }
            phase = .authorizing
            Task { await authenticateBackup(identityToken, nonce: nonce, appleUserID: cred.user) }

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

    // The BACKUP half of signing in. Kept separate so it can be retried on its own
    // and so its failure is reported instead of swallowed by `try?`.
    private func authenticateBackup(_ identityToken: Data, nonce: String, appleUserID: String) async {
        // RevenueCat FIRST and AWAITED. The Worker asks RevenueCat what tier this
        // Apple id is on, so if we don't finish identifying before /auth/apple
        // runs, the lookup can miss the subscription and a paying user gets the
        // free one-device treatment.
        _ = try? await Purchases.shared.logIn(appleUserID)

        do {
            let session = try await AuthService.authenticate(
                identityToken: identityToken, deviceID: Device.id, nonce: nonce)
            // Reconciliation decides what happens to the to-dos already on THIS
            // device (seed a new account, or back up + ask before touching them).
            // Its RESULT decides what we claim: a session alone is not a backup, so
            // "your to-dos are backed up" waits for a completed sync round trip.
            switch await sync.afterSignIn(session: session, context: context) {
            case .backedUp:
                phase = .backedUp
                dismiss()
            case .awaitingReconciliation:
                // RootTabView's alert takes over; get out of its way.
                dismiss()
            case .signedInLocally:
                // Signed in, but the first sync didn't complete — say exactly that
                // rather than promising a backup that hasn't happened.
                phase = .localOnly(String(localized: "You're signed in, but we couldn't finish backing up yet. It will retry on its own."))
            }
        } catch AuthService.AuthError.notConfigured {
            // No Worker set (simulator dev). Local sign-in is the whole feature
            // there, so this isn't a failure worth alarming anyone about.
            phase = .backedUp
            dismiss()
        } catch {
            phase = .localOnly(reason(for: error))
        }
    }

    // Retry re-runs the WHOLE Apple authorization rather than replaying the stored
    // token. The server burns each nonce on use, so a replay is guaranteed to fail
    // with "nonce already used" — and if the original request did land, replaying
    // it would be trying to mint a second session anyway. `pendingToken` is kept
    // only so the sheet can tell a completed authorization from a fresh one.
    private func retryBackup() {
        phase = .idle
        errorMessage = nil
        pendingToken = nil
        pendingNonce = nil
    }

    private func reason(for error: Error) -> String {
        if case AuthService.AuthError.server(let code) = error, code == 409 {
            return String(localized: "This account is already signed in on the maximum number of devices.")
        }
        return String(localized: "You can try again now or later — nothing is lost either way.")
    }

    // MARK: - nonce

    // A random string; its SHA-256 goes into the authorization request and the raw
    // value goes to the Worker, which re-derives the hash and compares.
    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
