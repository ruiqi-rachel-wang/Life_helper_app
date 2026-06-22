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
// Ordered most-common → least-common for this app's audience. CaseIterable
// drives the "Create it yourself" category menu and the Guides chips, so the
// order shown to the user follows this list (rawValue strings are unchanged, so
// stored items keep decoding).
nonisolated enum ItemCategory: String, Codable, CaseIterable {
    case utility, finance, housing, medical, personal, government, auto, work, other

    // Localized name shown in the tag (follows the device language via the catalog).
    var displayName: String {
        switch self {
        case .utility:    return String(localized: "Utility")
        case .government: return String(localized: "Government")
        case .medical:    return String(localized: "Medical")
        case .finance:    return String(localized: "Finance")
        case .auto:       return String(localized: "Auto")
        case .housing:    return String(localized: "Housing")
        case .work:       return String(localized: "Work")
        case .personal:   return String(localized: "Personal")
        case .other:      return String(localized: "Other")
        }
    }
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

// A stored reminder: when to fire, plus an optional note shown in the
// notification banner. An empty note → the scheduler computes a friendly body
// ("Due in 3 days"); a non-empty note is shown verbatim ("Bring your passport").
nonisolated struct ReminderItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var date: Date
    var note: String = ""
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
    // nil = a one-off. A cadence read from the document or set by the user.
    // Marking a recurring item done spawns the next cycle; see makeNextOccurrence().
    var recurrence: Recurrence?
    // Shared across every occurrence of one recurring series, so we can keep the
    // series tidy (at most one active + one done). nil = singleton/legacy; use
    // `effectiveSeriesID`. Stamped the first time a cycle spawns.
    var seriesID: UUID?
    // The day-of-month the series should land on (e.g. 31). Captured from the
    // first occurrence's due date so month-based recurrence doesn't drift after a
    // short month (see Recurrence.nextDate). nil = no anchor (use the due day).
    var recurrenceAnchorDay: Int?
    // First-launch onboarding examples. They render normally but never schedule
    // reminders (so a tutorial item can't nag the user) and aren't real user data.
    var isExample: Bool = false
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
    // User-customized reminders (fire-time + optional banner note). Empty +
    // !customized = use the smart defaults (defaultReminders). Once the user
    // edits, `customized` flips on and THIS list is authoritative (even if
    // emptied = no reminders).
    var reminders: [ReminderItem] = []
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
         recurrence: Recurrence? = nil) {
        self.title = title
        self.category = category
        self.amount = amount
        self.currency = currency
        self.dueDate = dueDate
        self.note = note
        self.imageData = imageData
        self.status = status
        self.steps = steps
        self.recurrence = recurrence
    }

    // Build an item from an AI extraction (Week 6). Folds the primary
    // accountNumber into otherIDs (deduped) so the Detail page shows every
    // identifier. The AI-read cadence (`repeats`) carries straight onto the item.
    convenience init(from r: ExtractionResult,
                     imageData: Data? = nil,
                     source: ItemSource = .scanned) {
        var ids = r.otherIDs
        if let acct = r.accountNumber, !acct.isEmpty,
           !ids.contains(where: { $0.value == acct }) {
            let label = r.accountLabel?.trimmingCharacters(in: .whitespaces)
            ids.insert(DocID(label: (label?.isEmpty == false ? label! : "Reference"), value: acct), at: 0)
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
            recurrence: r.repeats
        )
        // Anchor month-based series to the original due day so they don't drift.
        if let due = r.dueDate, let rec = r.repeats, rec.isMonthBased {
            self.recurrenceAnchorDay = Calendar.current.component(.day, from: due)
        }
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
        // Timed events are overdue once the exact time passes (even later the same
        // day); plain due-dates compare day-to-day (overdue the day AFTER).
        let cal = Calendar.current
        return dueHasTime ? due < .now : due < cal.startOfDay(for: .now)
    }

    var doneCount: Int { steps.filter(\.done).count }

    // For metrics: completing now, was it on or before the due date? nil when
    // there's no due date (nothing to be on-time about). Timed events compare to
    // the exact time; plain dates compare day-to-day (done on the due day = OK).
    func doneOnTime(now: Date = .now, calendar: Calendar = .current) -> Bool? {
        guard let due = dueDate else { return nil }
        return dueHasTime ? now <= due
                          : calendar.startOfDay(for: now) <= calendar.startOfDay(for: due)
    }

    var isRecurring: Bool { recurrence != nil }

    // Every occurrence of one series shares this. Falls back to the item's own id
    // for singletons / pre-seriesID items.
    var effectiveSeriesID: UUID { seriesID ?? id }

    // Keep a recurring series tidy: at most ONE active (the soonest-due) and ONE
    // done (the latest-due). Returns the *other* items in the series to delete.
    // Pure → unit-tested. Called after a spawn (mark-done / skip).
    static func redundantInSeries(_ items: [ActionItem]) -> [ActionItem] {
        let far = Date.distantFuture
        var keep = Set<UUID>()
        // Active: keep the soonest due (nearest future); undated sort last.
        if let active = items.filter({ $0.status != .done })
            .min(by: { ($0.dueDate ?? far) < ($1.dueDate ?? far) }) {
            keep.insert(active.id)
        }
        // Done: keep the newest due date.
        if let done = items.filter({ $0.status == .done })
            .max(by: { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }) {
            keep.insert(done.id)
        }
        return items.filter { !keep.contains($0.id) }
    }

    // The next cycle of a recurring item — a fresh copy with the due date
    // advanced by the cadence, all steps unchecked, and reminders reset to
    // defaults (the old custom times were tied to the old due date). Returns
    // nil for one-off items or when there's no due date to advance from.
    // Spawned when a recurring item is marked done (or skipped on delete).
    //
    // Carries over only the STABLE facts (what the task is + how to do it): title,
    // category, steps, sender, document type, site, saved IDs, cadence. It does
    // NOT carry the period-specific facts — `amount`, `summary`, and `notes` — so
    // next month's bill doesn't inherit "$42 · June electricity bill · pay by June
    // 30". Those are filled in fresh when the user scans the new statement.
    func makeNextOccurrence(calendar: Calendar = .current) -> ActionItem? {
        guard let recurrence, let due = dueDate,
              let nextDue = recurrence.nextDate(
                after: due, anchorDay: recurrenceAnchorDay, calendar: calendar) else { return nil }

        let freshSteps = steps.map { step -> ChecklistStep in
            var detail = step.detail
            if let mini = detail?.miniChecklist {
                detail?.miniChecklist = mini.map { SubStep(text: $0.text) }
            }
            return ChecklistStep(text: step.text, done: false, detail: detail)
        }
        let next = ActionItem(title: title, category: category,
                              currency: currency, dueDate: nextDue, note: note,
                              status: .todo, steps: freshSteps, recurrence: recurrence)
        // Stable identity/how-to facts carry over; period-specific ones do not.
        next.documentType = documentType
        next.sender = sender
        next.senderShort = senderShort
        next.dueHasTime = dueHasTime
        next.siteURL = siteURL
        next.otherIDs = otherIDs
        next.source = source
        next.reminderLeadHours = reminderLeadHours
        next.recurrenceAnchorDay = recurrenceAnchorDay
        next.seriesID = effectiveSeriesID   // child joins this series
        return next
    }

    // Timed events (dueHasTime): a heads-up the day before (9am) + a reminder
    // `reminderLeadHours` before the exact time. Plain dates: 3 days / 1 day /
    // due day. Daily overdue nudges are scheduled separately by the platform
    // scheduler and are intentionally absent from this editable list.
    func reminderSchedule(now: Date = .now,
                          calendar: Calendar = .current) -> [ScheduledReminder] {
        Self.reminderSchedule(dueDate: dueDate, dueHasTime: dueHasTime,
                              leadHours: reminderLeadHours, now: now, calendar: calendar)
    }

    // Static so the pre-save Review draft can compute the SAME smart defaults
    // without an ActionItem instance — both edit screens share this.
    static func reminderSchedule(dueDate: Date?, dueHasTime: Bool, leadHours: Int,
                                 now: Date = .now,
                                 calendar: Calendar = .current) -> [ScheduledReminder] {
        guard let due = dueDate else { return [] }

        if dueHasTime {
            var timed: [ScheduledReminder] = []
            if let dayBefore = calendar.date(byAdding: .day, value: -1, to: due) {
                timed.append(ScheduledReminder(date: calendar.startOfDay(for: dayBefore), label: "Day before"))
            }
            if let hoursBefore = calendar.date(byAdding: .hour, value: -leadHours, to: due) {
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
        return out
    }

    // The default reminders (day reminders resolved to 9am; timed reminders at
    // their exact time). Notes are left empty so the scheduler computes a
    // friendly body. Used to seed the editable list.
    func defaultReminders(now: Date = .now, calendar: Calendar = .current) -> [ReminderItem] {
        Self.defaultReminders(dueDate: dueDate, dueHasTime: dueHasTime,
                              leadHours: reminderLeadHours, now: now, calendar: calendar)
    }

    static func defaultReminders(dueDate: Date?, dueHasTime: Bool, leadHours: Int,
                                 now: Date = .now,
                                 calendar: Calendar = .current) -> [ReminderItem] {
        reminderSchedule(dueDate: dueDate, dueHasTime: dueHasTime, leadHours: leadHours,
                         now: now, calendar: calendar).compactMap { r in
            let fire = r.exactTime ? r.date : calendar.date(bySettingHour: 9, minute: 0, second: 0, of: r.date)
            return fire.map { ReminderItem(date: $0) }
        }
    }

    // What actually gets scheduled/shown: the user's custom list once edited,
    // otherwise the smart defaults.
    var effectiveReminders: [ReminderItem] {
        remindersCustomized ? reminders : defaultReminders()
    }
}

// MARK: - Onboarding examples
// Seeded once on first launch so a fresh install isn't empty and confusing.
// Three items that double as a tutorial — one in each state (needs attention /
// in progress / done) — and whose steps explain how the app works. Flagged
// `isExample` so they never schedule reminders. `samples` returns NEW instances
// each call (don't share @Model objects across contexts). Strings use
// String(localized:) so the tutorial appears in the device language.

extension ActionItem {
    private static func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset,
                              to: Calendar.current.startOfDay(for: .now)) ?? .now
    }
    private static func usd(_ s: String) -> Decimal { Decimal(string: s) ?? .zero }

    static var samples: [ActionItem] {
        let welcome = ActionItem(
            title: String(localized: "👋 Welcome to Cuevi"),
            category: .personal, dueDate: day(-1),
            steps: [
                ChecklistStep(text: String(localized: "Cuevi turns a confusing bill or letter into simple steps like these.")),
                ChecklistStep(text: String(localized: "Tap ＋ Add to scan a document — Cuevi explains it and what to do.")),
                ChecklistStep(text: String(localized: "Tap the box to check off a step as you finish it.")),
            ])
        let bill = ActionItem(
            title: String(localized: "Example: an electric bill"),
            category: .utility, amount: usd("42.00"), dueDate: day(18), status: .inProgress,
            steps: [
                ChecklistStep(text: String(localized: "Scanned bills show the amount and due date up top."), done: true),
                ChecklistStep(text: String(localized: "Cuevi reminds you before it's due so you don't forget.")),
                ChecklistStep(text: String(localized: "When you've paid, tap Mark done.")),
            ])
        let finished = ActionItem(
            title: String(localized: "Example: a finished task"),
            category: .personal, status: .done,
            steps: [
                ChecklistStep(text: String(localized: "Finished tasks move down here to Done."), done: true),
                ChecklistStep(text: String(localized: "Open one to reopen it or delete it."), done: true),
            ])
        let items = [welcome, bill, finished]
        items.forEach { $0.isExample = true }
        return items
    }
}
