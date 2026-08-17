//  RemindersEditor.swift
//
//  ONE reminders editor, shared by the Detail page (editing a saved ActionItem) and
//  the Review page (editing a scan/guide draft before saving). It works on bindings,
//  so it doesn't care which screen it's on — "just some difference based on where we
//  are" is only the data it's bound to. Renders the inner content; each screen wraps
//  it in its own card.
//

import SwiftUI

struct RemindersEditor: View {
    @Binding var reminders: [ReminderItem]
    @Binding var customized: Bool
    let defaults: [ReminderItem]      // smart defaults derived from the due date
    let dueDate: Date?
    let isEditing: Bool

    // The user's custom list once edited, otherwise the smart defaults.
    private var shown: [ReminderItem] { customized ? reminders : defaults }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("REMINDERS").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                Spacer()
                if isEditing {
                    // The smallest tap target in the app before this — an 11.5pt
                    // Label with no padding inside the button. contentShape +
                    // 44pt makes it hittable.
                    Button { add() } label: {
                        Label("Add", systemImage: "plus.circle").font(.body14).foregroundStyle(Color.accent)
                            .frame(minWidth: 72, minHeight: 44, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 10)

            if shown.isEmpty {
                Text(isEditing ? "No reminders — add one above." : "No reminders.")
                    .font(.subline).foregroundStyle(Color.faded)
            }
            ForEach(shown.indices, id: \.self) { i in
                if isEditing {
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            DatePicker("", selection: dateBinding(i), displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden().datePickerStyle(.compact).tint(Color.ink)
                            Spacer()
                            Button { delete(i) } label: {
                                Image(systemName: "minus.circle.fill").font(.system(size: 18)).foregroundStyle(Color.faint)
                            }
                            .buttonStyle(.plain)
                        }
                        // Optional note shown in the notification banner.
                        TextField("Reminder note", text: noteBinding(i),
                                  prompt: fieldPrompt("Note (optional) — shown in the alert"))
                            .font(.subline).foregroundStyle(Color.ink)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.bg))
                    }
                    .padding(.vertical, 6)
                } else {
                    let isPast = shown[i].date < .now
                    HStack(spacing: 10) {
                        Text(shown[i].date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.eyebrow).tracking(0.4)
                            .foregroundStyle(isPast ? Color.faded : Color.ink)
                            .frame(width: 60, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shown[i].date.formatted(.dateTime.hour().minute()))
                                .font(.subline).foregroundStyle(isPast ? Color.faded : Color.ink)
                            if !shown[i].note.isEmpty {
                                Text(shown[i].note)
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

    // Editing any reminder switches to a custom list (seeded from the smart
    // defaults), after which `reminders` is authoritative.
    private func ensureCustomized() {
        if !customized { reminders = defaults; customized = true }
    }
    private func dateBinding(_ i: Int) -> Binding<Date> {
        Binding(
            get: { i < shown.count ? shown[i].date : .now },
            set: { newValue in
                ensureCustomized()
                if reminders.indices.contains(i) { reminders[i].date = newValue }
            })
    }
    private func noteBinding(_ i: Int) -> Binding<String> {
        Binding(
            get: { i < shown.count ? shown[i].note : "" },
            set: { newValue in
                ensureCustomized()
                if reminders.indices.contains(i) { reminders[i].note = newValue }
            })
    }
    private func delete(_ i: Int) {
        ensureCustomized()
        if reminders.indices.contains(i) { reminders.remove(at: i) }
    }
    private func add() {
        ensureCustomized()
        let base = dueDate ?? Date()
        let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: base) ?? base
        let fire = Calendar.current.date(bySettingHour: AppSettings.defaultReminderHour,
                                         minute: AppSettings.defaultReminderMinute,
                                         second: 0, of: dayBefore) ?? dayBefore
        reminders.append(ReminderItem(date: fire))
    }
}
