//  DetailView.swift
//
//  Action detail — the full view of one stored item. Because it binds to
//  the live SwiftData object (@Bindable), edits, Mark done, and Delete
//  write straight through to the store and the Inbox reflects them.
//
//  Composed of optional, item-driven sections (stats / steps / reminders
//  / note) — different item TYPES can compose different sections later
//  without a rewrite. Top-right Edit (like Review); no manual status, no
//  Defer; once done, a Delete option appears.
//

import SwiftUI
import SwiftData

struct DetailView: View {
    @Bindable var item: ActionItem

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false

    private var isDone: Bool { item.status == .done }
    private var startOfToday: Date { Calendar.current.startOfDay(for: .now) }

    var body: some View {
        ZStack(alignment: .top) {
            Color.paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    navBar
                    titleBlock
                        .padding(.horizontal, 24)
                        .padding(.top, 8)

                    if item.amountText != nil || item.dueText != nil {
                        statsCard
                            .padding(.horizontal, 14)
                            .padding(.top, 16)
                    }

                    if !item.steps.isEmpty || isEditing {
                        checklistCard
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
                    }

                    if !item.reminderSchedule().isEmpty {
                        remindersCard
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
                    }

                    if !item.note.isEmpty || isEditing {
                        noteCard
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
                    }

                    footer
                        .padding(.horizontal, 14)
                        .padding(.top, 18)

                    Spacer(minLength: 40)
                }
                .padding(.top, 48)
            }
        }
        .navigationBarHidden(true)
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
        .padding(.horizontal, 22)
    }

    // MARK: title + status line

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title)
                .font(.serifDetail).tracking(-0.6).foregroundStyle(Color.ink)
            if !isEditing, !isDone, let note = item.overdueText {
                Text(note).font(.eyebrow).tracking(0.6).foregroundStyle(Color.bad)
            }
            if isDone {
                Text("✓ COMPLETED").font(.eyebrow).tracking(0.6).foregroundStyle(Color.ok)
            }
        }
    }

    // MARK: stats — amount (static) + due (editable)

    private var statsCard: some View {
        HStack(spacing: 14) {
            if let amount = item.amountText {
                statField(label: "AMOUNT", value: amount, tone: Color.ink)
            }
            if isEditing {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DUE").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                    DatePicker("", selection: dueBinding, displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.compact)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let dueText = item.dueText {
                statField(label: "DUE", value: dueText,
                          tone: item.isOverdue ? Color.bad : Color.ink)
            }
        }
        .padding(16)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }

    private func statField(label: String, value: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
            Text(value).font(.serifStat).tracking(-0.6).foregroundStyle(tone)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: checklist

    private var checklistCard: some View {
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
                            Text(step.text)
                                .font(.body14)
                                .foregroundStyle(step.done ? Color.faded : Color.ink)
                                .strikethrough(step.done, color: Color.faded)
                                .multilineTextAlignment(.leading)
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
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle").font(.system(size: 16))
                        Text("Add a step").font(.body14)
                    }
                    .foregroundStyle(Color.accent)
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
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
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                }
            }
    }

    // MARK: reminders (derived)

    private var remindersCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("REMINDERS").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                .padding(.bottom, 10)

            ForEach(item.reminderSchedule()) { reminder in
                let isPast = reminder.date < startOfToday
                HStack(spacing: 10) {
                    Text(reminder.date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.eyebrow).tracking(0.4)
                        .foregroundStyle(isPast ? Color.faint : Color.ink)
                        .frame(width: 60, alignment: .leading)
                    Text(reminder.label)
                        .font(.subline).foregroundStyle(isPast ? Color.faded : Color.ink)
                    Spacer()
                    Circle().fill(isPast ? Color.hairD : Color.accent).frame(width: 6, height: 6)
                }
                .padding(.vertical, 7)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }

    // MARK: note

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTE").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
            if isEditing {
                TextField("Add a note…", text: $item.note, axis: .vertical)
                    .font(.body14).foregroundStyle(Color.ink).lineLimit(2...5)
            } else {
                Text(item.note).font(.body14).foregroundStyle(Color.ink)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }

    // MARK: footer — Mark done, then Delete once done

    private var footer: some View {
        Group {
            if isDone {
                Button(role: .destructive) { deleteItem() } label: {
                    Text("Delete")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.bad)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.bad.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else {
                Button { item.status = .done } label: {
                    Text("Mark done")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.paper)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.ink))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // Delete only touches the store if the item actually lives there
    // (a guide-preview item isn't saved yet — just close).
    // TODO (Week 7): recurring items should ask "this one or future too?".
    private func deleteItem() {
        if item.modelContext != nil { context.delete(item) }
        dismiss()
    }

    private var dueBinding: Binding<Date> {
        Binding(get: { item.dueDate ?? startOfToday }, set: { item.dueDate = $0 })
    }
}

#Preview {
    DetailView(item: ActionItem.samples[0])
        .modelContainer(for: ActionItem.self, inMemory: true)
}
