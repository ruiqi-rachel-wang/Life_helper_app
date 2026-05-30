//  DetailView.swift
//
//  Action detail — the full view of one inbox item, used to work it:
//  check off steps, change status, see the reminder timeline, mark done.
//
//  Driven by the ActionItem passed in. Presentation (amount/date strings,
//  colors, the reminder timeline) is derived from the domain item via
//  Theme/ItemStyle.swift + reminderSchedule(); nothing UI-specific is
//  stored on the model.
//
//  TEMP (Week 2): checkbox/status edits and Mark done / Defer don't
//  persist yet — they live in @State and the buttons just dismiss.
//

import SwiftUI

struct DetailView: View {
    let item: ActionItem

    @Environment(\.dismiss) private var dismiss

    // Editable copies seeded from the item so checkboxes + status respond.
    @State private var steps: [ChecklistStep]
    @State private var status: WorkStatus

    init(item: ActionItem) {
        self.item = item
        _steps = State(initialValue: item.steps)
        _status = State(initialValue: item.status)
    }

    private var doneCount: Int { steps.filter(\.done).count }

    // Reminder dates are computed from the item; "past" is relative to now.
    private var reminders: [ScheduledReminder] { item.reminderSchedule() }
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

                    statusCard
                        .padding(.horizontal, 14)
                        .padding(.top, 16)

                    if !steps.isEmpty {
                        checklistCard
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
                    }

                    if !reminders.isEmpty {
                        remindersCard
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
                    }

                    footerActions
                        .padding(.horizontal, 14)
                        .padding(.top, 18)

                    Spacer(minLength: 40)
                }
                .padding(.top, 48)
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: nav

    private var navBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.faint)
            }
            .accessibilityLabel("Back")
            Spacer()
            Text("ACTION")
                .font(.eyebrow).tracking(1.4).foregroundStyle(Color.faded)
            Spacer()
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.faint)
        }
        .padding(.horizontal, 22)
    }

    // MARK: title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title)
                .font(.serifDetail)
                .tracking(-0.6)
                .foregroundStyle(Color.ink)
            if let note = item.overdueText {
                Text(note)
                    .font(.eyebrow)
                    .tracking(0.6)
                    .foregroundStyle(Color.bad)
            }
        }
    }

    // MARK: amount / due / status card

    private var statusCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                if let amount = item.amountText {
                    statField(label: "AMOUNT", value: amount, tone: Color.ink)
                }
                if let due = item.dueText {
                    statField(label: "DUE", value: due,
                              tone: item.isOverdue ? Color.bad : Color.ink)
                }
            }
            .padding(.bottom, 14)

            Rectangle().fill(Color.hair).frame(height: 1)

            HStack {
                Text("STATUS")
                    .font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                Spacer()
                statusPill
            }
            .padding(.top, 12)
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

    // Segmented status selector — each segment is a Button.
    private var statusPill: some View {
        HStack(spacing: 4) {
            ForEach(WorkStatus.allCases, id: \.self) { option in
                let isActive = option == status
                Button { status = option } label: {
                    Text(option.label)
                        .font(.eyebrow).tracking(0.3)
                        .foregroundStyle(isActive ? Color.paper : Color.faded)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(isActive ? Color.ink : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.bg))
    }

    // MARK: checklist

    private var checklistCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("STEPS").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                Spacer()
                Text("\(doneCount) of \(steps.count)")
                    .font(.eyebrow).foregroundStyle(Color.faded)
            }
            .padding(.bottom, 8)

            ForEach($steps) { $step in
                Button { step.done.toggle() } label: {
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
                .overlay(alignment: .top) {
                    if step.id != steps.first?.id {
                        Rectangle().fill(Color.hairD).frame(height: 1)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }

    private func checkbox(done: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(done ? Color.ok : Color.faint, lineWidth: 1.5)
            .background(
                RoundedRectangle(cornerRadius: 4).fill(done ? Color.ok : Color.clear)
            )
            .frame(width: 18, height: 18)
            .overlay {
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
    }

    // MARK: reminders (derived from the item's schedule)

    private var remindersCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("REMINDERS").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                .padding(.bottom, 10)

            ForEach(reminders) { reminder in
                let isPast = reminder.date < startOfToday
                HStack(spacing: 10) {
                    Text(reminder.date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.eyebrow).tracking(0.4)
                        .foregroundStyle(isPast ? Color.faint : Color.ink)
                        .frame(width: 60, alignment: .leading)
                    Text(reminder.label)
                        .font(.subline)
                        .foregroundStyle(isPast ? Color.faded : Color.ink)
                    Spacer()
                    Circle()
                        .fill(isPast ? Color.hairD : Color.accent)
                        .frame(width: 6, height: 6)
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

    // MARK: footer

    // TEMP (Week 2/3): real versions persist the status change + cancel or
    // reschedule reminders. For now they just close the screen.
    private var footerActions: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Text("Mark done")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.ink))
            }
            .buttonStyle(.plain)

            Button { dismiss() } label: {
                Text("Defer")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.hairD, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    DetailView(item: .parkingTicket)
}
