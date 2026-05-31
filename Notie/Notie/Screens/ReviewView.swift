//  ReviewView.swift
//
//  Review & Action — the hero screen, shown immediately after a scan
//  or upload. The AI has silently pre-filled every field; the user
//  glances, optionally edits, and taps "Add to inbox."
//
//  This is the screen the product wins or loses on. Treat it like a
//  product detail page, not a results screen.
//
//  TEMP: all content is mock (the Con Edison bill) and edits are held
//  in @State only — nothing persists. Week 6 wires this to a real
//  ExtractionResult and saves on "Add to inbox."
//

import SwiftUI

struct ReviewView: View {
    // Lets the × close button pop this screen off the stack.
    @Environment(\.dismiss) private var dismiss

    // Tapping "Edit" flips the editable fields into input controls.
    @State private var isEditing = false

    // ── Editable fields ──────────────────────────────────────────
    // TEMP: seeded with mock values; not persisted until Week 6. Every
    // field here is editable in Edit mode — Review is where the user
    // fixes anything the AI got wrong.
    @State private var docType      = "Utility bill"
    @State private var sender       = "Con Edison"
    @State private var title        = "An electricity bill for your apartment."
    @State private var amountText   = "86.42"
    @State private var dueDate      = Self.mockDate(month: 6, day: 15)
    @State private var reminderDate = Self.mockDate(month: 6, day: 12)
    @State private var note         = ""
    @State private var repeatsMonthly = true
    @State private var steps: [ChecklistStep] = [
        ChecklistStep(text: "Open Con Edison and sign in."),
        ChecklistStep(text: "Pay $86.42 before June 15."),
        ChecklistStep(text: "Save the confirmation number."),
        ChecklistStep(text: "Mark this done in Notie."),
    ]

    var body: some View {
        ZStack(alignment: .top) {
            Color.paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    modalHeader
                    documentHead
                        .padding(.horizontal, 24)
                        .padding(.top, 8)

                    statCards
                        .padding(.horizontal, 14)
                        .padding(.top, 18)

                    actionStepsCard
                        .padding(.horizontal, 14)
                        .padding(.top, 18)

                    noteCard
                        .padding(.horizontal, 14)
                        .padding(.top, 14)

                    remindersCard
                        .padding(.horizontal, 14)
                        .padding(.top, 14)

                    confirmButton
                        .padding(.horizontal, 14)
                        .padding(.top, 18)

                    Spacer(minLength: 40)
                }
                .padding(.top, 48)
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: header

    // × close · "REVIEW" · Edit/Done toggle.
    private var modalHeader: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.faint)
            }
            .accessibilityLabel("Close")
            Spacer()
            Text("REVIEW")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(Color.faded)
            Spacer()
            Button { isEditing.toggle() } label: {
                Text(isEditing ? "Done" : "Edit")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
    }

    // MARK: document head — the AI explanation (all editable)

    private var documentHead: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditing {
                // Type · Sender as two small editable chips.
                HStack(spacing: 6) {
                    editChip("Type", text: $docType)
                    editChip("Sender", text: $sender)
                }
                // The title / explanation.
                TextField("Title", text: $title, axis: .vertical)
                    .font(.serifModal).tracking(-0.4).foregroundStyle(Color.ink)
            } else {
                Text("\(docType.uppercased()) · \(sender.uppercased())")
                    .font(.eyebrow).tracking(1.4).foregroundStyle(Color.faded)
                Text(title)
                    .font(.serifModal).tracking(-0.4).foregroundStyle(Color.ink).lineSpacing(2)
                Text("Pay $\(amountText) by \(shortDate(dueDate)) to avoid a late fee.")
                    .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
            }

            Text("EN")
                .font(.eyebrow).tracking(0.6).foregroundStyle(Color.faint)
                .padding(.top, 4)
        }
    }

    // A small pill-shaped editable field for the type / sender line.
    private func editChip(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.eyebrow).tracking(0.6).foregroundStyle(Color.ink)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(Color.bg))
    }

    // MARK: stat cards — Amount + Due (both editable)

    private var statCards: some View {
        HStack(spacing: 8) {
            statCard(label: "AMOUNT", value: "$\(amountText)", sub: "electricity",
                     tone: Color.ink,
                     editor: isEditing ? AnyView(amountEditor) : nil)
            statCard(label: "DUE", value: shortDate(dueDate), sub: dueRelative,
                     tone: Color.warn,
                     editor: isEditing ? AnyView(dueEditor) : nil)
        }
    }

    // Edits the amount inside the stat card (the big value updates live).
    private var amountEditor: some View {
        HStack(spacing: 2) {
            Text("$").font(.subline).foregroundStyle(Color.faded)
            TextField("0.00", text: $amountText)
                .font(.subline).foregroundStyle(Color.ink)
                .keyboardType(.decimalPad)
        }
    }

    private func statCard(label: String, value: String, sub: String,
                          tone: Color, editor: AnyView?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
            Text(value).font(.serifStat).tracking(-1.0).foregroundStyle(tone)
            if let editor {
                editor
            } else {
                Text(sub).font(.subline).foregroundStyle(Color.faded)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }

    // A compact date picker that edits the due date inside the stat card.
    private var dueEditor: some View {
        DatePicker("", selection: $dueDate, displayedComponents: .date)
            .labelsHidden()
            .datePickerStyle(.compact)
            .scaleEffect(0.9, anchor: .leading)
            .frame(height: 22)
    }

    // MARK: action steps (editable)

    private var actionStepsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ACTION STEPS")
                    .font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                Spacer()
                if isEditing {
                    Text("EDITING")
                        .font(.eyebrow).tracking(1.0).foregroundStyle(Color.accent)
                }
            }
            .padding(.bottom, 10)

            ForEach($steps) { $step in
                HStack(alignment: .top, spacing: 10) {
                    Text(stepNumber(for: step))
                        .font(.eyebrow)
                        .foregroundStyle(Color.faded)
                        .frame(width: 22, alignment: .leading)
                        .padding(.top, isEditing ? 8 : 0)

                    if isEditing {
                        TextField("Step", text: $step.text, axis: .vertical)
                            .font(.body14)
                            .foregroundStyle(Color.ink)
                            .textFieldStyle(.plain)
                        Button {
                            steps.removeAll { $0.id == step.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.faint)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(step.text)
                            .font(.body14)
                            .foregroundStyle(Color.ink)
                        Spacer()
                    }
                }
                .padding(.vertical, 8)
                .overlay(alignment: .top) {
                    if step.id != steps.first?.id {
                        Rectangle().fill(Color.hairD).frame(height: 1)
                    }
                }
            }

            if isEditing {
                Button {
                    steps.append(ChecklistStep(text: ""))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 16))
                        Text("Add a step")
                            .font(.body14)
                    }
                    .foregroundStyle(Color.accent)
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }

    // MARK: note (editable; hidden when empty + not editing)

    @ViewBuilder
    private var noteCard: some View {
        if isEditing || !note.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("NOTE")
                    .font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                if isEditing {
                    TextField("Add a note…", text: $note, axis: .vertical)
                        .font(.body14)
                        .foregroundStyle(Color.ink)
                        .textFieldStyle(.plain)
                        .lineLimit(2...5)
                } else {
                    Text(note)
                        .font(.body14)
                        .foregroundStyle(Color.ink)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
        }
    }

    // MARK: reminders + recurring

    private var remindersCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("REMIND ME")
                .font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                .padding(.bottom, 10)

            if isEditing {
                // Editable single reminder date.
                HStack {
                    Text("Remind me on")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Color.ink)
                    Spacer()
                    DatePicker("", selection: $reminderDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
            } else {
                // Display preset schedule as chips.
                HStack(spacing: 6) {
                    ForEach(["3 days before", "1 day before", "Due day"], id: \.self) { chip in
                        Text(chip)
                            .font(.eyebrow).tracking(0.3)
                            .foregroundStyle(Color.ink)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.bg))
                    }
                }
            }

            Rectangle().fill(Color.hairD).frame(height: 1)
                .padding(.vertical, 12)

            HStack {
                Text("Repeats monthly")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.ink)
                Spacer()
                Toggle("", isOn: $repeatsMonthly)
                    .labelsHidden()
                    .tint(Color.ink)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }

    // MARK: confirm

    // TEMP (Week 6): real version saves the item + schedules reminders,
    // then routes to the inbox. For now it just closes the screen.
    private var confirmButton: some View {
        VStack(spacing: 10) {
            Button { dismiss() } label: {
                Text("Add to inbox")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.ink))
            }
            .buttonStyle(.plain)
            Text("ORIGINAL SCAN · KEEP / DELETE")
                .font(.eyebrow).tracking(0.5).foregroundStyle(Color.faint)
        }
    }

    // MARK: helpers

    private func stepNumber(for step: ChecklistStep) -> String {
        let idx = (steps.firstIndex { $0.id == step.id } ?? 0) + 1
        return String(format: "%02d", idx)
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    // "in 4 days" / "today" / "2 days ago"
    private var dueRelative: String {
        let days = Calendar.current.dateComponents([.day], from: .now, to: dueDate).day ?? 0
        if days == 0 { return "today" }
        if days > 0  { return "in \(days) day\(days == 1 ? "" : "s")" }
        return "\(-days) day\(days == -1 ? "" : "s") ago"
    }

    // TEMP: builds a fixed mock date in the current year.
    private static func mockDate(month: Int, day: Int) -> Date {
        let year = Calendar.current.component(.year, from: .now)
        return DateComponents(calendar: .current, year: year, month: month, day: day).date ?? .now
    }
}

#Preview {
    ReviewView()
}
