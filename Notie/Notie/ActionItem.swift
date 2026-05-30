//  ActionItem.swift
//
//  The core data type — one task/bill/reminder in the app. For now it's
//  a plain Swift struct with sample data, so the UI can be data-driven
//  (tapping a row opens *that* item's detail, not a hardcoded one).
//
//  Week 2 turns this into a SwiftData @Model so items actually persist.
//  The field shape is designed to carry forward, so that change is mostly
//  adding @Model + storage, not reshaping the type.
//

import SwiftUI

struct ActionItem: Identifiable {
    let id = UUID()

    // Display
    var glyph: String        // SF Symbol name
    var color: Color         // avatar circle color
    var title: String
    var subtitle: String     // inbox subline, e.g. "$115.00 · 2 days overdue"

    // Detail fields (optional — not every item is a bill)
    var amountText: String?  // "$115.00"  (becomes Decimal in Week 2)
    var dueText: String?     // "Jun 9"
    var dueIsBad: Bool = false
    var isOverdue: Bool = false
    var statusNote: String?  // red banner, e.g. "⚠ 2 DAYS OVERDUE · $50 PENALTY"
    var initialStatus: WorkStatus = .todo

    var steps: [ChecklistStep] = []
    var reminders: [ReminderRow] = []
}

struct ChecklistStep: Identifiable {
    let id = UUID()
    var text: String
    var done: Bool = false
}

struct ReminderRow: Identifiable {
    let id = UUID()
    var date: String
    var label: String
    var isPast: Bool
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

// MARK: - Sample data
// TEMP (Week 2): these hardcoded samples stand in for real saved items.
// When SwiftData lands, the Inbox reads stored records and this whole
// block goes away.

extension ActionItem {
    static let parkingTicket = ActionItem(
        glyph: "parkingsign",
        color: Color(hex: 0xC0532F),
        title: "NYC parking ticket",
        subtitle: "$115.00 · 2 days overdue",
        amountText: "$115.00",
        dueText: "Jun 9",
        dueIsBad: true,
        isOverdue: true,
        statusNote: "⚠ 2 DAYS OVERDUE · $50 PENALTY IF NOT PAID",
        initialStatus: .inProgress,
        steps: [
            ChecklistStep(text: "Decide: pay or contest.", done: true),
            ChecklistStep(text: "Open NYC Pay Tickets.", done: true),
            ChecklistStep(text: "Enter violation #1234567890.", done: false),
            ChecklistStep(text: "Pay $115.00 before June 9.", done: false),
        ],
        reminders: [
            ReminderRow(date: "Jun 06", label: "3 days before", isPast: true),
            ReminderRow(date: "Jun 08", label: "1 day before", isPast: true),
            ReminderRow(date: "Jun 09", label: "Due day", isPast: true),
            ReminderRow(date: "Today",  label: "Overdue follow-up", isPast: false),
        ]
    )

    static let conEdison = ActionItem(
        glyph: "bolt.fill",
        color: Color.sourceScanned,
        title: "Con Edison · electricity",
        subtitle: "$86.42 · Sun Jun 15",
        amountText: "$86.42",
        dueText: "Jun 15",
        steps: [
            ChecklistStep(text: "Open Con Edison and sign in.", done: false),
            ChecklistStep(text: "Pay $86.42 before June 15.", done: false),
            ChecklistStep(text: "Save the confirmation number.", done: false),
        ],
        reminders: [
            ReminderRow(date: "Jun 12", label: "3 days before", isPast: false),
            ReminderRow(date: "Jun 14", label: "1 day before", isPast: false),
            ReminderRow(date: "Jun 15", label: "Due day", isPast: false),
        ]
    )

    static let insuranceCall = ActionItem(
        glyph: "phone.fill",
        color: Color.sourceCustom,
        title: "Call insurance — claim follow-up",
        subtitle: "Fri Jun 20",
        dueText: "Jun 20",
        steps: [
            ChecklistStep(text: "Find claim reference #CL-4421.", done: false),
            ChecklistStep(text: "Call 1-800-555-0140.", done: false),
            ChecklistStep(text: "Ask about the copay refund.", done: false),
        ],
        reminders: [
            ReminderRow(date: "Jun 19", label: "1 day before", isPast: false),
            ReminderRow(date: "Jun 20", label: "Due day", isPast: false),
        ]
    )

    static let moveOut = ActionItem(
        glyph: "checklist",
        color: Color.sourceCustom,
        title: "Apartment move-out inspection",
        subtitle: "Checklist · 4 of 6 done · Jun 28",
        dueText: "Jun 28",
        initialStatus: .inProgress,
        steps: [
            ChecklistStep(text: "Patch nail holes.", done: true),
            ChecklistStep(text: "Deep-clean kitchen.", done: true),
            ChecklistStep(text: "Shampoo carpets.", done: true),
            ChecklistStep(text: "Return all keys.", done: true),
            ChecklistStep(text: "Take dated photos of each room.", done: false),
            ChecklistStep(text: "Email landlord the forwarding address.", done: false),
        ],
        reminders: [
            ReminderRow(date: "Jun 25", label: "3 days before", isPast: false),
            ReminderRow(date: "Jun 28", label: "Due day", isPast: false),
        ]
    )

    static let sutterVisit = ActionItem(
        glyph: "cross.fill",
        color: Color.sourceGuide,
        title: "Sutter Health · clinic visit",
        subtitle: "$214.00 · Thu Jul 2",
        amountText: "$214.00",
        dueText: "Jul 2",
        steps: [
            ChecklistStep(text: "Review the itemized charges.", done: false),
            ChecklistStep(text: "Pay $214.00 or set up a plan.", done: false),
        ],
        reminders: [
            ReminderRow(date: "Jun 29", label: "3 days before", isPast: false),
            ReminderRow(date: "Jul 02", label: "Due day", isPast: false),
        ]
    )

    // Builds a checklist-style item from a tapped guide (Week 7 will use
    // each guide's real template steps; placeholder steps for now).
    static func fromGuide(_ guide: Guide) -> ActionItem {
        ActionItem(
            glyph: guide.symbol,
            color: guide.color,
            title: guide.title,
            subtitle: "Checklist · \(guide.stepCount) steps",
            steps: (1...min(guide.stepCount, 5)).map {
                ChecklistStep(text: "Step \($0)", done: false)
            }
        )
    }
}
