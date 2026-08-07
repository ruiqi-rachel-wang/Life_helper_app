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

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var showDeleteConfirm = false
    @State private var didDelete = false
    @State private var detailStep: ChecklistStep?   // tapped step → detail sheet
    @State private var showFullPhoto = false         // tapped photo → full-screen viewer

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
                StepDetailView(step: $item.steps[idx], startInEditMode: !tapped.hasDetail)
            }
        }
        .onDisappear {
            if !didDelete, item.modelContext != nil {
                ReminderScheduler.shared.reschedule(for: item)
            }
        }
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
                    item.touch()
                    SyncCoordinator.shared.noteLocalChange()
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

                if isEditing {
                    TextField("Title", text: $item.title, axis: .vertical)
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
                            .labelsHidden().datePickerStyle(.compact)
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
                            TextField("Step", text: $step.text, axis: .vertical)
                                .font(.body14).foregroundStyle(Color.ink)
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
                    Button { item.steps.append(ChecklistStep(text: "")) } label: {
                        Label("Add a step", systemImage: "plus.circle").font(.body14).foregroundStyle(Color.accent)
                    }
                    .buttonStyle(.plain).padding(.top, 10)
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
                            defaults: item.defaultReminders(),
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
                                TextField("Label", text: $item.otherIDs[i].label)
                                    .font(.eyebrow).tracking(0.5).foregroundStyle(Color.faded)
                                Button { item.otherIDs.remove(at: i) } label: {
                                    Image(systemName: "minus.circle.fill").font(.system(size: 18)).foregroundStyle(Color.faint)
                                }.buttonStyle(.plain)
                            }
                        } else {
                            Text(item.otherIDs[i].label.uppercased())
                                .font(.eyebrow).tracking(0.5).foregroundStyle(Color.faded)
                        }
                        if isEditing {
                            TextField("Tap to fill in", text: $item.otherIDs[i].value)
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
                    Button { item.otherIDs.append(DocID(label: "", value: "")) } label: {
                        Label("Add a detail", systemImage: "plus.circle").font(.body14).foregroundStyle(Color.accent)
                    }.buttonStyle(.plain).padding(.top, 2)
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
                            TextField("Note", text: $item.notes[i], axis: .vertical)
                                .font(.body14).foregroundStyle(Color.faded)
                            Button { item.notes.remove(at: i) } label: {
                                Image(systemName: "minus.circle.fill").font(.system(size: 18)).foregroundStyle(Color.faint)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button { item.notes.append("") } label: {
                        Label("Add a note", systemImage: "plus.circle").font(.body14).foregroundStyle(Color.accent)
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
                    .font(.subline).foregroundStyle(Color.faint)
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
    DetailView(item: ActionItem(title: "Preview item", category: .utility,
                                dueDate: .now, steps: [ChecklistStep(text: "A step")]))
        .modelContainer(for: ActionItem.self, inMemory: true)
}
