//  CueviTests.swift
//
//  Unit tests for ActionItem — domain logic (isOverdue, doneCount,
//  reminderSchedule) plus a real SwiftData round-trip on an in-memory
//  store (insert → save → fetch → delete). Run with Cmd+U.
//

import Testing
import Foundation
import SwiftData
@testable import Cuevi

struct ActionItemTests {

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset,
                              to: Calendar.current.startOfDay(for: .now))!
    }

    // MARK: isOverdue

    @Test func dueInPastIsOverdue() {
        #expect(ActionItem(title: "x", category: .other, dueDate: day(-2)).isOverdue)
    }

    @Test func dueInFutureIsNotOverdue() {
        #expect(!ActionItem(title: "x", category: .other, dueDate: day(5)).isOverdue)
    }

    @Test func doneItemIsNeverOverdue() {
        #expect(!ActionItem(title: "x", category: .other,
                            dueDate: day(-10), status: .done).isOverdue)
    }

    @Test func noDueDateIsNotOverdue() {
        #expect(!ActionItem(title: "x", category: .other).isOverdue)
    }

    // MARK: doneCount

    @Test func doneCountCountsCheckedSteps() {
        let item = ActionItem(title: "x", category: .other, steps: [
            ChecklistStep(text: "a", done: true),
            ChecklistStep(text: "b", done: false),
            ChecklistStep(text: "c", done: true),
        ])
        #expect(item.doneCount == 2)
    }

    // MARK: reminderSchedule

    @Test func noDueDateHasNoReminders() {
        #expect(ActionItem(title: "x", category: .other).reminderSchedule().isEmpty)
    }

    @Test func futureItemHasThreeReminders() {
        let schedule = ActionItem(title: "x", category: .other, dueDate: day(10)).reminderSchedule()
        #expect(schedule.count == 3)
        #expect(schedule.map(\.label) == ["3 days before", "1 day before", "Due day"])
    }

    @Test func overdueNudgeIsNotPartOfEditableSchedule() {
        let item = ActionItem(title: "x", category: .other, dueDate: day(-2))
        #expect(item.isOverdue)
        #expect(!item.reminderSchedule().contains { $0.label == "Overdue follow-up" })
    }

    @Test func reminderDatesAreOffsetFromDueDate() {
        let due = day(10)
        let schedule = ActionItem(title: "x", category: .other, dueDate: due).reminderSchedule()
        let cal = Calendar.current
        #expect(schedule[0].date == cal.date(byAdding: .day, value: -3, to: due))
        #expect(schedule[1].date == cal.date(byAdding: .day, value: -1, to: due))
        #expect(schedule[2].date == due)
    }

    // MARK: Inbox urgency bucketing

    @Test func groupsItemsIntoCorrectBuckets() {
        let items = [
            ActionItem(title: "overdue", category: .other, dueDate: day(-1)),
            ActionItem(title: "due soon", category: .other, dueDate: day(3)),
            ActionItem(title: "far off", category: .other, dueDate: day(30)),
            ActionItem(title: "completed", category: .other, status: .done),
            ActionItem(title: "started", category: .other,
                       steps: [ChecklistStep(text: "a", done: true)]),
        ]
        let b = items.groupedForInbox()

        #expect(b.needsAttention.map(\.title) == ["overdue"])
        #expect(b.dueThisWeek.map(\.title) == ["due soon"])
        #expect(b.upcoming.map(\.title) == ["far off"])
        #expect(b.done.map(\.title) == ["completed"])
        #expect(b.inProgress.map(\.title) == ["started"])
        #expect(b.activeCount == 4)   // everything except the done one
    }

    @Test func dueTodayIsOverdueNotDueThisWeek() {
        // A task due today needs to get done today, not "any time this week" —
        // it lands in Needs attention (and gets the daily overdue nudge) the
        // same day it's due, not the day after.
        let b = [ActionItem(title: "today", category: .other, dueDate: day(0))].groupedForInbox()
        #expect(b.needsAttention.count == 1)
        #expect(b.dueThisWeek.isEmpty)
    }

    @Test func noDueDateGoesToUpcomingNotInProgress() {
        // An undated, not-started task waits in Upcoming — it only becomes
        // In progress once a step is checked.
        let b = [ActionItem(title: "no date", category: .other)].groupedForInbox()
        #expect(b.upcoming.count == 1)
        #expect(b.inProgress.isEmpty)
    }

    @Test func undatedItemWithCheckedStepIsInProgress() {
        let b = [ActionItem(title: "started, no date", category: .other,
                            steps: [ChecklistStep(text: "a", done: true)])].groupedForInbox()
        #expect(b.inProgress.count == 1)
        #expect(b.upcoming.isEmpty)
    }

    @Test func doneItemNeverCountsAsActive() {
        // Overdue date but already done → lands in Done, not Needs attention.
        let b = [ActionItem(title: "x", category: .other,
                            dueDate: day(-5), status: .done)].groupedForInbox()
        #expect(b.done.count == 1)
        #expect(b.activeCount == 0)
    }

    @Test func reopeningMovesADoneItemBackToActive() {
        // What reopen() does: flip status off .done. A part-checked item then
        // re-buckets as in-progress and counts as active again.
        let item = ActionItem(title: "x", category: .other,
                              status: .done,
                              steps: [ChecklistStep(text: "a", done: true),
                                      ChecklistStep(text: "b")])
        #expect([item].groupedForInbox().done.count == 1)
        item.status = .todo
        let b = [item].groupedForInbox()
        #expect(b.done.isEmpty)
        #expect(b.inProgress.count == 1)   // some steps checked → in progress
        #expect(b.activeCount == 1)
    }

    // MARK: SwiftData persistence (in-memory store)

    @MainActor
    @Test func savesLoadsAndDeletes() throws {
        let container = try ModelContainer(
            for: ActionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext

        let item = ActionItem(title: "Rent", category: .housing,
                              amount: Decimal(string: "1200"), dueDate: day(5),
                              steps: [ChecklistStep(text: "Pay landlord")])
        context.insert(item)
        try context.save()

        var fetched = try context.fetch(FetchDescriptor<ActionItem>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Rent")
        #expect(fetched.first?.steps.count == 1)          // array of structs persisted
        #expect(fetched.first?.amount == Decimal(string: "1200"))

        context.delete(item)
        try context.save()
        fetched = try context.fetch(FetchDescriptor<ActionItem>())
        #expect(fetched.isEmpty)
    }

    @Test func sectionsAreSortedByDueDateSoonestFirst() {
        let items = [
            ActionItem(title: "later", category: .other, dueDate: day(5)),
            ActionItem(title: "sooner", category: .other, dueDate: day(1)),
            ActionItem(title: "middle", category: .other, dueDate: day(3)),
        ]
        #expect(items.groupedForInbox().dueThisWeek.map(\.title) == ["sooner", "middle", "later"])
    }

    // MARK: timed-event reminders (Week 6, Step 3)

    @Test func timedItemRemindsDayBeforeAndHoursBefore() {
        let due = DateComponents(calendar: .current, year: 2026, month: 6, day: 25,
                                 hour: 8, minute: 5).date!
        let item = ActionItem(title: "Flight", category: .personal, dueDate: due)
        item.dueHasTime = true
        item.reminderLeadHours = 3
        let s = item.reminderSchedule()
        #expect(s.map(\.label) == ["Day before", "Hours before"])
        #expect(s[1].exactTime)
        let c = Calendar.current.dateComponents([.day, .hour, .minute], from: s[1].date)
        #expect(c.day == 25 && c.hour == 5 && c.minute == 5)   // 3h before 8:05 AM
    }

    @Test func plainDateItemKeepsDayBasedReminders() {
        // dueHasTime defaults false → the original 3d/1d/due-day schedule.
        let item = ActionItem(title: "Bill", category: .utility, dueDate: day(10))
        #expect(item.reminderSchedule().map(\.label) == ["3 days before", "1 day before", "Due day"])
    }

    @Test func effectiveRemindersUseDefaultsThenCustom() {
        let item = ActionItem(title: "Bill", category: .utility, dueDate: day(10))
        #expect(item.effectiveReminders.count == 3)        // smart defaults (9am)
        #expect(item.effectiveReminders.allSatisfy { $0.note.isEmpty })  // defaults carry no note
        let custom = day(7)
        item.reminders = [ReminderItem(date: custom, note: "Bring passport")]
        item.remindersCustomized = true
        #expect(item.effectiveReminders.map(\.date) == [custom])         // custom wins
        #expect(item.effectiveReminders.first?.note == "Bring passport")
    }

    @Test func customizedEmptyMeansNoReminders() {
        let item = ActionItem(title: "Bill", category: .utility, dueDate: day(10))
        item.remindersCustomized = true                     // emptied on purpose
        #expect(item.effectiveReminders.isEmpty)
    }

    @Test func reviewDraftRemindersSurviveSave() {
        // Reminders set on the Review screen must persist onto the saved item.
        var draft = ExtractionResult(title: "Bill", dueDate: day(10), confidence: 1)
        let custom = day(5)
        draft.reminders = [ReminderItem(date: custom, note: "Pay early")]
        draft.remindersCustomized = true
        let item = ActionItem(from: draft)
        #expect(item.remindersCustomized)
        #expect(item.effectiveReminders.map(\.date) == [custom])
        #expect(item.effectiveReminders.first?.note == "Pay early")
    }

    @Test func nearDueDateDropsPastDefaultReminders() {
        // A due date tomorrow shouldn't seed "3 days before"/"1 day before" (both
        // already past) — only times still ahead are offered.
        let defaults = ActionItem.defaultReminders(dueDate: day(1), dueHasTime: false, leadHours: 2)
        #expect(defaults.allSatisfy { $0.date > .now })
    }

    @MainActor
    @Test func stepDetailSurvivesSwiftDataRoundTrip() throws {
        let container = try ModelContainer(
            for: ActionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext

        let detail = StepDetail(explanation: "do this", miniChecklist: ["a", "b"],
                                links: [StepLink(label: "L", url: "https://example.com")])
        context.insert(ActionItem(title: "Guide", category: .government,
                                  steps: [ChecklistStep(text: "Step", detail: detail)]))
        try context.save()

        let d = try context.fetch(FetchDescriptor<ActionItem>()).first?.steps.first?.detail
        #expect(d?.miniChecklist.count == 2)
        #expect(d?.miniChecklist.first?.text == "a")
        #expect(d?.miniChecklist.first?.done == false)
        #expect(d?.links.first?.url == "https://example.com")
    }

    @Test func stepDetailDecodesWhenFieldsKeyMissing() throws {
        // A step saved before `fields` existed must still decode (defaults to []).
        let json = #"{"explanation":"x","miniChecklist":[],"links":[],"script":"","needed":[]}"#.data(using: .utf8)!
        let d = try JSONDecoder().decode(StepDetail.self, from: json)
        #expect(d.fields.isEmpty)
        #expect(d.explanation == "x")
    }

    @MainActor
    @Test func savedFieldsSurviveSwiftDataRoundTrip() throws {
        let container = try ModelContainer(
            for: ActionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext

        let detail = StepDetail(explanation: "e",
                                fields: [SavedField(label: "Claim number", value: "ABC123")])
        context.insert(ActionItem(title: "Guide", category: .finance,
                                  steps: [ChecklistStep(text: "Step", detail: detail)]))
        try context.save()

        let f = try context.fetch(FetchDescriptor<ActionItem>()).first?.steps.first?.detail?.fields
        #expect(f?.first?.label == "Claim number")
        #expect(f?.first?.value == "ABC123")
    }

    @MainActor
    @Test func recurrenceSurvivesSwiftDataRoundTrip() throws {
        // Recurrence is a Codable enum with an associated value — make sure
        // SwiftData actually persists and restores it.
        let container = try ModelContainer(
            for: ActionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext

        context.insert(ActionItem(title: "Rent", category: .housing,
                                  dueDate: day(3), recurrence: .everyNDays(14)))
        try context.save()

        let loaded = try context.fetch(FetchDescriptor<ActionItem>()).first
        #expect(loaded?.recurrence == .everyNDays(14))
        #expect(loaded?.isRecurring == true)
    }

    @MainActor
    @Test func reminderNoteSurvivesSwiftDataRoundTrip() throws {
        let container = try ModelContainer(
            for: ActionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext

        let item = ActionItem(title: "Flight", category: .personal, dueDate: day(3))
        item.reminders = [ReminderItem(date: day(2), note: "Bring passport")]
        item.remindersCustomized = true
        context.insert(item)
        try context.save()

        let r = try context.fetch(FetchDescriptor<ActionItem>()).first?.reminders.first
        #expect(r?.note == "Bring passport")
    }

    // MARK: ExtractionResult → ActionItem mapping (Week 6)

    @Test func buildsActionItemFromExtraction() {
        let r = ExtractionResult(
            title: "Con Edison electricity bill",
            documentType: "Utility bill",
            sender: "Con Edison",
            amount: Decimal(string: "86.42"),
            currency: "USD",
            dueDate: day(10),
            accountNumber: "12-3456",
            otherIDs: [DocID(label: "Policy", value: "AS2")],
            category: .utility,
            summary: "Your monthly electricity bill.",
            steps: ["Pay it", "Save the receipt"],
            notes: ["Autopay is off."],
            repeats: .monthly)
        let item = ActionItem(from: r)

        #expect(item.title == "Con Edison electricity bill")
        #expect(item.category == .utility)
        #expect(item.amount == Decimal(string: "86.42"))
        #expect(item.summary == "Your monthly electricity bill.")
        #expect(item.steps.map(\.text) == ["Pay it", "Save the receipt"])
        #expect(item.notes == ["Autopay is off."])
        #expect(item.recurrence == .monthly)
        #expect(item.source == .scanned)
        // primary accountNumber folded into otherIDs (deduped), first
        #expect(item.otherIDs.first == DocID(label: "Reference", value: "12-3456"))
        #expect(item.otherIDs.contains(DocID(label: "Policy", value: "AS2")))
    }

    @Test func extractionTitleFallsBackToSender() {
        #expect(ActionItem(from: ExtractionResult(sender: "GEICO")).title == "GEICO")
    }

    // MARK: recurrence (Week 8)

    @Test func recurrenceNextDateAdvancesByCadence() {
        let cal = Calendar.current
        let base = cal.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        #expect(Recurrence.monthly.nextDate(after: base) ==
                cal.date(from: DateComponents(year: 2026, month: 2, day: 15)))
        #expect(Recurrence.yearly.nextDate(after: base) ==
                cal.date(from: DateComponents(year: 2027, month: 1, day: 15)))
        #expect(Recurrence.everyNDays(10).nextDate(after: base) ==
                cal.date(from: DateComponents(year: 2026, month: 1, day: 25)))
        // The added presets (weekly / biweekly / quarterly).
        #expect(Recurrence.weekly.nextDate(after: base) ==
                cal.date(byAdding: .day, value: 7, to: base))
        #expect(Recurrence.biweekly.nextDate(after: base) ==
                cal.date(byAdding: .day, value: 14, to: base))
        #expect(Recurrence.quarterly.nextDate(after: base) ==
                cal.date(from: DateComponents(year: 2026, month: 4, day: 15)))
    }

    @Test func recurrenceFollowsTheDocumentNotTheCategory() {
        // A utility scan no longer gets force-defaulted to monthly — a one-off
        // utility doc (final bill, shut-off notice) stays one-off.
        #expect(ActionItem(from: ExtractionResult(category: .utility)).recurrence == nil)
        // A stated cadence is respected.
        #expect(ActionItem(from: ExtractionResult(category: .utility, repeats: .monthly)).recurrence == .monthly)
        #expect(ActionItem(from: ExtractionResult(category: .utility, repeats: .yearly)).recurrence == .yearly)
    }

    @Test func monthlyRecurrenceDoesNotDriftAfterShortMonth() {
        let cal = Calendar.current
        let jan31 = cal.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        // With the original day (31) as the anchor, a short month clamps but the
        // series snaps back to 31 the next month instead of permanently drifting.
        let feb = Recurrence.monthly.nextDate(after: jan31, anchorDay: 31)!
        #expect(cal.component(.day, from: feb) == 28)   // Feb 2026 has 28 days
        let mar = Recurrence.monthly.nextDate(after: feb, anchorDay: 31)!
        #expect(cal.component(.day, from: mar) == 31)   // NOT 28 — drift is fixed
    }

    @Test func nextOccurrenceDropsPeriodSpecificFacts() {
        let r = ExtractionResult(
            title: "Con Edison electricity bill", amount: Decimal(string: "42"),
            dueDate: Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 30)),
            category: .utility, summary: "June electricity bill — pay by June 30",
            steps: ["Pay at coned.com"], notes: ["Late fee after June 30"], repeats: .monthly)
        let item = ActionItem(from: r)
        let next = item.makeNextOccurrence()!
        // Stable facts carry over…
        #expect(next.title == "Con Edison electricity bill")
        #expect(next.steps.map(\.text) == ["Pay at coned.com"])
        #expect(next.recurrence == .monthly)
        // …but period-specific facts do NOT (no stale "June" / "$42").
        #expect(next.amount == nil)
        #expect(next.summary.isEmpty)
        #expect(next.notes.isEmpty)
    }

    @Test func redundantInSeriesKeepsOneActiveAndOneDone() {
        let oldDone   = ActionItem(title: "old",  category: .utility, dueDate: day(-30), status: .done)
        let newerDone = ActionItem(title: "new",  category: .utility, dueDate: day(-1),  status: .done)
        let soonActive = ActionItem(title: "a1",  category: .utility, dueDate: day(5))
        let farActive  = ActionItem(title: "a2",  category: .utility, dueDate: day(40))
        let redundant = ActionItem.redundantInSeries([oldDone, newerDone, soonActive, farActive])
        // Keeps the newest done + the soonest active; the other two are redundant.
        #expect(Set(redundant.map(\.id)) == Set([oldDone.id, farActive.id]))
    }

    @Test func onboardingSamplesCoverEachStateAndAreExamples() {
        let s = ActionItem.samples
        #expect(s.count == 3)
        #expect(s.allSatisfy { $0.isExample })       // never schedule reminders
        let b = s.groupedForInbox()
        #expect(b.needsAttention.count == 1)          // overdue "welcome"
        #expect(b.inProgress.count == 1)              // the example bill (steps started)
        #expect(b.done.count == 1)                    // the finished example
    }

    @Test func nonRecurringHasNoNextOccurrence() {
        let oneOff = ActionItem(title: "x", category: .other, dueDate: day(5))
        #expect(!oneOff.isRecurring)
        #expect(oneOff.makeNextOccurrence() == nil)
        // Recurring but no due date → nothing to advance from.
        #expect(ActionItem(title: "x", category: .other, recurrence: .monthly)
            .makeNextOccurrence() == nil)
    }

    @Test func nextOccurrenceAdvancesDueResetsStepsAndStatus() {
        let item = ActionItem(title: "Con Edison", category: .utility,
                              amount: Decimal(string: "86.42"), dueDate: day(2),
                              status: .inProgress,
                              steps: [ChecklistStep(text: "Pay it", done: true),
                                      ChecklistStep(text: "Save receipt", done: true)],
                              recurrence: .monthly)
        item.sender = "Con Edison"

        let next = item.makeNextOccurrence()
        #expect(next != nil)
        #expect(next?.dueDate == Calendar.current.date(byAdding: .month, value: 1, to: day(2)))
        #expect(next?.status == .todo)
        #expect(next?.steps.allSatisfy { !$0.done } == true)        // checks reset
        #expect(next?.steps.map(\.text) == ["Pay it", "Save receipt"])
        #expect(next?.recurrence == .monthly)                       // series continues
        #expect(next?.amount == nil)                                // period-specific → NOT copied
        #expect(next?.sender == "Con Edison")                       // stable identity carries over
    }
}

// MARK: - Language preference (Week 8 — Profile picker)

struct ExplainLanguageTests {

    @Test func resolveUsesStoredOverride() {
        #expect(ExplainLanguage.resolve(stored: "chinese") == .chinese)
        #expect(ExplainLanguage.resolve(stored: "spanish") == .spanish)
        #expect(ExplainLanguage.resolve(stored: "english") == .english)
    }

    @Test func resolveFallsBackToDeviceWhenEmptyOrUnknown() {
        // Empty (never chosen) or a stale/garbage value → follow the device.
        #expect(ExplainLanguage.resolve(stored: "") == .deviceDefault)
        #expect(ExplainLanguage.resolve(stored: "klingon") == .deviceDefault)
    }

    @Test func promptAndDisplayNamesAreDistinct() {
        // The model is told a clear English language name…
        #expect(ExplainLanguage.chinese.promptName == "Simplified Chinese")
        // …while the picker shows the language in its own script.
        #expect(ExplainLanguage.chinese.displayName == "中文")
        #expect(ExplainLanguage.spanish.displayName == "Español")
    }
}

// MARK: - Launch metric (Week 8 — item 5)

struct MetricsTests {

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset,
                              to: Calendar.current.startOfDay(for: .now))!
    }

    @Test func summaryFunnelsByConfirmedItemAndDeDupes() {
        let a = UUID(), b = UUID(), c = UUID(), sample = UUID()
        let events: [MetricEvent] = [
            .init(kind: .confirmed, date: .now, itemID: a, source: "scanned"),
            .init(kind: .confirmed, date: .now, itemID: b, source: "guide"),
            .init(kind: .confirmed, date: .now, itemID: c, source: "custom"),  // confirmed, never completed
            .init(kind: .completed, date: .now, itemID: a, onTime: true),
            .init(kind: .completed, date: .now, itemID: a, onTime: true),      // duplicate (reopen/stale) → de-duped
            .init(kind: .completed, date: .now, itemID: b, onTime: false),
            .init(kind: .completed, date: .now, itemID: sample, onTime: true), // never confirmed (seeded sample) → ignored
        ]
        let s = MetricsSummary.from(events)
        #expect(s.confirmed == 3)
        #expect(s.completed == 2)                 // a + b; duplicate a de-duped, sample ignored
        #expect(s.completedWithDue == 2)
        #expect(s.completedOnTime == 1)           // only a was on time
        #expect(s.completionRate == 2.0 / 3.0)
        #expect(s.onTimeRate == 0.5)
        #expect(s.bySource == ["scanned": 1, "guide": 1, "custom": 1])
    }

    @Test func completionWithoutDueDateCountsButIsNotInOnTime() {
        let a = UUID()
        let s = MetricsSummary.from([
            .init(kind: .confirmed, date: .now, itemID: a, source: "custom"),
            .init(kind: .completed, date: .now, itemID: a, onTime: nil),   // no due date
        ])
        #expect(s.completed == 1)
        #expect(s.completedWithDue == 0)
        #expect(s.onTimeRate == 0)
    }

    @Test func emptyLogIsAllZeroNoDivideByZero() {
        let s = MetricsSummary.from([])
        #expect(s.confirmed == 0 && s.completed == 0)
        #expect(s.completionRate == 0 && s.onTimeRate == 0)
    }

    @Test func doneOnTimeComparesAgainstDueDate() {
        // No due date → nothing to be on-time about.
        #expect(ActionItem(title: "x", category: .other).doneOnTime() == nil)
        // Day-based: due in the future → on time; due in the past → late.
        #expect(ActionItem(title: "x", category: .other, dueDate: day(3)).doneOnTime() == true)
        #expect(ActionItem(title: "x", category: .other, dueDate: day(-3)).doneOnTime() == false)
        // Done ON the due day still counts as on time.
        #expect(ActionItem(title: "x", category: .other, dueDate: day(0)).doneOnTime() == true)
        // Timed event: compare to the exact moment.
        let item = ActionItem(title: "x", category: .other, dueDate: .now.addingTimeInterval(3600))
        item.dueHasTime = true
        #expect(item.doneOnTime() == true)
    }
}

// MARK: - Scan rate limit (10/day, 50/month)

struct ScanQuotaTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    @Test func blocksAtDailyLimitThenResetsNextDay() {
        let d = freshDefaults()
        let today = Date()
        #expect(ScanQuota.canScan(now: today, d))
        for _ in 0..<ScanQuota.perDay { ScanQuota.record(now: today, d) }
        #expect(!ScanQuota.canScan(now: today, d))
        #expect(ScanQuota.blockedReason(now: today, d) != nil)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        #expect(ScanQuota.canScan(now: tomorrow, d))   // daily counter rolled over
    }

    @Test func blocksAtMonthlyLimitAcrossDays() {
        let d = freshDefaults()
        let cal = Calendar.current
        var day = cal.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        // 5 scans/day for 10 days = 50 — under the daily cap each day, hits monthly.
        for _ in 0..<10 {
            for _ in 0..<5 { ScanQuota.record(now: day, d) }
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        #expect(ScanQuota.usedThisMonth(now: day, d) == ScanQuota.perMonth)
        #expect(!ScanQuota.canScan(now: day, d))   // monthly cap blocks even on a fresh day
    }
}
