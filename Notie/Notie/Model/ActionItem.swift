//  ActionItem.swift
//
//  The core domain type — one task/bill/reminder. Pure data: no SwiftUI,
//  no colors, no screen-local types. The view layer maps `category` to a
//  color + SF Symbol (see Theme/ItemStyle.swift) and formats amounts/dates.
//
//  Keeping this Foundation-only is what makes Week 2 (SwiftData) and a
//  future Android port clean: persistence stores semantic values, and the
//  same logic ports to Kotlin unchanged.
//
//  Week 2 adds @Model + storage; the field shape is designed to carry over.
//

import Foundation

// Semantic category of an item. Drives the icon/color in the view, NOT
// the other way around. (The AI's extraction will set this.)
enum ItemCategory: String, Codable, CaseIterable {
    case utility, government, medical, finance, housing, work, personal, other
}

// Settable workflow states. `overdue` is derived (see isOverdue), not stored.
enum WorkStatus: String, Codable, CaseIterable {
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

struct ChecklistStep: Identifiable, Codable {
    var id = UUID()
    var text: String
    var done: Bool = false
}

// One scheduled reminder. Dates are domain data; whether it's "past" is
// derived in the view against the current time.
struct ScheduledReminder: Identifiable {
    var id = UUID()
    var date: Date
    var label: String
}

struct ActionItem: Identifiable {
    var id = UUID()

    var title: String
    var category: ItemCategory
    var amount: Decimal?        // nil = not a bill
    var currency: String = "USD"
    var dueDate: Date?
    var note: String = ""
    var status: WorkStatus = .todo
    var steps: [ChecklistStep] = []
    var repeatsMonthly: Bool = false

    // MARK: derived (no UI, no formatting — just facts)

    // Overdue = due before today and not finished. Not a settable state.
    var isOverdue: Bool {
        guard status != .done, let due = dueDate else { return false }
        return due < Calendar.current.startOfDay(for: .now)
    }

    var doneCount: Int { steps.filter(\.done).count }

    // The reminder schedule for this item: 3 days before, 1 day before,
    // due day, plus an overdue follow-up (today) if it's overdue. Pure
    // date math so it's unit-testable without any UI.
    func reminderSchedule(now: Date = .now,
                          calendar: Calendar = .current) -> [ScheduledReminder] {
        guard let due = dueDate else { return [] }
        var out: [ScheduledReminder] = []
        if let d = calendar.date(byAdding: .day, value: -3, to: due) {
            out.append(ScheduledReminder(date: d, label: "3 days before"))
        }
        if let d = calendar.date(byAdding: .day, value: -1, to: due) {
            out.append(ScheduledReminder(date: d, label: "1 day before"))
        }
        out.append(ScheduledReminder(date: due, label: "Due day"))
        if isOverdue {
            out.append(ScheduledReminder(date: calendar.startOfDay(for: now),
                                         label: "Overdue follow-up"))
        }
        return out
    }
}

// MARK: - Sample data
// TEMP (Week 2): these hardcoded samples stand in for real saved items.
// Dates are relative to today so the derived states (overdue, due-soon)
// stay correct no matter when the app is run. Replaced by SwiftData.

extension ActionItem {
    private static func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset,
                              to: Calendar.current.startOfDay(for: .now)) ?? .now
    }
    private static func usd(_ s: String) -> Decimal { Decimal(string: s) ?? .zero }

    static let parkingTicket = ActionItem(
        title: "NYC parking ticket",
        category: .government,
        amount: usd("115.00"),
        dueDate: day(-2),                 // overdue
        status: .inProgress,
        steps: [
            ChecklistStep(text: "Decide: pay or contest.", done: true),
            ChecklistStep(text: "Open NYC Pay Tickets.", done: true),
            ChecklistStep(text: "Enter violation #1234567890."),
            ChecklistStep(text: "Pay the balance before the due date."),
        ]
    )

    static let conEdison = ActionItem(
        title: "Con Edison · electricity",
        category: .utility,
        amount: usd("86.42"),
        dueDate: day(16),
        steps: [
            ChecklistStep(text: "Open Con Edison and sign in."),
            ChecklistStep(text: "Pay the balance before the due date."),
            ChecklistStep(text: "Save the confirmation number."),
        ],
        repeatsMonthly: true
    )

    static let insuranceCall = ActionItem(
        title: "Call insurance — claim follow-up",
        category: .personal,
        dueDate: day(21),
        steps: [
            ChecklistStep(text: "Find claim reference #CL-4421."),
            ChecklistStep(text: "Call 1-800-555-0140."),
            ChecklistStep(text: "Ask about the copay refund."),
        ]
    )

    static let moveOut = ActionItem(
        title: "Apartment move-out inspection",
        category: .housing,
        dueDate: day(29),
        status: .inProgress,
        steps: [
            ChecklistStep(text: "Patch nail holes.", done: true),
            ChecklistStep(text: "Deep-clean kitchen.", done: true),
            ChecklistStep(text: "Shampoo carpets.", done: true),
            ChecklistStep(text: "Return all keys.", done: true),
            ChecklistStep(text: "Take dated photos of each room."),
            ChecklistStep(text: "Email landlord the forwarding address."),
        ]
    )

    static let sutterVisit = ActionItem(
        title: "Sutter Health · clinic visit",
        category: .medical,
        amount: usd("214.00"),
        dueDate: day(33),
        steps: [
            ChecklistStep(text: "Review the itemized charges."),
            ChecklistStep(text: "Pay the balance or set up a plan."),
        ]
    )
}
