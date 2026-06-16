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

struct DetailView: View {
    @Bindable var item: ActionItem

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var showDeleteConfirm = false
    @State private var didDelete = false
    @State private var detailStep: ChecklistStep?   // tapped step → detail sheet

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
                    if !item.notes.isEmpty || !item.note.isEmpty || isEditing { noteCard }
                    footer
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 14)
                .padding(.top, 48)
            }
        }
        .navigationBarHidden(true)
        .sheet(item: $detailStep) { tapped in
            if let idx = item.steps.firstIndex(where: { $0.id == tapped.id }) {
                StepDetailView(step: $item.steps[idx])   // edits persist to the item
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
            Button { isEditing.toggle() } label: {
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
                    Text(overdue).font(.eyebrow).tracking(0.6).foregroundStyle(Color.bad)
                }
                if isDone {
                    Text("✓ COMPLETED").font(.eyebrow).tracking(0.6).foregroundStyle(Color.ok)
                }

                HStack(spacing: 8) {
                    if let amount = item.amountText { chipBox("AMOUNT", amount, tone: Color.ink) }
                    dueChip   // always shown; offers "Add date" when there's none
                }
                .padding(.top, 2)

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
        let type = item.documentType.isEmpty ? item.category.rawValue.capitalized : item.documentType
        let sender = item.sender.isEmpty ? nil : item.sender
        return [type, sender].compactMap { $0 }.joined(separator: " · ").uppercased()
    }

    private func chipBox(_ label: String, _ value: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
            Text(value).font(.serifStat).tracking(-0.5).foregroundStyle(tone)
                .minimumScaleFactor(0.5).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.bg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var dueChip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DUE").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
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
                } else {
                    Button { item.dueDate = startOfToday } label: {
                        Label("Add date", systemImage: "plus.circle").font(.subline).foregroundStyle(Color.accent)
                    }
                    .buttonStyle(.plain)
                }
            } else if let due = item.dueDate {
                Text(dueDisplay(due, hasTime: item.dueHasTime))
                    .font(.serifStat).tracking(-0.5)
                    .foregroundStyle(item.isOverdue ? Color.bad : Color.ink)
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
                            Button { item.steps.removeAll { $0.id == step.id } } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 18)).foregroundStyle(Color.faint)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 8)
                        .overlay(alignment: .top) { divider(above: step) }
                    } else {
                        HStack(alignment: .top, spacing: 10) {
                            Button { $step.done.wrappedValue.toggle() } label: { checkbox(done: step.done) }
                                .buttonStyle(.plain)
                            // Tapping the text opens the step's detail, but only
                            // when there IS detail — a plain step stays full-color
                            // (a disabled Button would gray it out).
                            if step.hasDetail {
                                Button { detailStep = step } label: { stepText(step, chevron: true) }
                                    .buttonStyle(.plain)
                            } else {
                                stepText(step, chevron: false)
                            }
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
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("REMINDERS").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                    Spacer()
                    if isEditing {
                        Button { addReminder() } label: {
                            Label("Add", systemImage: "plus.circle").font(.eyebrow).foregroundStyle(Color.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 10)

                let reminders = item.effectiveReminders
                if reminders.isEmpty {
                    Text(isEditing ? "No reminders — add one above." : "No reminders.")
                        .font(.subline).foregroundStyle(Color.faded)
                }
                ForEach(reminders.indices, id: \.self) { i in
                    if isEditing {
                        VStack(spacing: 6) {
                            HStack(spacing: 8) {
                                DatePicker("", selection: reminderDateBinding(i), displayedComponents: [.date, .hourAndMinute])
                                    .labelsHidden().datePickerStyle(.compact)
                                Spacer()
                                Button { deleteReminder(i) } label: {
                                    Image(systemName: "minus.circle.fill").font(.system(size: 18)).foregroundStyle(Color.faint)
                                }
                                .buttonStyle(.plain)
                            }
                            // Optional note shown in the notification banner.
                            TextField("Note (optional) — shown in the alert", text: reminderNoteBinding(i))
                                .font(.subline).foregroundStyle(Color.ink)
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.bg))
                        }
                        .padding(.vertical, 6)
                    } else {
                        let isPast = reminders[i].date < .now
                        HStack(spacing: 10) {
                            Text(reminders[i].date.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.eyebrow).tracking(0.4)
                                .foregroundStyle(isPast ? Color.faint : Color.ink)
                                .frame(width: 60, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reminders[i].date.formatted(.dateTime.hour().minute()))
                                    .font(.subline).foregroundStyle(isPast ? Color.faded : Color.ink)
                                if !reminders[i].note.isEmpty {
                                    Text(reminders[i].note)
                                        .font(.subline).foregroundStyle(Color.faded).lineLimit(2)
                                }
                            }
                            Spacer()
                            Circle().fill(isPast ? Color.hairD : Color.accent).frame(width: 6, height: 6)
                        }
                        .padding(.vertical, 7)
                    }
                }
            }
        }
    }

    // Editing any reminder switches the item to a custom list (seeded from the
    // current smart defaults), after which `reminders` is authoritative.
    private func ensureRemindersCustomized() {
        if !item.remindersCustomized {
            item.reminders = item.defaultReminders()
            item.remindersCustomized = true
        }
    }
    private func reminderDateBinding(_ i: Int) -> Binding<Date> {
        Binding(
            get: { let r = item.effectiveReminders; return i < r.count ? r[i].date : .now },
            set: { newValue in
                ensureRemindersCustomized()
                if item.reminders.indices.contains(i) { item.reminders[i].date = newValue }
            })
    }
    private func reminderNoteBinding(_ i: Int) -> Binding<String> {
        Binding(
            get: { let r = item.effectiveReminders; return i < r.count ? r[i].note : "" },
            set: { newValue in
                ensureRemindersCustomized()
                if item.reminders.indices.contains(i) { item.reminders[i].note = newValue }
            })
    }
    private func deleteReminder(_ i: Int) {
        ensureRemindersCustomized()
        if item.reminders.indices.contains(i) { item.reminders.remove(at: i) }
    }
    private func addReminder() {
        ensureRemindersCustomized()
        let base = item.dueDate ?? Date()
        let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: base) ?? base
        let fire = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: dayBefore) ?? dayBefore
        item.reminders.append(ReminderItem(date: fire))
    }

    // MARK: details — IDs (claim/policy/confirmation)

    // DETAILS — saved IDs / provider / claim #, etc. Values are editable inline
    // (tap to fill, even in read mode); labels and add/remove appear in edit mode.
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
                        TextField("Tap to fill in", text: $item.otherIDs[i].value)
                            .font(.body14).foregroundStyle(Color.ink)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.bg))
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

    // MARK: notes (AI notes + the user's free note) — last

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
                    TextField("Your own note…", text: $item.note, axis: .vertical)
                        .font(.body14).foregroundStyle(Color.ink).lineLimit(2...5).padding(.top, 4)
                } else {
                    ForEach(item.notes.indices, id: \.self) { i in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•").font(.body14).foregroundStyle(Color.faded)
                            Text(linked(item.notes[i])).font(.body14).foregroundStyle(Color.faded).tint(Color.accent)
                        }
                    }
                    if !item.note.isEmpty {
                        Text(item.note).font(.body14).foregroundStyle(Color.ink).padding(.top, item.notes.isEmpty ? 0 : 4)
                    }
                }
            }
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

    private var deleteDialogTitle: String {
        canSplitRecurring ? "This is a repeating task" : "Delete this task?"
    }

    // Reopen a done item: back to active (the Inbox re-buckets it by urgency /
    // derived in-progress) and reschedule its still-future reminders.
    private func reopen() {
        item.status = .todo
        ReminderScheduler.shared.reschedule(for: item)
    }

    private func markDone() {
        // Idempotent: an already-done item must not re-log a completion or spawn
        // another next cycle (e.g. tapping a stale notification action after
        // completing in the app).
        guard item.status != .done else { return }
        Metrics.record(.completed, itemID: item.id, onTime: item.doneOnTime())
        item.status = .done
        ReminderScheduler.shared.cancel(itemID: item.id)
        if spawnNextOccurrence() != nil {
            // Keep the series to one active + one done so cycles can't pile up.
            pruneSeries(item.effectiveSeriesID)
        }
    }

    private func deleteItem() {
        didDelete = true
        ReminderScheduler.shared.cancel(itemID: item.id)
        if item.modelContext != nil { context.delete(item) }
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

    // Enforce at most one active + one done per recurring series, deleting the
    // rest (and cancelling their reminders).
    private func pruneSeries(_ sid: UUID) {
        let descriptor = FetchDescriptor<ActionItem>(predicate: #Predicate { $0.seriesID == sid })
        guard let members = try? context.fetch(descriptor) else { return }
        for redundant in ActionItem.redundantInSeries(members) {
            ReminderScheduler.shared.cancel(itemID: redundant.id)
            context.delete(redundant)
        }
    }

    private var dueBinding: Binding<Date> {
        Binding(get: { item.dueDate ?? startOfToday }, set: { item.dueDate = $0 })
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

    // URLs + phone numbers → tappable links (same as Review).
    private func linked(_ string: String) -> AttributedString {
        var attr = AttributedString(string)
        let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return attr }
        let ns = string as NSString
        for m in detector.matches(in: string, range: NSRange(location: 0, length: ns.length)) {
            guard let sr = Range(m.range, in: string),
                  let lo = AttributedString.Index(sr.lowerBound, within: attr),
                  let hi = AttributedString.Index(sr.upperBound, within: attr) else { continue }
            let url: URL? = (m.resultType == .phoneNumber)
                ? m.phoneNumber.flatMap { URL(string: "tel:" + $0.filter { $0.isNumber || $0 == "+" }) }
                : m.url
            if let url { attr[lo..<hi].link = url; attr[lo..<hi].underlineStyle = .single }
        }
        return attr
    }
}

#Preview {
    DetailView(item: ActionItem.samples[0])
        .modelContainer(for: ActionItem.self, inMemory: true)
}
