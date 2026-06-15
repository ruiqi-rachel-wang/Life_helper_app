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
    case utility, government, medical, finance, auto, housing, work, personal, other
}

// Where an item came from — drives the source tag (Scanned / guide / Custom).
nonisolated enum ItemSource: String, Codable {
    case scanned, guide, custom
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

// A link inside a step's detail (a website to open).
nonisolated struct StepLink: Codable, Hashable {
    var label: String
    var url: String
}

// One checkable sub-step inside a step's mini-checklist. Deliberately has NO
// `detail` of its own — this is the one-level-only rule, enforced by the type.
nonisolated struct SubStep: Codable, Hashable, Identifiable {
    var id = UUID()
    var text: String
    var done: Bool = false
}

// A piece of info the user fills in and keeps on a step — claim number, USCIS
// receipt number, appointment time, install date, etc. The label can be authored
// (an empty-value prompt) or added by the user; the value is theirs to fill.
nonisolated struct SavedField: Codable, Hashable, Identifiable {
    var id = UUID()
    var label: String
    var value: String = ""
}

// Optional structured help behind a milestone step — ONE level deep, no further
// nesting. Authored by guides; nil for plain scanned-document steps.
nonisolated struct StepDetail: Codable, Hashable {
    var explanation: String = ""
    var miniChecklist: [SubStep] = []  // flat, checkable sub-steps (one level)
    var links: [StepLink] = []
    var script: String = ""            // what to say on a call / visit
    var needed: [String] = []          // documents / info to have ready
    var fields: [SavedField] = []      // info to save (claim #, receipt #, time…)

    var isEmpty: Bool {
        explanation.isEmpty && miniChecklist.isEmpty && links.isEmpty
            && script.isEmpty && needed.isEmpty && fields.isEmpty
    }

    // Authoring convenience: pass the mini-checklist as plain strings; they become
    // checkable SubSteps.
    init(explanation: String = "", miniChecklist: [String] = [],
         links: [StepLink] = [], script: String = "", needed: [String] = [],
         fields: [SavedField] = []) {
        self.explanation = explanation
        self.miniChecklist = miniChecklist.map { SubStep(text: $0) }
        self.links = links
        self.script = script
        self.needed = needed
        self.fields = fields
    }

    // Tolerant decode: items saved before a field existed (e.g. `fields`) simply
    // default, so adding new detail keys never breaks already-stored steps.
    enum CodingKeys: String, CodingKey { case explanation, miniChecklist, links, script, needed, fields }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        explanation = try c.decodeIfPresent(String.self, forKey: .explanation) ?? ""
        miniChecklist = try c.decodeIfPresent([SubStep].self, forKey: .miniChecklist) ?? []
        links = try c.decodeIfPresent([StepLink].self, forKey: .links) ?? []
        script = try c.decodeIfPresent(String.self, forKey: .script) ?? ""
        needed = try c.decodeIfPresent([String].self, forKey: .needed) ?? []
        fields = try c.decodeIfPresent([SavedField].self, forKey: .fields) ?? []
    }
}

// A checklist step. Stored as part of the item (SwiftData persists the array of
// these Codable values). `detail` is optional structured help shown on tap.
nonisolated struct ChecklistStep: Identifiable, Codable, Hashable {
    var id = UUID()
    var text: String
    var done: Bool = false
    var detail: StepDetail? = nil

    var hasDetail: Bool { detail?.isEmpty == false }
}

// One scheduled reminder — derived, never stored. `exactTime` = fire at this
// precise time (a timed event, e.g. 3h before a flight); otherwise the scheduler
// fires at 9am on that day (a bill heads-up).
nonisolated struct ScheduledReminder: Identifiable {
    var id = UUID()
    var date: Date
    var label: String
    var exactTime: Bool = false
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

    // Rich detail from AI extraction (Week 6). All optional with defaults, so
    // adding them is a lightweight SwiftData migration and manual items just
    // leave them empty. `confidence`/`lowConfidenceFields` are intentionally NOT
    // stored — they only matter at Review time (the accent underlines).
    var summary: String = ""
    var documentType: String = ""
    var sender: String = ""
    var senderShort: String = ""
    var dueHasTime: Bool = false        // dueDate carries a real time (flight/appt)
    var siteURL: String = ""
    var otherIDs: [DocID] = []          // claim/policy/confirmation numbers
    var notes: [String] = []            // side info (not action steps)
    var source: ItemSource = ItemSource.custom
    // How many hours before a TIMED event (dueHasTime) to remind — seeds the
    // default schedule (flight ~3h, appointment ~1h). Ignored for plain dates.
    var reminderLeadHours: Int = 2
    // User-customized reminder fire-times. Empty + !customized = use the smart
    // defaults (defaultReminderDates). Once the user edits, `customized` flips on
    // and THIS list is authoritative (even if emptied = no reminders).
    var reminders: [Date] = []
    var remindersCustomized: Bool = false

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

    // Build an item from an AI extraction (Week 6). Folds the primary
    // accountNumber into otherIDs (deduped) so the Detail page shows every
    // identifier. repeats → repeatsMonthly for now (full Recurrence is Week 7).
    convenience init(from r: ExtractionResult,
                     imageData: Data? = nil,
                     source: ItemSource = .scanned) {
        var ids = r.otherIDs
        if let acct = r.accountNumber, !acct.isEmpty,
           !ids.contains(where: { $0.value == acct }) {
            ids.insert(DocID(label: "Reference", value: acct), at: 0)
        }
        let cleanTitle = r.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            title: (cleanTitle?.isEmpty == false ? cleanTitle! : (r.sender ?? r.documentType ?? "Untitled")),
            category: r.category ?? .other,
            amount: r.amount,
            currency: r.currency ?? "USD",
            dueDate: r.dueDate,
            imageData: imageData,
            steps: Self.mapSteps(r),
            repeatsMonthly: r.repeats == .monthly
        )
        self.summary = r.summary ?? ""
        self.documentType = r.documentType ?? ""
        self.sender = r.sender ?? ""
        self.senderShort = r.senderShort ?? ""
        self.dueHasTime = r.dueHasTime
        self.siteURL = r.siteURL?.absoluteString ?? ""
        self.otherIDs = ids
        self.notes = r.notes
        self.source = source
        self.reminderLeadHours = Self.defaultLeadHours(documentType: r.documentType ?? "", category: r.category)
    }

    // Choices for the "remind me _ before" picker (hours; 24 = one day).
    static let leadOptions = [1, 2, 3, 6, 12, 24]
    static func leadLabel(_ h: Int) -> String { h >= 24 ? "1 day" : "\(h) hour\(h == 1 ? "" : "s")" }

    // Map extraction steps → checklist steps. Guides supply `detailedSteps`
    // (with optional StepDetail); when their count matches the milestone strings
    // we sync the (possibly edited/polished) text but keep the authored detail.
    private static func mapSteps(_ r: ExtractionResult) -> [ChecklistStep] {
        if !r.detailedSteps.isEmpty {
            if r.detailedSteps.count == r.steps.count {
                return zip(r.steps, r.detailedSteps).map { ChecklistStep(text: $0, detail: $1.detail) }
            }
            return r.detailedSteps
        }
        return r.steps.map { ChecklistStep(text: $0) }
    }

    // Smart default for how many hours before a timed event to remind.
    static func defaultLeadHours(documentType: String, category: ItemCategory?) -> Int {
        let t = documentType.lowercased()
        if t.contains("flight") || t.contains("itinerary") || t.contains("boarding") { return 3 }
        if t.contains("appointment") || category == .medical { return 1 }
        return 2
    }

    // MARK: derived (no UI, no formatting — just facts)

    var isOverdue: Bool {
        guard status != .done, let due = dueDate else { return false }
        return due < Calendar.current.startOfDay(for: .now)
    }

    var doneCount: Int { steps.filter(\.done).count }

    // Timed events (dueHasTime): a heads-up the day before (9am) + a reminder
    // `reminderLeadHours` before the exact time. Plain dates: 3 days / 1 day /
    // due day (+ overdue follow-up).
    func reminderSchedule(now: Date = .now,
                          calendar: Calendar = .current) -> [ScheduledReminder] {
        guard let due = dueDate else { return [] }

        if dueHasTime {
            var timed: [ScheduledReminder] = []
            if let dayBefore = calendar.date(byAdding: .day, value: -1, to: due) {
                timed.append(ScheduledReminder(date: calendar.startOfDay(for: dayBefore), label: "Day before"))
            }
            if let hoursBefore = calendar.date(byAdding: .hour, value: -reminderLeadHours, to: due) {
                timed.append(ScheduledReminder(date: hoursBefore, label: "Hours before", exactTime: true))
            }
            return timed
        }

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

    // The default reminder fire-times (day reminders resolved to 9am; timed
    // reminders at their exact time). Used to seed the editable list.
    func defaultReminderDates(now: Date = .now, calendar: Calendar = .current) -> [Date] {
        reminderSchedule(now: now, calendar: calendar).compactMap {
            $0.exactTime ? $0.date : calendar.date(bySettingHour: 9, minute: 0, second: 0, of: $0.date)
        }
    }

    // What actually gets scheduled/shown: the user's custom list once edited,
    // otherwise the smart defaults.
    var effectiveReminders: [Date] {
        remindersCustomized ? reminders : defaultReminderDates()
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
