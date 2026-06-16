//  NotieTests.swift
//
//  Unit tests for ActionItem — domain logic (isOverdue, doneCount,
//  reminderSchedule) plus a real SwiftData round-trip on an in-memory
//  store (insert → save → fetch → delete). Run with Cmd+U.
//

import Testing
import Foundation
import SwiftData
@testable import Notie

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

    @Test func overdueItemAddsFollowUp() {
        let schedule = ActionItem(title: "x", category: .other, dueDate: day(-2)).reminderSchedule()
        #expect(schedule.count == 4)
        #expect(schedule.last?.label == "Overdue follow-up")
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

    @Test func dueTodayIsDueThisWeekNotOverdue() {
        let b = [ActionItem(title: "today", category: .other, dueDate: day(0))].groupedForInbox()
        #expect(b.dueThisWeek.count == 1)
        #expect(b.needsAttention.isEmpty)
    }

    @Test func noDueDateGoesToInProgressNotUpcoming() {
        let b = [ActionItem(title: "no date", category: .other)].groupedForInbox()
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
        let custom = day(7)
        item.reminders = [custom]
        item.remindersCustomized = true
        #expect(item.effectiveReminders == [custom])        // custom wins
    }

    @Test func customizedEmptyMeansNoReminders() {
        let item = ActionItem(title: "Bill", category: .utility, dueDate: day(10))
        item.remindersCustomized = true                     // emptied on purpose
        #expect(item.effectiveReminders.isEmpty)
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
        #expect(next?.amount == Decimal(string: "86.42"))           // detail carries over
        #expect(next?.sender == "Con Edison")
    }
}
