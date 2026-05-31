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
}
