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
                    if !item.otherIDs.isEmpty || siteURLToShow != nil { detailsCard }
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

                if item.amountText != nil || item.dueDate != nil || isEditing {
                    HStack(spacing: 8) {
                        if let amount = item.amountText { chipBox("AMOUNT", amount, tone: Color.ink) }
                        if item.dueDate != nil || isEditing { dueChip }
                    }
                    .padding(.top, 2)
                }
            }
        }
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
                        Button { $step.done.wrappedValue.toggle() } label: {
                            HStack(alignment: .top, spacing: 10) {
                                checkbox(done: step.done)
                                Text(linked(step.text))
                                    .font(.body14)
                                    .foregroundStyle(step.done ? Color.faded : Color.ink)
                                    .strikethrough(step.done, color: Color.faded)
                                    .multilineTextAlignment(.leading).tint(Color.accent)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
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
                        HStack(spacing: 8) {
                            DatePicker("", selection: reminderBinding(i), displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden().datePickerStyle(.compact)
                            Spacer()
                            Button { deleteReminder(i) } label: {
                                Image(systemName: "minus.circle.fill").font(.system(size: 18)).foregroundStyle(Color.faint)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 6)
                    } else {
                        let isPast = reminders[i] < .now
                        HStack(spacing: 10) {
                            Text(reminders[i].formatted(.dateTime.month(.abbreviated).day()))
                                .font(.eyebrow).tracking(0.4)
                                .foregroundStyle(isPast ? Color.faint : Color.ink)
                                .frame(width: 60, alignment: .leading)
                            Text(reminders[i].formatted(.dateTime.hour().minute()))
                                .font(.subline).foregroundStyle(isPast ? Color.faded : Color.ink)
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
            item.reminders = item.defaultReminderDates()
            item.remindersCustomized = true
        }
    }
    private func reminderBinding(_ i: Int) -> Binding<Date> {
        Binding(
            get: { let r = item.effectiveReminders; return i < r.count ? r[i] : .now },
            set: { newValue in
                ensureRemindersCustomized()
                if item.reminders.indices.contains(i) { item.reminders[i] = newValue }
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
        item.reminders.append(Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: dayBefore) ?? dayBefore)
    }

    // MARK: details — IDs (claim/policy/confirmation)

    private var detailsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 4) {
                Text("DETAILS").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                ForEach(item.otherIDs.indices, id: \.self) { i in
                    Text("\(item.otherIDs[i].label): \(item.otherIDs[i].value)")
                        .font(.subline).foregroundStyle(Color.faded).textSelection(.enabled)
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
            if isEditing || isDone {
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Text("Delete")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.bad)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 12).stroke(Color.bad.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
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
        .confirmationDialog("Delete this task?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteItem() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func markDone() {
        item.status = .done
        ReminderScheduler.shared.cancel(itemID: item.id)
    }

    private func deleteItem() {
        didDelete = true
        ReminderScheduler.shared.cancel(itemID: item.id)
        if item.modelContext != nil { context.delete(item) }
        dismiss()
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
