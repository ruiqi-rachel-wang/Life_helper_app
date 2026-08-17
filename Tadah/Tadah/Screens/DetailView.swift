//  DetailView.swift
//
//  Action detail — the full view of one stored item. Binds to the live
//  SwiftData object (@Bindable), so edits / Mark done / Delete write straight
//  through. Mirrors the Review screen's card style: a head card (tag · title ·
//  amount/due chips), then steps, reminders, details (IDs), and notes last.
//
//  Composed of optional, item-driven sections so different item TYPES can
//  compose differently later without a rewrite.
//

import SwiftUI
import SwiftData
import UIKit

struct DetailView: View {
    @Bindable var item: ActionItem
    @Environment(ProfileStore.self) private var profiles
    @Environment(PlusStore.self) private var plus

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var showDeleteConfirm = false
    @State private var didDelete = false
    @State private var detailStep: ChecklistStep?   // tapped step → detail sheet
    @State private var showFullPhoto = false         // tapped photo → full-screen viewer
    // What the item looked like when edit mode opened, so leaving can tell a real
    // edit from a look. `TaskDTO` is the item's own value form and is Equatable, so
    // this compares every synced field without hand-listing them.
    @State private var editSnapshot: TaskDTO?
    @State private var moveBlocked = false           // destination list already full

    // Which field the keyboard is in. Tapping "Add a step / detail / note" used to
    // append a row whose only visible sign was an empty placeholder — testers read
    // that as "the button didn't do anything". Focusing the new row instead raises
    // the keyboard and puts a caret in it, so the tap is unmistakably acknowledged.
    private enum Field: Hashable { case step(UUID), detailLabel(Int), note(Int) }
    @FocusState private var focused: Field?

    // The reader's explanation language (Profile picker). The enlarged photo viewer
    // offers in-place translation only when it isn't English — an English reader of
    // an English doc doesn't need it.
    @AppStorage(ExplainLanguage.storageKey) private var explainLanguageRaw = ""
    private var explainLanguage: ExplainLanguage { ExplainLanguage.resolve(stored: explainLanguageRaw) }

    private var isDone: Bool { item.status == .done }
    private var startOfToday: Date { Calendar.current.startOfDay(for: .now) }

    var body: some View {
        ZStack(alignment: .top) {
            Color.paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    navBar.padding(.horizontal, 22)
                    headCard
                    if !item.steps.isEmpty || isEditing { checklistCard }
                    if !item.otherIDs.isEmpty || siteURLToShow != nil || isEditing { detailsCard }
                    if !item.effectiveReminders.isEmpty || isEditing { remindersCard }
                    if !item.notes.isEmpty || isEditing { noteCard }
                    if let photo = storedPhoto { photoCard(photo) }
                    footer
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 14)
                .padding(.top, 48)
            }
            .dismissKeyboardOnTap()
        }
        .navigationBarHidden(true)
        .sheet(item: $detailStep) { tapped in
            if let idx = item.steps.firstIndex(where: { $0.id == tapped.id }) {
                // A plain step (no detail yet) opens straight into edit mode —
                // there's nothing to read otherwise.
                StepDetailView(step: $item.steps[idx], startInEditMode: !tapped.hasDetail) {
                    // The sheet edits item.steps in place; only the item can stamp
                    // itself, so it does it here.
                    item.touch()
                    SyncCoordinator.shared.noteLocalChange()
                }
            }
        }
        // Reusing "List full" — it's the same ceiling the create flow reports.
        .alert("List full", isPresented: $moveBlocked) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("That person's list is already full. Remove a to-do from it first, then move this one.")
        }
        .onDisappear {
            if !didDelete, item.modelContext != nil {
                // COMMIT EDITS THAT NEVER GOT A "Done" TAP.
                //
                // Every field here binds straight to `$item`, so typing has already
                // mutated the stored model — but `touch()` only ran on the Done
                // button. Leaving by the back chevron or a swipe therefore saved the
                // edit locally while `updatedAt` stayed old, which means the push
                // filter (`updatedAt > watermark`) skips it and the next pull from
                // another device overwrites it. The user's edit vanishes with no
                // error anywhere. Committing on the way out closes that path.
                if isEditing { commitIfChanged() }
                ReminderScheduler.shared.reschedule(for: item)
            }
        }
    }

    // Reassigning the to-do to a different person.
    //
    // Goes through a proxy binding rather than `$item.profileID` for two reasons:
    // it has to REFUSE a move into a list that's already at its cap, and it has to
    // stamp the change itself.
    private var assigneeBinding: Binding<UUID?> {
        Binding(
            get: { item.profileID },
            set: { newID in
                guard newID != item.profileID else { return }
                // Caps are PER PERSON (TaskLimit counts one bucket), so a move can
                // push the destination over even though the account total is
                // unchanged. Without this, moving would be a free way around the
                // per-profile cap: create in an empty list, then shuffle across.
                guard TaskLimit.count(context, profileID: newID)
                        < TaskLimit.cap(plus: plus.paidFeaturesUnlocked) else {
                    moveBlocked = true
                    return
                }
                item.profileID = newID
                item.touch()
                SyncCoordinator.shared.noteLocalChange()
            })
    }

    // Stamp `updatedAt` ONLY if something actually changed.
    //
    // ⚠️ AN UNCONDITIONAL touch() IS NOT THE SAFE DEFAULT — it's a different data
    // loss. Under last-writer-wins, stamping on the way out of a screen the user
    // only LOOKED at makes this stale copy the newest version of the item, so it
    // overwrites a genuine edit made on another device in the meantime. Opening a
    // to-do to read it must never beat someone else's real change.
    private func commitIfChanged() {
        defer { editSnapshot = nil }
        // No snapshot means edit mode was never entered through the button — treat
        // that as "nothing to commit" rather than stamping blind.
        guard let editSnapshot, TaskDTO(item) != editSnapshot else { return }
        item.touch()
        SyncCoordinator.shared.noteLocalChange()
    }

    // MARK: nav — back · ACTION · Edit/Done

    private var navBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium)).foregroundStyle(Color.faint)
            }
            .accessibilityLabel("Back")
            Spacer()
            Text("ACTION").font(.eyebrow).tracking(1.4).foregroundStyle(Color.faded)
            Spacer()
            Button {
                if isEditing {                  // leaving edit mode = commit
                    commitIfChanged()
                } else {                        // entering = remember the "before"
                    editSnapshot = TaskDTO(item)
                }
                isEditing.toggle()
            } label: {
                Text(isEditing ? "Done" : "Edit")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.accent)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: head — tag · title · status · chips

    private var headCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text(tagText).font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)

                // WHO THIS IS FOR — changeable after the fact.
                //
                // Filing something under the wrong person used to be permanent:
                // the only fix was deleting it and typing it again. The row shows
                // in read mode too (not just Edit), because moving a letter to Mum
                // is a quick correction, not an editing session — which is exactly
                // why the binding stamps immediately rather than waiting for
                // `commitIfChanged`, since that only runs when leaving edit mode.
                //
                // Renders nothing when the account has no family (AssigneeRow).
                AssigneeRow(profileID: assigneeBinding)

                if isEditing {
                    TextField("Title", text: $item.title, prompt: fieldPrompt("Title"), axis: .vertical)
                        .font(.serifDetail).tracking(-0.4).foregroundStyle(Color.ink)
                } else {
                    Text(item.title).font(.serifDetail).tracking(-0.4).foregroundStyle(Color.ink)
                }

                if !isEditing, !isDone, let overdue = item.overdueText {
                    // Amber for "due today" (not a failure yet), red once truly past.
                    Text(overdue).font(.eyebrow).tracking(0.6).foregroundStyle(item.dueColor)
                }
                if isDone {
                    Text("✓ COMPLETED").font(.eyebrow).tracking(0.6).foregroundStyle(Color.ok)
                }

                // Read mode: amount + due side by side. Edit mode: stacked, so the
                // date picker gets full width instead of a cramped half-column.
                if isEditing {
                    VStack(spacing: 8) {
                        amountChip   // editable now — add or fix the amount on a saved item
                        dueChip
                    }
                    .padding(.top, 2)
                } else {
                    HStack(spacing: 8) {
                        if item.amount != nil { amountChip }
                        dueChip   // always shown; offers "Add date" when there's none
                    }
                    .padding(.top, 2)
                }

                if isEditing || item.recurrence != nil { repeatsRow }
            }
        }
    }

    // REPEATS — read mode shows the cadence; edit mode lets you set/clear it.
    // A recurring item spawns its next cycle when marked done.
    private var repeatsRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.faded)
            Text("REPEATS").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
            Spacer()
            if isEditing {
                Menu {
                    Button("Doesn't repeat") { item.recurrence = nil }
                    ForEach(Recurrence.presets, id: \.self) { preset in
                        Button(preset.label) { item.recurrence = preset }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(item.recurrence?.label ?? "Doesn't repeat")
                            .font(.subline).foregroundStyle(Color.accent)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.accent)
                    }
                }
            } else if let r = item.recurrence {
                Text(r.label).font(.subline).foregroundStyle(Color.ink)
            }
        }
        .padding(.top, 2)
    }

    private var tagText: String {
        let type = item.documentType.isEmpty ? item.category.displayName : item.documentType
        let sender = item.sender.isEmpty ? nil : item.sender
        return [type, sender].compactMap { $0 }.joined(separator: " · ").uppercased()
    }

    private var amountChip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AMOUNT").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
            if isEditing {
                AmountInput(amount: $item.amount)
            } else if let amount = item.amountText {
                Text(amount).font(.serifStat).tracking(-0.5).foregroundStyle(Color.ink)
                    .minimumScaleFactor(0.5).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.bg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var dueChip: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isEditing {
                if item.dueDate != nil {
                    HStack(spacing: 6) {
                        DatePicker("", selection: dueBinding,
                                   displayedComponents: item.dueHasTime ? [.date, .hourAndMinute] : [.date])
                            .labelsHidden().datePickerStyle(.compact).tint(Color.ink)
                        Button {
                            // Clear the due date AND its (now-orphaned) reminders,
                            // so we don't schedule reminders for an item with no date.
                            item.dueDate = nil
                            item.reminders = []
                            item.remindersCustomized = false
                        } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(Color.faint)
                        }
                        .buttonStyle(.plain).accessibilityLabel("Remove due date")
                    }
                    Toggle("Specific time", isOn: $item.dueHasTime).font(.subline).tint(Color.ink)
                        // A plain date carries midnight; turning "time" on would make a
                        // 12:00 AM event that's instantly overdue. Start at 9am instead.
                        .onChange(of: item.dueHasTime) { _, on in
                            if on, let due = item.dueDate,
                               Calendar.current.dateComponents([.hour, .minute], from: due) == DateComponents(hour: 0, minute: 0) {
                                item.dueDate = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: due)
                            }
                        }
                } else {
                    Button { item.dueDate = startOfToday } label: {
                        Label("Add date", systemImage: "plus.circle").font(.subline).foregroundStyle(Color.accent)
                            .addRowTapTarget()
                    }
                    .buttonStyle(.plain)
                }
            } else if let due = item.dueDate {
                Text(dueDisplay(due, hasTime: item.dueHasTime))
                    .font(.serifStat).tracking(-0.5)
                    .foregroundStyle(item.isPastDue ? Color.bad : item.isDueToday ? Color.warn : Color.ink)
                    .minimumScaleFactor(0.5).lineLimit(2)
            } else {
                // No date yet (e.g. a guide task) — let the user add one in read mode.
                Button { item.dueDate = startOfToday; isEditing = true } label: {
                    Label("Add date", systemImage: "plus.circle").font(.subline).foregroundStyle(Color.accent)
                        .addRowTapTarget()
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.bg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: checklist

    private var checklistCard: some View {
        card {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("STEPS").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                    Spacer()
                    if !isEditing {
                        Text("\(item.doneCount) of \(item.steps.count)")
                            .font(.eyebrow).foregroundStyle(Color.faded)
                    }
                }
                .padding(.bottom, 8)

                ForEach($item.steps) { $step in
                    if isEditing {
                        HStack(alignment: .top, spacing: 10) {
                            TextField("Step", text: $step.text, prompt: fieldPrompt("Step"), axis: .vertical)
                                .font(.body14).foregroundStyle(Color.ink)
                                .focused($focused, equals: .step(step.id))
                            // Add/edit a step's mini-checklist, explanation, etc. — lives
                            // here in the general edit page, not floating in the read list.
                            Button { detailStep = step } label: {
                                Image(systemName: "pencil.circle")
                                    .font(.system(size: 18)).foregroundStyle(Color.accent)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit step details")
                            Button { item.steps.removeAll { $0.id == step.id } } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 18)).foregroundStyle(Color.faint)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 8)
                        .overlay(alignment: .top) { divider(above: step) }
                    } else if step.hasDetail {
                        HStack(alignment: .top, spacing: 10) {
                            Button {
                                $step.done.wrappedValue.toggle()
                                item.touch()
                                SyncCoordinator.shared.noteLocalChange()
                            } label: { checkbox(done: step.done) }
                                .buttonStyle(.plain)
                            // Has real detail (mini-checklist / explanation / links) — open to read it.
                            Button { detailStep = step } label: { stepText(step, chevron: true) }
                                .buttonStyle(.plain)
                        }
                        .padding(.vertical, 8)
                        .overlay(alignment: .top) { divider(above: step) }
                    } else {
                        // Nothing to read on a plain step — not tappable in the read view.
                        // Adding details happens in edit mode (the pencil above).
                        HStack(alignment: .top, spacing: 10) {
                            Button {
                                $step.done.wrappedValue.toggle()
                                item.touch()
                                SyncCoordinator.shared.noteLocalChange()
                            } label: { checkbox(done: step.done) }
                                .buttonStyle(.plain)
                            stepText(step, chevron: false)
                        }
                        .padding(.vertical, 8)
                        .overlay(alignment: .top) { divider(above: step) }
                    }
                }

                if isEditing {
                    Button {
                        let new = ChecklistStep(text: "")
                        item.steps.append(new)
                        focus(.step(new.id))
                    } label: {
                        Label("Add a step", systemImage: "plus.circle").font(.body14).foregroundStyle(Color.accent)
                            .addRowTapTarget()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func divider(above step: ChecklistStep) -> some View {
        if step.id != item.steps.first?.id {
            Rectangle().fill(Color.hairD).frame(height: 1)
        }
    }

    private func stepText(_ step: ChecklistStep, chevron: Bool) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(linked(step.text))
                .font(.body14)
                .foregroundStyle(step.done ? Color.faded : Color.ink)
                .strikethrough(step.done, color: Color.faded)
                .multilineTextAlignment(.leading).tint(Color.accent)
            Spacer()
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.faint)
            }
        }
    }

    private func checkbox(done: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(done ? Color.ok : Color.faint, lineWidth: 1.5)
            .background(RoundedRectangle(cornerRadius: 4).fill(done ? Color.ok : Color.clear))
            .frame(width: 18, height: 18)
            .overlay {
                if done {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                }
            }
    }

    // MARK: reminders — fully editable list (add / remove / retime each)

    private var remindersCard: some View {
        card {
            RemindersEditor(reminders: $item.reminders,
                            customized: $item.remindersCustomized,
                            defaults: item.defaultReminders(
                                defaultMinutes: profiles.reminderMinutes(for: item.profileID)),
                            dueDate: item.dueDate,
                            isEditing: isEditing)
        }
    }

    // MARK: details — IDs (claim/policy/confirmation)

    // DETAILS — saved IDs / provider / claim #, etc. Editable only in edit mode,
    // same as everything else; read mode just displays whatever's filled in.
    private var detailsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text("DETAILS").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                ForEach(item.otherIDs.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 5) {
                        if isEditing {
                            HStack(spacing: 8) {
                                TextField("Label", text: $item.otherIDs[i].label, prompt: fieldPrompt("Label"))
                                    .font(.eyebrow).tracking(0.5).foregroundStyle(Color.ink)
                                    .focused($focused, equals: .detailLabel(i))
                                Button { item.otherIDs.remove(at: i) } label: {
                                    Image(systemName: "minus.circle.fill").font(.system(size: 18)).foregroundStyle(Color.faint)
                                }.buttonStyle(.plain)
                            }
                        } else {
                            Text(item.otherIDs[i].label.uppercased())
                                .font(.eyebrow).tracking(0.5).foregroundStyle(Color.faded)
                        }
                        if isEditing {
                            TextField("Value", text: $item.otherIDs[i].value,
                                      prompt: fieldPrompt("Tap to fill in"))
                                .font(.body14).foregroundStyle(Color.ink)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.bg))
                        } else if !item.otherIDs[i].value.isEmpty {
                            Text(item.otherIDs[i].value)
                                .font(.body14).foregroundStyle(Color.ink)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.bg))
                        }
                    }
                }
                if isEditing {
                    Button {
                        item.otherIDs.append(DocID(label: "", value: ""))
                        focus(.detailLabel(item.otherIDs.count - 1))
                    } label: {
                        Label("Add a detail", systemImage: "plus.circle").font(.body14).foregroundStyle(Color.accent)
                            .addRowTapTarget()
                    }.buttonStyle(.plain)
                }
                if let site = siteURLToShow {
                    Link(destination: site) {
                        Text("Website: \(site.host() ?? site.absoluteString)")
                            .font(.subline).foregroundStyle(Color.accent)
                    }
                }
            }
        }
    }

    // The website, but only if it isn't already linkified inside steps/notes.
    private var siteURLToShow: URL? {
        guard !item.siteURL.isEmpty, let url = URL(string: item.siteURL) else { return nil }
        let hay = (item.steps.map(\.text) + item.notes).joined(separator: " ").lowercased()
        let host = (url.host() ?? item.siteURL).lowercased()
        return hay.contains(host) ? nil : url
    }

    // MARK: notes (a checklist of notes — same editor as Review / Create) — last

    private var noteCard: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Text("NOTES").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)

                if isEditing {
                    ForEach(item.notes.indices, id: \.self) { i in
                        HStack(alignment: .top, spacing: 8) {
                            TextField("Note", text: $item.notes[i], prompt: fieldPrompt("Note"), axis: .vertical)
                                .font(.body14).foregroundStyle(Color.ink)
                                .focused($focused, equals: .note(i))
                            Button { item.notes.remove(at: i) } label: {
                                Image(systemName: "minus.circle.fill").font(.system(size: 18)).foregroundStyle(Color.faint)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button {
                        item.notes.append("")
                        focus(.note(item.notes.count - 1))
                    } label: {
                        Label("Add a note", systemImage: "plus.circle").font(.body14).foregroundStyle(Color.accent)
                            .addRowTapTarget()
                    }
                    .buttonStyle(.plain)
                } else {
                    ForEach(item.notes.indices, id: \.self) { i in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•").font(.body14).foregroundStyle(Color.faded)
                            Text(linked(item.notes[i])).font(.body14).foregroundStyle(Color.faded).tint(Color.accent)
                        }
                    }
                }
            }
        }
    }

    // MARK: original photo — the scanned document, kept at the very end so the
    // user can always go back to the source. Tap to view it full-screen.

    private var storedPhoto: UIImage? {
        item.imageData.flatMap(UIImage.init(data:))
    }

    private func photoCard(_ photo: UIImage) -> some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text("ORIGINAL DOCUMENT").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                // A small preview only — the full document is a tap away in the
                // pinch-zoom viewer, so it doesn't need to fill the page here.
                Button { showFullPhoto = true } label: {
                    Image(uiImage: photo)
                        .resizable().scaledToFill()
                        .frame(width: 96, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.hair, lineWidth: 1))
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(Circle().fill(.black.opacity(0.45)))
                                .padding(6)
                        }
                }
                .buttonStyle(.plain)
                Text(explainLanguage == .english ? "Tap to enlarge" : "Tap to enlarge and translate")
                    .font(.subline).foregroundStyle(Color.faded)
            }
        }
        .fullScreenCover(isPresented: $showFullPhoto) {
            FullPhotoViewer(photo: photo, language: explainLanguage)
        }
    }

    // MARK: footer — Mark done / Delete

    private var footer: some View {
        Group {
            if isDone {
                // A completed item can be reopened (back to active, reminders
                // rescheduled) or deleted. Delete stays final — no undo.
                VStack(spacing: 10) {
                    Button { reopen() } label: {
                        Text("Mark as not done")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: 12).stroke(Color.hairD, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    deleteButton
                }
            } else if isEditing {
                deleteButton
            } else {
                Button { markDone() } label: {
                    Text("Mark done")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.paper)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.ink))
                }
                .buttonStyle(.plain)
            }
        }
        .confirmationDialog(deleteDialogTitle, isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            if canSplitRecurring {
                // A live recurring task with a due date: deleting just this one
                // keeps the series going (spawns the next cycle); "this and all
                // future" stops it.
                Button("Delete just this one") { skipToNextAndDelete() }
                Button("Delete this and all future", role: .destructive) { deleteItem() }
            } else {
                Button("Delete", role: .destructive) { deleteItem() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // The "this one vs. all future" choice only makes sense when a next cycle can
    // actually be spawned — i.e. recurring AND dated. A recurring item with no due
    // date can't advance (makeNextOccurrence returns nil), so "just this one"
    // would silently end the series; offer a plain delete instead.
    private var canSplitRecurring: Bool { item.isRecurring && item.dueDate != nil && !isDone }

    private var deleteButton: some View {
        Button(role: .destructive) { showDeleteConfirm = true } label: {
            Text("Delete")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.bad)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: 12).stroke(Color.bad.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var deleteDialogTitle: LocalizedStringKey {
        canSplitRecurring ? "This is a repeating task" : "Delete this task?"
    }

    // Reopen a done item: back to active (the Inbox re-buckets it by urgency /
    // derived in-progress) and reschedule its still-future reminders.
    private func reopen() {
        ItemActions.reopen(item)   // centralized so all reopen paths stay in sync
    }

    private func markDone() {
        // Shared with the Inbox swipe + the notification "Mark done" action
        // (ItemActions) so the three can't diverge. Idempotent; handles the
        // metric log, reminder cancel, and recurring spawn + prune.
        ItemActions.complete(item, in: context)
    }

    private func deleteItem() {
        didDelete = true
        // Centralized so the reminder-cancel + delete-tombstone (for sync) can't
        // drift from the Inbox swipe / notification paths.
        if item.modelContext != nil {
            ItemActions.delete(item, in: context)
        } else {
            ReminderScheduler.shared.cancel(itemID: item.id)
        }
        dismiss()
    }

    // Delete this occurrence but keep the series alive at its next date. (No
    // prune: we're about to delete the current one, leaving the spawn as the only
    // active — pruning here would risk removing the wrong one.)
    private func skipToNextAndDelete() {
        _ = spawnNextOccurrence()
        deleteItem()
    }

    // Insert the next cycle of a recurring item and schedule its reminders.
    // Stamps the series id so the parent and the new cycle are linked.
    @discardableResult
    private func spawnNextOccurrence() -> ActionItem? {
        guard let next = item.makeNextOccurrence() else { return nil }
        item.seriesID = item.effectiveSeriesID
        context.insert(next)
        ReminderScheduler.shared.reschedule(for: next)
        return next
    }

    private var dueBinding: Binding<Date> {
        Binding(get: { item.dueDate ?? startOfToday },
                set: { newValue in
                    // Custom reminder times were picked relative to the OLD date —
                    // slide them by the same number of days so "1 day before at
                    // 9am" stays 1 day before, instead of silently going stale.
                    if item.remindersCustomized {
                        item.reminders = ActionItem.shiftedReminders(
                            item.reminders, fromDue: item.dueDate, toDue: newValue)
                    }
                    item.dueDate = newValue
                })
    }

    // MARK: shared helpers

    // Focus a row that was appended in this same tap. One runloop hop: the field
    // doesn't exist yet when the button's action runs, and @FocusState silently
    // ignores a value with no matching field.
    private func focus(_ field: Field) {
        Task { @MainActor in focused = field }
    }

    private func card<C: View>(@ViewBuilder _ inner: () -> C) -> some View {
        inner()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }

    // URLs + phone numbers → tappable links (shared with Review/StepDetail).
    private func linked(_ string: String) -> AttributedString { linkified(string) }
}

#Preview {
    // Both stores are required by @Environment lookups in this view, and a missing
    // one traps at runtime — the preview was already short of ProfileStore.
    DetailView(item: ActionItem(title: "Preview item", category: .utility,
                                dueDate: .now, steps: [ChecklistStep(text: "A step")]))
        .modelContainer(for: ActionItem.self, inMemory: true)
        .environment(ProfileStore())
        .environment(PlusStore())
}
