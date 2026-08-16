//  PasswordResetView.swift
//
//  Forgot password — the only way back into an account, so it can't be left out.
//
//  A CODE, NOT A LINK. A reset link needs a web page to land on, and Tadah has no
//  site; a six-digit code is typed straight into the app and needs nothing.
//
//  ⚠️ THE COPY MUST NOT CONFIRM WHETHER AN ACCOUNT EXISTS. The Worker answers the
//  request step identically for a registered and an unregistered address — that's
//  deliberate, so nobody can use this screen to discover who has an account. Which
//  means this screen has to say "if that address has an account, we've sent a
//  code", never "check your inbox". Getting chatty here would undo the server-side
//  care entirely.
//

import SwiftUI

struct PasswordResetView: View {
    let initialEmail: String
    @Environment(\.dismiss) private var dismiss

    private enum Step { case askEmail, enterCode, done }
    @State private var step: Step = .askEmail
    @State private var email = ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var busy = false
    @State private var errorMessage: String?

    private var canSend: Bool { !busy && email.contains("@") }
    private var canConfirm: Bool {
        !busy && code.count == 6
            && newPassword.count >= PasswordCrypto.minimumPasswordLength
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch step {
                        case .askEmail:   askEmailStep
                        case .enterCode:  enterCodeStep
                        case .done:       doneStep
                        }
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.subline).foregroundStyle(Color.bad).lineSpacing(2)
                        }
                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 22).padding(.top, 16)
                }
                .dismissKeyboardOnTap()
            }
            .navigationTitle("Reset password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear { if email.isEmpty { email = initialEmail } }
    }

    private var askEmailStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("We'll email you a 6-digit code.")
                .font(.body14).foregroundStyle(Color.faded)
            TextField("Email", text: $email, prompt: Text("you@example.com"))
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .resetFieldBox()
            actionButton("Send code", enabled: canSend) { await sendCode() }
        }
    }

    private var enterCodeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Says "if" on purpose — see the header.
            Text("If that address has an account, a code is on its way. It expires in 15 minutes.")
                .font(.body14).foregroundStyle(Color.faded).lineSpacing(3)
            TextField("6-digit code", text: $code, prompt: Text("123456"))
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .onChange(of: code) { _, new in
                    code = String(new.filter(\.isNumber).prefix(6))
                }
                .resetFieldBox()
            SecureField("New password", text: $newPassword, prompt: Text("New password"))
                .textContentType(.newPassword)
                .resetFieldBox()
            Text("At least \(PasswordCrypto.minimumPasswordLength) characters")
                .font(.subline).foregroundStyle(Color.faded)
            actionButton("Set new password", enabled: canConfirm) { await confirm() }
            Button("Send another code") { Task { await sendCode() } }
                .font(.subline.weight(.semibold)).foregroundStyle(Color.accent)
                .buttonStyle(.plain)
                .disabled(busy)
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.ok)
                Text("Password changed").font(.body14.weight(.semibold)).foregroundStyle(Color.ink)
            }
            // Every session was revoked server-side, including this device's, so
            // signing in again isn't optional — say so rather than let them
            // discover it.
            Text("You've been signed out everywhere. Sign in with your new password.")
                .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
            actionButton("Done", enabled: true) { dismiss() }
        }
    }

    private func actionButton(_ title: String, enabled: Bool,
                              action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            HStack(spacing: 8) {
                if busy { ProgressView().controlSize(.small).tint(Color.paper) }
                Text(title).font(.body14.weight(.semibold))
            }
            .foregroundStyle(Color.paper)
            .frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(enabled ? Color.ink : Color.faded)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain).disabled(!enabled)
    }

    private func sendCode() async {
        busy = true; errorMessage = nil
        defer { busy = false }
        do {
            try await AuthService.requestPasswordReset(email: email)
            step = .enterCode
        } catch {
            errorMessage = message(for: error)
        }
    }

    private func confirm() async {
        busy = true; errorMessage = nil
        defer { busy = false; newPassword = "" }
        do {
            try await AuthService.confirmPasswordReset(
                email: email, code: code, newPassword: newPassword)
            step = .done
        } catch {
            errorMessage = message(for: error)
        }
    }

    private func message(for error: Error) -> String {
        guard case AuthService.AuthError.server(let status) = error else {
            return String(localized: "We couldn't reach Tadah. Check your connection and try again.")
        }
        switch status {
        // 400 covers wrong, expired, and already-used codes — the server won't say
        // which, and neither should this.
        case 400: return String(localized: "That code isn't right, or it's expired. Ask for a new one.")
        case 429: return String(localized: "Too many attempts. Please wait a moment and try again.")
        default:  return String(localized: "Something went wrong. Please try again.")
        }
    }
}

private extension View {
    func resetFieldBox() -> some View {
        self
            .font(.body14).foregroundStyle(Color.ink)
            .padding(14)
            .background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hair, lineWidth: 1))
    }
}
