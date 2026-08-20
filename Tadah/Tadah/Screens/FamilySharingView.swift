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
            // ONE short line. It still has to teach the swipe (the only way in)
            // and what TAPPING does — tapping sets who new to-dos are filed under,
            // not just what you're looking at. The "anyone but yourself" tail
            // stays: the owner's own row silently ignores the right swipe, and
            // without those three words the promised gesture reads as broken on
            // the one row every account has.
            Text("Tap a name to switch; new to-dos are filed under them. Swipe left to edit, right to remove — anyone but yourself.")
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
    // active. Modelled on the account switchers this pattern is borrowed from.
    //
    // EDIT AND REMOVE ARE SWIPES, matching the Inbox exactly (2026-08-17): swipe
    // RIGHT to reveal Remove and tap it, swipe LEFT to edit. The ⓘ menu that used
    // to sit on the right is gone — the same two actions reached two ways, one of
    // which contradicted the Inbox, and its 30pt tap target crowded the row. The
    // long-press menu stays as the non-gesture path, and VoiceOver gets both
    // actions explicitly.
    private var grid: some View {
        VStack(spacing: 0) {
            ForEach(Array(profiles.profiles.enumerated()), id: \.element.id) { index, profile in
                if index > 0 { divider }
                ProfileSwipeRow(
                    name: profile.displayName,
                    initials: profile.initials,
                    colorIndex: profile.colorIndex,
                    todoCount: count(profile),
                    isActive: profile.id == profiles.activeProfileID,
                    // The owner is the account itself, so there is nothing to
                    // remove them FROM — their row has no Remove tray at all
                    // rather than one that opens and then refuses.
                    canRemove: !profile.isOwner,
                    onTap: { switchTo(profile) },
                    onEdit: { startEditing(profile) },
                    onRemove: { confirmRemove = profile })
                .contextMenu { editActions(for: profile) }
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
        Button("Edit") { startEditing(profile) }
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
                    // BOTH lines are for ADDING only. On a rename the sheet is one
                    // labelled field and a toggle — a sentence explaining what a
                    // name is was noise, and the paperwork warning would be a nag
                    // about a decision already made.
                    //
                    // ADDING SOMEONE MEANS HOLDING THEIR DOCUMENTS. A profile is
                    // where a parent's medical letters, a partner's immigration
                    // notices and a child's school forms end up — real information
                    // about a real person who never agreed to anything and cannot
                    // see or delete it themselves.
                    if profile == nil {
                        Text("This isn't an invitation or a separate login.")
                            .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
                        Text("Only add someone whose paperwork you're allowed to handle — a family member you help, or your own child. What you file under them can include medical, money, and immigration details about that person.")
                            .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }

                    // PER-PERSON REMINDER TIME. Only when editing someone who
                    // already exists — while adding, there's nothing to attach it
                    // to yet, and one decision at a time is plenty.
                    if profile != nil {
                        Divider().overlay(Color.hair).padding(.vertical, 4)
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
                                    .tint(Color.ink)
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

    private func startEditing(_ profile: Profile) {
        newName = profile.name
        loadReminderState(for: profile)
        editing = profile
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

// One family member's row. The gesture contract is INboxView.SwipeRow's, on
// purpose: swipe RIGHT to open a Remove tray you then tap, swipe LEFT to edit.
//
// Why a hand-rolled drag rather than `.swipeActions`: that modifier only works
// inside a `List`, and this screen is a card-shaped `VStack`. The Inbox solved
// the same problem the same way, so copying its mechanics — 84pt tray, identical
// spring, identical dominance guard — is what makes the two feel like one app.
//
// The DESTRUCTIVE direction settles open and waits for a tap; the harmless one
// fires on release. That asymmetry is the Inbox's too, and it's the reason a
// stray swipe can't delete a person.
private struct ProfileSwipeRow: View {
    let name: String
    let initials: String
    let colorIndex: Int
    let todoCount: Int
    let isActive: Bool
    let canRemove: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    @State private var offset: CGFloat = 0    // live x-offset
    @State private var rest: CGFloat = 0      // committed resting offset (0, or +btnW)
    private let btnW: CGFloat = 84
    private let spring = Animation.spring(response: 0.28, dampingFraction: 0.85)

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                removeButton
                Spacer()
                editHint
            }
            rowContent
                .background(Color.card)   // opaque, so the trays stay hidden until revealed
                .contentShape(Rectangle())
                .offset(x: offset)
                // A tap, never a Button: a Button under `.simultaneousGesture`
                // fires a phantom tap when a swipe ends, which would switch
                // profiles every time you tried to edit one.
                .onTapGesture { rest != 0 ? close() : onTap() }
                .simultaneousGesture(dragGesture)
                .accessibilityAddTraits(.isButton)
                .accessibilityActions {
                    Button("Edit") { onEdit() }
                    if canRemove { Button("Remove") { onRemove() } }
                }
        }
        .clipped()
    }

    private var rowContent: some View {
        HStack(spacing: 14) {
            ProfileAvatar(initials: initials, colorIndex: colorIndex, size: 44, isSelected: false)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body14).foregroundStyle(Color.ink).lineLimit(1)
                Text("\(todoCount) to-dos").font(.subline).foregroundStyle(Color.faded)
            }
            Spacer(minLength: 8)
            // The tick, not a ring: it NAMES the state instead of leaving colour
            // to imply it.
            if isActive {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accent)
                    .accessibilityLabel("Currently viewing")
            }
        }
        .padding(.vertical, 10)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                // Horizontal dominance, or the card stops scrolling vertically.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let raw = rest + value.translation.width
                // Don't let the Remove tray peek open on a row that has none.
                offset = min(canRemove ? btnW : 0, max(-btnW, raw))
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    withAnimation(spring) { offset = rest }; return
                }
                let dx = value.translation.width
                let t = btnW * 0.5
                if dx <= -t && rest == 0 {
                    onEdit()                                              // LEFT → edit
                    withAnimation(spring) { offset = 0 }
                } else if dx >= t && canRemove {
                    rest = btnW; withAnimation(spring) { offset = btnW }   // RIGHT → reveal Remove
                } else {
                    rest = 0; withAnimation(spring) { offset = 0 }
                }
            }
    }

    // Revealed by a right swipe, then TAPPED — the "one more click" before a
    // person and their to-dos go. It still routes through the existing
    // confirmation alert, so removing stays two deliberate acts.
    private var removeButton: some View {
        Button { onRemove() } label: {
            VStack(spacing: 3) {
                Image(systemName: "trash").font(.system(size: 17, weight: .semibold))
                Text("Remove").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(width: btnW).frame(maxHeight: .infinity)
            .background(Color.bad)
        }
        .buttonStyle(.plain)
        .opacity(offset > 1 ? 1 : 0)
    }

    // Feedback while swiping left; the edit sheet itself opens on release.
    private var editHint: some View {
        VStack(spacing: 3) {
            Image(systemName: "pencil").font(.system(size: 17, weight: .semibold))
            Text("Edit").font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.white)
        .frame(width: btnW).frame(maxHeight: .infinity)
        .background(Color.accent)
        .opacity(offset < -1 ? 1 : 0)
    }

    private func close() {
        rest = 0
        withAnimation(spring) { offset = 0 }
    }
}
