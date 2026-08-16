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
    @State private var removeFailed = false
    // Per-person reminder time, edited in the same sheet as the name.
    @State private var useOwnReminderTime = false
    @State private var reminderTime = Date.now


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
        // A failed removal used to be swallowed by `try?`. The person stayed in the
        // grid with no explanation, which reads as the app ignoring the tap.
        .alert("Couldn't remove", isPresented: $removeFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("We couldn't remove that person. Nothing was changed — please try again.")
        }
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
            // Names the icon that is ACTUALLY on screen. This said "Tap ⋯" while
            // the button has been an ⓘ since the grid became a list — instructions
            // pointing at a control that isn't there read as a bug in the app.
            Text("Tap ⓘ next to a person to edit or remove them.")
                .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
    }

    // A LIST, not a grid of avatars.
    //
    // The grid put identity, count and a ⋯ button into a 92pt tile, so the name
    // truncated, the count was an afterthought, and "which one am I?" was carried
    // only by a coloured ring. Rows give each person a full line: a ✓ says who is
    // active, and an explicit edit button replaces the ⋯ that people had to know
    // to look for. Modelled on the account switchers this pattern is borrowed
    // from, where the same three jobs — identify, indicate current, change
    // settings — are laid out exactly this way.
    private var grid: some View {
        VStack(spacing: 0) {
            ForEach(Array(profiles.profiles.enumerated()), id: \.element.id) { index, profile in
                if index > 0 { divider }
                HStack(spacing: 14) {
                    Button { switchTo(profile) } label: {
                        HStack(spacing: 14) {
                            ProfileAvatar(initials: profile.initials,
                                          colorIndex: profile.colorIndex,
                                          size: 44,
                                          isSelected: false)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName)
                                    .font(.body14).foregroundStyle(Color.ink).lineLimit(1)
                                Text("\(count(profile)) to-dos")
                                    .font(.subline).foregroundStyle(Color.faded)
                            }
                            Spacer(minLength: 8)
                            // The tick, not a ring: it names the state ("this is
                            // the one you're using") instead of leaving colour to
                            // imply it.
                            if profile.id == profiles.activeProfileID {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.accent)
                                    .accessibilityLabel("Currently viewing")
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu { editActions(for: profile) }

                    Menu {
                        editActions(for: profile)
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 19))
                            .foregroundStyle(Color.faded)
                            .frame(width: 30, height: 40)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Edit \(profile.displayName)")
                }
                .padding(.vertical, 10)
            }

            divider
            Button { addTapped() } label: {
                HStack(spacing: 14) {
                    AddProfileCircle(size: 44)
                    Text("Add someone").font(.body14).foregroundStyle(Color.ink)
                    Spacer()
                    if !profiles.familyUnlocked {
                        Text("PLUS").font(.eyebrow).tracking(0.6).foregroundStyle(Color.accent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 10)
        }
        .padding(.horizontal, 16)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
        .padding(.vertical, 4)
    }

    private var divider: some View {
        Rectangle().fill(Color.hair).frame(height: 1)
    }

    // Shared by the ⓘ menu and the long-press menu, so the two can't drift apart.
    @ViewBuilder
    private func editActions(for profile: Profile) -> some View {
        // Prefill with the CURRENT name. An empty rename field reads as "type a new
        // name from scratch" and, worse, Save is disabled until you type something —
        // so tapping Edit to check a spelling left you with a dead sheet.
        Button("Edit") {
            newName = profile.name
            loadReminderState(for: profile)
            editing = profile
        }
        // The owner is the account itself, so there's nothing to remove them FROM.
        if !profile.isOwner {
            Button("Remove", role: .destructive) { confirmRemove = profile }
        }
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
                    TextField("Name", text: $newName, prompt: fieldPrompt("Mom"))
                        .font(.body14).foregroundStyle(Color.ink)
                        .textInputAutocapitalization(.words)
                        .padding(14)
                        .background(Color.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hair, lineWidth: 1))
                    Text("Just a name so you can tell the lists apart — it isn't an invitation or a separate login.")
                        .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)

                    // PER-PERSON REMINDER TIME. Only when editing someone who
                    // already exists — while adding, there's nothing to attach it
                    // to yet, and one decision at a time is plenty.
                    if profile != nil {
                        Divider().padding(.vertical, 4)
                        Toggle(isOn: $useOwnReminderTime.animation(.easeInOut(duration: 0.15))) {
                            Text("Own reminder time").font(.body14).foregroundStyle(Color.ink)
                        }
                        .tint(Color.accent)
                        // The picker is `.compact`, which is a TAPPABLE control
                        // rather than a label — the default style rendered as text
                        // that looked like a caption, so it read as unchangeable.
                        if useOwnReminderTime {
                            HStack {
                                Text("Remind at").font(.body14).foregroundStyle(Color.ink)
                                Spacer()
                                DatePicker("", selection: $reminderTime,
                                           displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                            }
                        } else {
                            Text("Follows your default reminder time.")
                                .font(.subline).foregroundStyle(Color.faded)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
            }
            .navigationTitle(profile == nil ? "Add someone" : "Edit person")
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
        // Taller when editing: the sheet carries the reminder controls too.
        .presentationDetents([.height(profile == nil ? 300 : 460)])
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
        // Same gate the rest of the family UI uses, so an outage can't leave a
        // subscriber looking at their profiles but unable to add one.
        guard profiles.familyUnlocked else { showPaywall = true; return }
        if let reason = profiles.blockedReason(plus: true) { limitMessage = reason; return }
        newName = ""
        showAdd = true
    }

    private func save(_ profile: Profile?) {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if let profile {
            profiles.rename(profile, to: name, in: context)
            // `rename` stamps updatedAt; set the time first so one touch covers
            // both and the pair syncs together rather than as two writes.
            let minutes = useOwnReminderTime ? Self.minutes(from: reminderTime) : nil
            if profile.reminderMinutes != minutes {
                profile.reminderMinutes = minutes
                profile.touch()
                // Times feed straight into what's already scheduled.
                ReminderScheduler.shared.rescheduleAll(
                    for: (try? context.fetch(FetchDescriptor<ActionItem>())) ?? [])
            }
        } else {
            do {
                // `familyUnlocked`, matching addTapped. Using isPlus here meant the
                // Add tile opened (gate says yes) and Save then applied the FREE
                // one-profile cap (isPlus says no) — so during a RevenueCat outage
                // a subscriber could type a name and be refused on save.
                let created = try profiles.add(name: name, plus: profiles.familyUnlocked, in: context)
                profiles.setActive(created.id)     // jump straight into the new list
            } catch {
                limitMessage = profiles.blockedReason(plus: profiles.familyUnlocked)
            }
        }
        SyncCoordinator.shared.noteLocalChange()
        closeNameSheet()
    }

    private func remove(_ profile: Profile) {
        // Both of `delete`'s throw points — the owner guard and the child-item
        // fetch — happen BEFORE it mutates anything, so "nothing was changed" in
        // the alert is literally true, and there is nothing to roll back here.
        do {
            try profiles.delete(profile, in: context)
        } catch {
            removeFailed = true
            return                      // and DON'T nudge a sync for a no-op
        }
        SyncCoordinator.shared.noteLocalChange()
    }

    private func closeNameSheet() {
        showAdd = false
        editing = nil
        newName = ""
        useOwnReminderTime = false
    }

    // Minutes past midnight ⇄ a Date the picker can show. Only the time of day is
    // meaningful; the date part is whatever today happens to be.
    private static func minutes(from date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 9) * 60 + (c.minute ?? 0)
    }

    private static func date(fromMinutes m: Int) -> Date {
        Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: .now) ?? .now
    }

    // Load the sheet's per-person state from whoever is being edited.
    private func loadReminderState(for profile: Profile?) {
        guard let profile else { useOwnReminderTime = false; return }
        useOwnReminderTime = profile.reminderMinutes != nil
        reminderTime = Self.date(fromMinutes: profile.reminderMinutes
                                 ?? AppSettings.defaultReminderMinutes)
    }
}

#Preview {
    FamilySharingView()
        .modelContainer(for: ActionItem.self, inMemory: true)
        .environment(ProfileStore())
        .environment(PlusStore())
}
