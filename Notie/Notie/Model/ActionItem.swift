//  ActionItem.swift
//
//  The core domain type — one task/bill/reminder — now a SwiftData @Model
//  so items actually persist to disk. Still UI-free: no colors, no
//  screen-local types (the view layer maps category → color/symbol in
//  Theme/ItemStyle.swift).
//
//  @Model makes this a reference type (class), not a struct. That's what
//  lets the Inbox (@Query) and Detail (@Bindable) share one live object:
//  edit it on Detail and the Inbox updates, because they're the same
//  instance backed by the store.
//

import Foundation
import SwiftData

// Semantic category. Drives the icon/color in the view, not vice-versa.
nonisolated enum ItemCategory: String, Codable, CaseIterable {
    case utility, government, medical, finance, housing, work, personal, other
}

// Workflow state. Not user-set: inProgress is derived (some steps checked),
// done comes from "Mark done", overdue is derived (see isOverdue).
enum WorkStatus: String, Codable {
    case todo, inProgress, done

    var label: String {
        switch self {
        case .todo:       return "Todo"
        case .inProgress: return "In progress"
        case .done:       return "Done"
        }
    }
}

// A checklist step. Stored as part of the item (SwiftData persists the
// array of these Codable values).
struct ChecklistStep: Identifiable, Codable, Hashable {
    var id = UUID()
    var text: String
    var done: Bool = false
}

// One scheduled reminder — derived, never stored.
struct ScheduledReminder: Identifiable {
    var id = UUID()
    var date: Date
    var label: String
}

@Model
final class ActionItem {
    var id: UUID = UUID()
    var title: String = ""
    var category: ItemCategory = ItemCategory.other
    var amount: Decimal?
    var currency: String = "USD"
    var dueDate: Date?
    var note: String = ""
    // Photo stored as an external file (not inline in the SQLite store) so big
    // images don't bloat the database. SwiftData manages the file for us.
    @Attribute(.externalStorage) var imageData: Data?
    var status: WorkStatus = WorkStatus.todo
    var steps: [ChecklistStep] = []
    var repeatsMonthly: Bool = false
    var createdAt: Date = Date.now

    init(title: String,
         category: ItemCategory,
         amount: Decimal? = nil,
         currency: String = "USD",
         dueDate: Date? = nil,
         note: String = "",
         imageData: Data? = nil,
         status: WorkStatus = .todo,
         steps: [ChecklistStep] = [],
         repeatsMonthly: Bool = false) {
        self.title = title
        self.category = category
        self.amount = amount
        self.currency = currency
        self.dueDate = dueDate
        self.note = note
        self.imageData = imageData
        self.status = status
        self.steps = steps
        self.repeatsMonthly = repeatsMonthly
    }

    // MARK: derived (no UI, no formatting — just facts)

    var isOverdue: Bool {
        guard status != .done, let due = dueDate else { return false }
        return due < Calendar.current.startOfDay(for: .now)
    }

    var doneCount: Int { steps.filter(\.done).count }

    // 3 days before, 1 day before, due day, + overdue follow-up if overdue.
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

        // Overdue follow-up — computed against the passed `now` (not .now), and
        // placed on the next 9am that's still in the future, so it isn't
        // silently skipped when an overdue item is created/rescheduled after 9am.
        let overdue = (status != .done)
            && ((dueDate.map { $0 < calendar.startOfDay(for: now) }) ?? false)
        if overdue {
            let nineToday = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
            let followUpDay = now < nineToday
                ? calendar.startOfDay(for: now)                                       // today (9am still ahead)
                : (calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now)  // tomorrow
            out.append(ScheduledReminder(date: followUpDay, label: "Overdue follow-up"))
        }
        return out
    }
}

// MARK: - Sample data
// TEMP (Week 2): seeded into the store once on first launch so a fresh
// install isn't empty during testing. A real app would start empty +
// onboard. `samples` returns NEW instances each call (don't share @Model
// objects across contexts).

extension ActionItem {
    private static func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset,
                              to: Calendar.current.startOfDay(for: .now)) ?? .now
    }
    private static func usd(_ s: String) -> Decimal { Decimal(string: s) ?? .zero }

    static var samples: [ActionItem] {
        [
            ActionItem(title: "NYC parking ticket", category: .government,
                       amount: usd("115.00"), dueDate: day(-2), status: .inProgress,
                       steps: [
                        ChecklistStep(text: "Decide: pay or contest.", done: true),
                        ChecklistStep(text: "Open NYC Pay Tickets.", done: true),
                        ChecklistStep(text: "Enter violation #1234567890."),
                        ChecklistStep(text: "Pay the balance before the due date."),
                       ]),
            ActionItem(title: "Con Edison · electricity", category: .utility,
                       amount: usd("86.42"), dueDate: day(16),
                       steps: [
                        ChecklistStep(text: "Open Con Edison and sign in."),
                        ChecklistStep(text: "Pay the balance before the due date."),
                        ChecklistStep(text: "Save the confirmation number."),
                       ],
                       repeatsMonthly: true),
            ActionItem(title: "Call insurance — claim follow-up", category: .personal,
                       dueDate: day(21),
                       steps: [
                        ChecklistStep(text: "Find claim reference #CL-4421."),
                        ChecklistStep(text: "Call 1-800-555-0140."),
                        ChecklistStep(text: "Ask about the copay refund."),
                       ]),
            ActionItem(title: "Apartment move-out inspection", category: .housing,
                       dueDate: day(29), status: .inProgress,
                       steps: [
                        ChecklistStep(text: "Patch nail holes.", done: true),
                        ChecklistStep(text: "Deep-clean kitchen.", done: true),
                        ChecklistStep(text: "Shampoo carpets.", done: true),
                        ChecklistStep(text: "Return all keys.", done: true),
                        ChecklistStep(text: "Take dated photos of each room."),
                        ChecklistStep(text: "Email landlord the forwarding address."),
                       ]),
            ActionItem(title: "Sutter Health · clinic visit", category: .medical,
                       amount: usd("214.00"), dueDate: day(33),
                       steps: [
                        ChecklistStep(text: "Review the itemized charges."),
                        ChecklistStep(text: "Pay the balance or set up a plan."),
                       ]),
        ]
    }
}
