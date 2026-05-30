//  DetailView.swift
//
//  Action detail — the full view of one inbox item, used to work it:
//  check off steps, change status, see the reminder timeline, mark done.
//
//  This mock shows the worst-case visual state: an overdue parking
//  ticket. Currently uses inline mock data; Week 2 feeds it a real
//  ActionItem. Checkboxes and the status pill are interactive (@State)
//  but don't persist yet.
//

import SwiftUI

struct DetailView: View {
    // Lets the custom back chevron pop this screen off the stack.
    @Environment(\.dismiss) private var dismiss

    // Local editable copies so the checkboxes + status pill respond to
    // taps. Not persisted until Week 2.
    @State private var steps: [ChecklistStep] = [
        ChecklistStep(text: "Decide: pay or contest.", done: true),
        ChecklistStep(text: "Open NYC Pay Tickets.", done: true),
        ChecklistStep(text: "Enter violation #1234567890.", done: false),
        ChecklistStep(text: "Pay $115.00 before June 9.", done: false),
    ]
    @State private var status: WorkStatus = .inProgress

    private var doneCount: Int { steps.filter(\.done).count }

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

                    checklistCard
                        .padding(.horizontal, 14)
                        .padding(.top, 14)

                    remindersCard
                        .padding(.horizontal, 14)
                        .padding(.top, 14)

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
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.faint)
                .onTapGesture { dismiss() }
            Spacer()
            Text("ACTION")
                .font(.eyebrow)
                .tracking(1.4)
                .foregroundStyle(Color.faded)
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
            Text("NYC parking ticket")
                .font(.serifDetail)
                .tracking(-0.6)
                .foregroundStyle(Color.ink)
            Text("⚠ 2 DAYS OVERDUE · $50 PENALTY IF NOT PAID")
                .font(.eyebrow)
                .tracking(0.6)
                .foregroundStyle(Color.bad)
        }
    }

    // MARK: amount / due / status card

    private var statusCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                statField(label: "AMOUNT", value: "$115.00", tone: Color.ink)
                statField(label: "DUE", value: "Jun 9", tone: Color.bad)
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

    // Segmented status selector. Tapping a segment updates @State.
    private var statusPill: some View {
        HStack(spacing: 4) {
            ForEach(WorkStatus.allCases, id: \.self) { option in
                let isActive = option == status
                Text(option.label)
                    .font(.eyebrow)
                    .tracking(0.3)
                    .foregroundStyle(isActive ? Color.paper : Color.faded)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(isActive ? Color.ink : Color.clear))
                    .onTapGesture { status = option }
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
                HStack(alignment: .top, spacing: 10) {
                    checkbox(done: step.done)
                        .onTapGesture { step.done.toggle() }
                    Text(step.text)
                        .font(.body14)
                        .foregroundStyle(step.done ? Color.faded : Color.ink)
                        .strikethrough(step.done, color: Color.faded)
                    Spacer()
                }
                .padding(.vertical, 8)
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

    // MARK: reminders

    private var remindersCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("REMINDERS").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                .padding(.bottom, 10)

            reminderRow(date: "Jun 06", label: "3 days before", isPast: true)
            reminderRow(date: "Jun 08", label: "1 day before", isPast: true)
            reminderRow(date: "Jun 09", label: "Due day", isPast: true)
            reminderRow(date: "Today",  label: "Overdue follow-up", isPast: false)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }

    private func reminderRow(date: String, label: String, isPast: Bool) -> some View {
        HStack(spacing: 10) {
            Text(date)
                .font(.eyebrow).tracking(0.4)
                .foregroundStyle(isPast ? Color.faint : Color.ink)
                .frame(width: 60, alignment: .leading)
            Text(label)
                .font(.subline)
                .foregroundStyle(isPast ? Color.faded : Color.ink)
            Spacer()
            Circle()
                .fill(isPast ? Color.hairD : Color.bad)
                .frame(width: 6, height: 6)
        }
        .padding(.vertical, 7)
    }

    // MARK: footer

    private var footerActions: some View {
        HStack(spacing: 8) {
            Text("Mark done")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.paper)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.ink))
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
    }
}

// MARK: - Supporting types

struct ChecklistStep: Identifiable {
    let id = UUID()
    var text: String
    var done: Bool
}

// The settable workflow states (overdue is derived, not settable).
enum WorkStatus: CaseIterable {
    case todo, inProgress, deferred, done

    var label: String {
        switch self {
        case .todo:       return "Todo"
        case .inProgress: return "In progress"
        case .deferred:   return "Deferred"
        case .done:       return "Done"
        }
    }
}

#Preview {
    DetailView()
}
