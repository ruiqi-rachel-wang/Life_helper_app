//  AccountDetailsView.swift
//
//  Identity + auth only (Part 3, phase 1). Deliberately minimal per the mockup:
//  avatar, name, email, and Delete account. It does NOT repeat Language /
//  Notifications / Privacy / App rows — those live on the main Profile screen.
//
//  "Delete account" deletes the ACCOUNT — the server copy of the to-dos, the
//  family profiles, and every session — then forgets the identity on this device.
//  Apple requires an in-app path that deletes the account and its data, so this
//  cannot be a local-only gesture (which is all it used to be).
//
//  What it deliberately does NOT do is erase the to-dos saved on this phone: they
//  are the user's own copy and they were there before the account existed. The
//  confirmation says so plainly.
//

import SwiftUI
import StoreKit
import UIKit

struct AccountDetailsView: View {
    @Environment(AccountStore.self) private var account
    @Environment(PlusStore.self) private var plus
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var isRestoring = false
    @State private var restoreMessage: String?

    @State private var name = ""
    @State private var email = ""
    @State private var confirmDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var askPassword = false
    @State private var deletePassword = ""

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        avatarHeader
                        identityCard
                        membershipCard
                        deleteCard
                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); dismiss() }.font(.body14.weight(.semibold))
                }
            }
        }
        .onAppear {
            name = account.account?.name ?? ""
            email = account.account?.email ?? ""
        }
        .confirmationDialog("Delete account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            // The password is asked for next — something irreversible needs proof
            // it's really you, not just an unlocked phone.
            Button("Delete account", role: .destructive) { askPassword = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account and everything backed up to it, on every device. Your saved items stay on this phone. This can't be undone.")
        }
        // The password step. Deliberately a second, separate confirmation rather
        // than a field on the warning above — typing your password should be a
        // deliberate act, not something done while reading what you're about to
        // lose.
        .alert("Confirm your password", isPresented: $askPassword) {
            SecureField("Password", text: $deletePassword)
                .textContentType(.password)
            Button("Delete account", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) { deletePassword = "" }
        } message: {
            Text("Enter your password to confirm.")
        }
        // Never dismiss on failure: saying nothing here is how someone walks away
        // believing their data is gone when the server still has it.
        .alert("Couldn't delete your account",
               isPresented: Binding(get: { deleteError != nil },
                                    set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    private func delete() {
        isDeleting = true
        Task {
            // Never leave the typed password sitting in memory after the attempt,
            // successful or not.
            defer { isDeleting = false; deletePassword = "" }
            do {
                // Re-authenticated with the password collected just above.
                try await account.deleteAccountEverywhere(password: deletePassword)
                // NOTE: LocalDataOwner is deliberately NOT released. The to-dos left
                // on this phone still belong to the account that made them; marking
                // them unclaimed would let the next account to sign in upload them
                // automatically, which is the exact leak LocalDataOwner prevents.
                dismiss()
            } catch AuthService.AuthError.notConfigured {
                // No Worker configured (simulator dev): there is genuinely no
                // server record, so forgetting the local identity IS the deletion.
                account.forgetLocally()
                dismiss()
            } catch {
                deleteError = message(for: error)
            }
        }
    }

    // Say which thing failed. "Couldn't delete" with no cause leaves someone unsure
    // whether their data is gone, which is the worst possible state to leave them in.
    private func message(for error: Error) -> String {
        if case AuthService.AuthError.server(let code) = error {
            switch code {
            case 401:
                // BOTH a wrong password and an expired session land here, and the
                // server deliberately won't say which. Telling someone to sign out
                // and back in when they simply mistyped is worse than useless — it
                // sends them away from the fix.
                return String(localized: "That password doesn't match, or your session has expired. Check the password, or sign out and back in.")
            case 501:
                return String(localized: "Account deletion isn't available right now. Please contact support and we'll delete it for you.")
            case 502:
                // Deliberately vague about HOW far it got: deletion spans Apple,
                // RevenueCat and our backend and can't be atomic, so the honest
                // instruction is simply "tap it again" — the server resumes at the
                // first unfinished step.
                return String(localized: "Your account wasn't fully deleted. Tap Delete account again to finish — we'll pick up where we left off.")
            default:
                return String(localized: "Your account was not deleted. Please check your connection and try again.")
            }
        }
        return String(localized: "Your account was not deleted. Please check your connection and try again.")
    }

    private var avatarHeader: some View {
        HStack {
            Spacer()
            ZStack {
                Circle().fill(Color.accent.opacity(0.15))
                Text(account.account?.initials ?? "•")
                    .font(.system(size: 30, weight: .semibold)).foregroundStyle(Color.accent)
            }
            .frame(width: 84, height: 84)
            Spacer()
        }
        .padding(.top, 8)
    }

    private var identityCard: some View {
        card {
            VStack(alignment: .leading, spacing: 0) {
                fieldLabel("NAME")
                TextField("Name", text: $name, prompt: fieldPrompt("Your name"))
                    .font(.body14).foregroundStyle(Color.ink).textContentType(.name)
                    .padding(.vertical, 4)

                // EMAIL IS READ-ONLY. It's the address the account was created
                // with and what you sign in as, so it isn't a display preference
                // to be edited here — changing it means changing the credential,
                // which needs its own verified flow.
                //
                // The caption used to say "From your Apple ID. Change it in iPhone
                // Settings." That was true under Sign in with Apple and became
                // false the moment accounts moved to email (2026-08-15) — it now
                // just IS your address. Removed rather than reworded: the label
                // above already says EMAIL.
                if !email.isEmpty {
                    Rectangle().fill(Color.hairD).frame(height: 1).padding(.vertical, 12)

                    fieldLabel("EMAIL")
                    Text(email)
                        .font(.body14).foregroundStyle(Color.ink)
                        .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: membership
    //
    // WHAT YOU CAN AND CANNOT DO ABOUT A SUBSCRIPTION FROM INSIDE AN APP.
    //
    // Apple owns cancellation, plan changes and payment details — an app may not
    // cancel an App Store subscription itself, and there is no pause on the App
    // Store at all (that is a Google Play feature). So the honest design is: show
    // everything we actually know, and hand off to Apple's own screen for the
    // rest. A fake "Cancel" that just deep-links is worse than a button that says
    // where it goes.
    //
    // Shown to everyone, including free users, because "am I paying for this, and
    // when does it renew?" is exactly the question people open this page to answer
    // — and finding nothing is what makes them email support.
    @ViewBuilder
    private var membershipCard: some View {
        card {
            VStack(alignment: .leading, spacing: 0) {
                fieldLabel("MEMBERSHIP")

                HStack(spacing: 12) {
                    Image(systemName: plus.isPlus ? "star.circle.fill" : "person.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(plus.isPlus ? Color.accent : Color.faded)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(planTitle).font(.body14).foregroundStyle(Color.ink)
                        Text(planDetail).font(.subline).foregroundStyle(planDetailColor).lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                }
                .padding(.vertical, 12)

                if plus.membership != nil {
                    divider
                    // Goes to Apple's subscription screen, which is where renewing,
                    // switching monthly/yearly, changing the card and cancelling
                    // all actually happen. Named for where it goes.
                    Button { openAppleSubscriptions() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.up.forward.app").font(.system(size: 15))
                                .foregroundStyle(Color.accent).frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Manage in the App Store").font(.body14).foregroundStyle(Color.ink)
                                Text("Cancel, switch between monthly and yearly, or update your payment method. Apple handles subscriptions, so this opens their settings.")
                                    .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                divider
                Button { Task { await restore() } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 15))
                            .foregroundStyle(Color.accent).frame(width: 22)
                        Text("Restore purchases").font(.body14).foregroundStyle(Color.ink)
                        Spacer()
                        if isRestoring { ProgressView().controlSize(.small) }
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isRestoring)

                if let restoreMessage {
                    Text(restoreMessage)
                        .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 12)
                }
            }
        }
    }

    private var planTitle: String {
        guard let m = plus.membership, m.isActive else {
            return plus.isPlus ? String(localized: "Tadah Plus") : String(localized: "Free plan")
        }
        return m.isYearly ? String(localized: "Tadah Plus · Yearly")
                          : String(localized: "Tadah Plus · Monthly")
    }

    // The line people actually came for: when does money move, or when does this
    // stop working. Each state says the DATE, because "active" alone answers
    // nothing.
    private var planDetail: String {
        guard let m = plus.membership else {
            return String(localized: "You're on the free plan. Tadah Plus adds family lists, more scans, and more devices.")
        }
        let when = m.expirationDate.map { Self.dateText($0) }
        if m.hasBillingProblem {
            return String(localized: "There's a problem with your payment. Update your payment method in the App Store to keep Tadah Plus.")
        }
        if !m.isActive {
            return when.map { String(localized: "Your Plus membership ended on \($0).") }
                ?? String(localized: "Your Plus membership has ended.")
        }
        if m.willRenew {
            return when.map { String(localized: "Renews automatically on \($0).") }
                ?? String(localized: "Renews automatically.")
        }
        // Cancelled but still paid up — the most confusing state, so it says both
        // that it is ending AND that it still works until then.
        return when.map { String(localized: "Cancelled — you keep Tadah Plus until \($0), then it won't renew.") }
            ?? String(localized: "Cancelled — it won't renew.")
    }

    private var planDetailColor: Color {
        guard let m = plus.membership else { return Color.faded }
        if m.hasBillingProblem { return Color.bad }
        if !m.isActive { return Color.warn }
        return Color.faded
    }

    private static func dateText(_ d: Date) -> String {
        d.formatted(.dateTime.day().month(.wide).year())
    }

    private func openAppleSubscriptions() {
        // StoreKit's own sheet keeps people inside Tadah; the URL is the fallback
        // when there is no window scene to present it from.
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first {
            Task { try? await AppStore.showManageSubscriptions(in: scene) }
        } else if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            openURL(url)
        }
    }

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        switch await plus.restore() {
        case .restored:
            restoreMessage = String(localized: "Your Tadah Plus membership is back on this phone.")
        case .nothingToRestore:
            restoreMessage = String(localized: "This Apple ID has no Tadah Plus purchase to restore.")
        case .failed:
            restoreMessage = String(localized: "We couldn't reach the App Store. Please check your connection and try again.")
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.hair).frame(height: 1)
    }

    private var deleteCard: some View {
        card {
            Button { confirmDelete = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "trash").font(.system(size: 15)).foregroundStyle(Color.bad)
                        .frame(width: 22)
                    Text("Delete account").font(.body14).foregroundStyle(Color.bad)
                    Spacer()
                    if isDeleting { ProgressView().controlSize(.small) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
        }
    }

    private func fieldLabel(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded).padding(.bottom, 6)
    }

    private func save() {
        account.updateProfile(name: name.trimmingCharacters(in: .whitespaces),
                              email: email.trimmingCharacters(in: .whitespaces))
    }

    private func card<C: View>(@ViewBuilder _ inner: () -> C) -> some View {
        inner()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }
}
