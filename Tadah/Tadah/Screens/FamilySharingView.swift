//  FamilySharingView.swift
//
//  Manage who's on the account (Part 3, family sharing). A grid of avatars —
//  you first, then the people you look after — plus a dashed tile to add someone.
//  Tapping a face switches whose to-dos the app is showing.
//
//  The whole point is a daughter managing a parent's paperwork, so the language
//  here is plain and the actions are few: add a person, rename them, remove them.
//  Adding is Plus-only; on a free account the add tile opens the paywall instead
//  of a dead-end error.
//

import SwiftUI
import SwiftData

struct FamilySharingView: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(PlusStore.self) private var plus
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var editing: Profile?          // rename sheet
    @State private var confirmRemove: Profile?
    @State private var showAdd = false
    @State private var newName = ""
    @State private var showPaywall = false
    @State private var limitMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 18)]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        intro
                        grid
                        footnote
                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Family")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(.body14.weight(.semibold))
                }
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(item: $editing) { profile in nameSheet(for: profile) }
        .sheet(isPresented: $showAdd) { nameSheet(for: nil) }
        .alert("Remove this person?", isPresented: Binding(
            get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }),
               presenting: confirmRemove) { person in
            Button("Remove \(person.displayName)", role: .destructive) { remove(person) }
            Button("Cancel", role: .cancel) {}
        } message: { person in
            Text("Their to-dos are deleted too. Yours aren't affected.")
        }
        .alert("Can't add", isPresented: Binding(
            get: { limitMessage != nil }, set: { if !$0 { limitMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(limitMessage ?? "") }
        .onAppear { profiles.reload(context) }
    }

    // MARK: pieces

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Everyone on this account")
                .font(.cardTitle).foregroundStyle(Color.ink)
            // Says what tapping ACTUALLY does. The old copy ("Tap someone to see
            // their to-dos") described a filter, but tapping sets who is using the
            // phone — which also becomes the default person new to-dos are filed
            // under. Someone following that sentence would have quietly started
            // saving their own mail under Mom.
            Text("Give each person their own list, so a parent's letters don't mix with yours. Tap someone to switch to them — new to-dos are filed under whoever is selected.")
                .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(profiles.profiles) { profile in
                Button { switchTo(profile) } label: {
                    VStack(spacing: 8) {
                        ProfileAvatar(initials: profile.initials,
                                      colorIndex: profile.colorIndex,
                                      size: 62,
                                      isSelected: profile.id == profiles.activeProfileID)
                        Text(profile.displayName)
                            .font(.subline).foregroundStyle(Color.ink)
                            .lineLimit(1)
                        Text(profile.isOwner ? "You" : "\(count(profile)) to-dos")
                            .font(.eyebrow).tracking(0.4).foregroundStyle(Color.faded)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Rename / remove live here rather than as visible buttons —
                // the grid stays calm, and both are rare actions.
                .contextMenu {
                    Button("Rename") { editing = profile }
                    if !profile.isOwner {
                        Button("Remove", role: .destructive) { confirmRemove = profile }
                    }
                }
            }

            Button { addTapped() } label: {
                VStack(spacing: 8) {
                    AddProfileCircle(size: 62)
                    Text("Add someone").font(.subline).foregroundStyle(Color.faded)
                        .lineLimit(1)
                    Text(plus.isPlus ? " " : "PLUS")
                        .font(.eyebrow).tracking(0.6).foregroundStyle(Color.accent)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }

    private var footnote: some View {
        Text("Tadah Plus covers every profile on this account — no extra charge per person.")
            .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
            .padding(.horizontal, 6)
    }

    // One sheet for both add and rename — the same single field either way.
    private func nameSheet(for profile: Profile?) -> some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.paper.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 10) {
                    Text(profile == nil ? "WHO ARE YOU ADDING?" : "NAME")
                        .font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                    TextField("Mom", text: $newName)
                        .font(.body14).foregroundStyle(Color.ink)
                        .textInputAutocapitalization(.words)
                        .padding(14)
                        .background(Color.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hair, lineWidth: 1))
                    Text("Just a name so you can tell the lists apart — it isn't an invitation or a separate login.")
                        .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
            }
            .navigationTitle(profile == nil ? "Add someone" : "Rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { closeNameSheet() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(profile) }
                        .font(.body14.weight(.semibold))
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.height(280)])
    }

    // MARK: actions

    private func count(_ profile: Profile) -> Int {
        TaskLimit.count(context, profileID: profile.id)
    }

    private func switchTo(_ profile: Profile) {
        profiles.setActive(profile.id)
    }

    private func addTapped() {
        // Free accounts get the upgrade path, not an error they can't act on.
        guard plus.isPlus else { showPaywall = true; return }
        if let reason = profiles.blockedReason(plus: true) { limitMessage = reason; return }
        newName = ""
        showAdd = true
    }

    private func save(_ profile: Profile?) {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if let profile {
            profiles.rename(profile, to: name, in: context)
        } else {
            do {
                let created = try profiles.add(name: name, plus: plus.isPlus, in: context)
                profiles.setActive(created.id)     // jump straight into the new list
            } catch {
                limitMessage = profiles.blockedReason(plus: plus.isPlus)
            }
        }
        SyncCoordinator.shared.noteLocalChange()
        closeNameSheet()
    }

    private func remove(_ profile: Profile) {
        try? profiles.delete(profile, in: context)
        SyncCoordinator.shared.noteLocalChange()
    }

    private func closeNameSheet() {
        showAdd = false
        editing = nil
        newName = ""
    }
}

#Preview {
    FamilySharingView()
        .modelContainer(for: ActionItem.self, inMemory: true)
        .environment(ProfileStore())
        .environment(PlusStore())
}
