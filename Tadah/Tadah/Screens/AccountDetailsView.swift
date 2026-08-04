//  AccountDetailsView.swift
//
//  Identity + auth only (Part 3, phase 1). Deliberately minimal per the mockup:
//  avatar, name, email, and Delete account. It does NOT repeat Language /
//  Notifications / Privacy / App rows — those live on the main Profile screen.
//
//  "Delete account" on the free, local tier just forgets the stored identity on
//  this device; your saved items stay put. Server-side deletion arrives with
//  cloud sync (the Tadah Plus phase).
//

import SwiftUI

struct AccountDetailsView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var confirmDelete = false

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
            Button("Delete account", role: .destructive) { account.deleteAccount(); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your account from this device. Your saved items stay on the device.")
        }
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
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
