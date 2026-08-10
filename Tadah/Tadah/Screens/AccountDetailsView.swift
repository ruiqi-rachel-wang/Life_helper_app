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

struct AccountDetailsView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var confirmDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        avatarHeader
                        identityCard
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
            Button("Delete account", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account, everything backed up to it on every device, and disconnects your Apple ID from Tadah. You'll be asked to confirm with Apple. Your saved items stay on this phone. This can't be undone.")
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
            defer { isDeleting = false }
            do {
                // Re-authorize with Apple FIRST. Deleting the account has to revoke
                // the Apple grant too, and that needs a fresh authorization code —
                // the one from the original sign-in is single-use and long expired.
                // It also makes the user confirm with Face ID before something
                // irreversible.
                let code = try await AppleReauthorization().authorizationCode()
                try await account.deleteAccountEverywhere(authorizationCode: code)
                // NOTE: LocalDataOwner is deliberately NOT released. The to-dos left
                // on this phone still belong to the account that made them; marking
                // them unclaimed would let the next account to sign in upload them
                // automatically, which is the exact leak LocalDataOwner prevents.
                dismiss()
            } catch AppleReauthorization.ReauthError.cancelled {
                // Backed out at the Apple sheet — not an error, just don't delete.
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
                return String(localized: "Your session has expired. Please sign out, sign in again, and retry.")
            case 501:
                return String(localized: "Account deletion isn't available right now. Please contact support and we'll delete it for you.")
            case 502:
                return String(localized: "We couldn't fully disconnect your Apple ID, so nothing was deleted. Please try again.")
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
                TextField("Your name", text: $name)
                    .font(.body14).foregroundStyle(Color.ink).textContentType(.name)
                    .padding(.vertical, 4)

                Rectangle().fill(Color.hairD).frame(height: 1).padding(.vertical, 12)

                fieldLabel("EMAIL")
                TextField("you@example.com", text: $email)
                    .font(.body14).foregroundStyle(Color.ink)
                    .textContentType(.emailAddress).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(.vertical, 4)
            }
        }
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
