//  VerifyEmailView.swift
//
//  Proving the address on the account is yours: Tadah emails six digits, you
//  type them back.
//
//  ONLY TADAH CALLS NEEDS THIS. Scanning, guides, reminders, sync and Plus all
//  work on an unverified address, so this is never forced on anyone at sign-up —
//  it appears on the account screen as a quiet line, and on a call that was
//  refused for exactly this reason.
//
//  WHY CALLS NEEDS IT: an unverified address is an unowned one, and anyone can
//  type a stranger's. Calling hands that person an agent that phones real
//  businesses and speaks as them, so "we'll confirm who you are later" is the
//  wrong order. Both routes are authenticated by the session, so the code can
//  only ever be sent to the address already on the account.

import SwiftUI

struct VerifyEmailView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var isWorking = false
    @State private var codeSent = false
    @State private var message: String?
    @State private var failed = false
    @FocusState private var codeFocused: Bool

    private var email: String { account.account?.email ?? "" }
    private var canVerify: Bool { code.trimmingCharacters(in: .whitespaces).count == 6 && !isWorking }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Tadah needs to know this address is yours before it calls anyone for you.")
                            .font(.body14).foregroundStyle(Color.faded).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)

                        card {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("EMAIL").font(.eyebrow).foregroundStyle(Color.faint)
                                Text(email).font(.cardTitle).foregroundStyle(Color.ink)
                            }
                        }

                        if codeSent { codeCard } else { sendCard }

                        if let message {
                            Text(message)
                                .font(.subline).foregroundStyle(failed ? Color.bad : Color.faded)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 24)
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .dismissKeyboardOnTap()
            .navigationTitle(Text("Verify your email"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // Step 1 — ask for the code.
    private var sendCard: some View {
        VStack(spacing: 10) {
            Button(action: sendCode) {
                label(isWorking ? String(localized: "Sending…") : String(localized: "Send me a code"))
            }
            .buttonStyle(.plain).disabled(isWorking)
        }
    }

    // Step 2 — type it back.
    private var codeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("6-DIGIT CODE").font(.eyebrow).foregroundStyle(Color.faint)
                    TextField("", text: $code, prompt: fieldPrompt("123456"))
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($codeFocused)
                }
            }
            Button(action: verify) {
                label(isWorking ? String(localized: "Checking…") : String(localized: "Verify"), enabled: canVerify)
            }
            .buttonStyle(.plain).disabled(!canVerify)

            Button(action: sendCode) {
                Text("Send another code").font(.subline).foregroundStyle(Color.faded)
            }
            .buttonStyle(.plain).disabled(isWorking)
        }
    }

    // ── actions ─────────────────────────────────────────────────────────────

    private func sendCode() {
        isWorking = true
        message = nil
        failed = false
        Task {
            do {
                let alreadyVerified = try await AuthService.requestEmailVerification()
                if alreadyVerified {
                    account.setEmailVerified(true)
                    dismiss()
                    return
                }
                codeSent = true
                codeFocused = true
                message = String(localized: "Check your inbox. The code expires in 30 minutes.")
            } catch {
                failed = true
                message = Self.sendFailure(error)
            }
            isWorking = false
        }
    }

    private func verify() {
        isWorking = true
        message = nil
        failed = false
        Task {
            do {
                if try await AuthService.confirmEmailVerification(code: code) {
                    account.setEmailVerified(true)
                    dismiss()
                    return
                }
                failed = true
                message = String(localized: "That code didn't work. Check it and try again.")
            } catch {
                failed = true
                message = Self.verifyFailure(error)
            }
            isWorking = false
        }
    }

    /// The Worker answers 502 when the mail itself couldn't be sent, which is the
    /// one case where "try again" is honest advice rather than a shrug.
    private static func sendFailure(_ error: Error) -> String {
        if case AuthService.AuthError.server(502) = error {
            return String(localized: "Couldn't send the code just now. Please try again shortly.")
        }
        return String(localized: "Couldn't send the code. Check your connection and try again.")
    }

    /// A wrong, expired or used-up code all come back as 400 — deliberately, so a
    /// guesser learns nothing from the difference.
    private static func verifyFailure(_ error: Error) -> String {
        if case AuthService.AuthError.server(400) = error {
            return String(localized: "That code didn't work. Codes expire after 30 minutes, and there are only five tries.")
        }
        return String(localized: "Couldn't check the code. Please try again.")
    }

    // ── bits ────────────────────────────────────────────────────────────────

    private func label(_ text: String, enabled: Bool = true) -> some View {
        Text(text)
            .font(.cardTitle).foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(enabled ? Color.accent : Color.hairD)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }
}
