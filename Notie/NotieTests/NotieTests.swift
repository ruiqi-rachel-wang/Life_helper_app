//  NotieTests.swift
//
//  Unit tests for the domain logic on ActionItem. These run with Cmd+U
//  (or `xcodebuild test`) in seconds and need no UI — exactly the kind
//  of logic that's worth locking down before persistence lands.
//

import Testing
import Foundation
@testable import Notie

struct ActionItemTests {

    // Helper: a date N days from the start of today.
    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset,
                              to: Calendar.current.startOfDay(for: .now))!
    }

    // MARK: isOverdue

    @Test func dueInPastIsOverdue() {
        let item = ActionItem(title: "x", category: .other, dueDate: day(-2))
        #expect(item.isOverdue == true)
    }

    @Test func dueInFutureIsNotOverdue() {
        let item = ActionItem(title: "x", category: .other, dueDate: day(5))
        #expect(item.isOverdue == false)
    }

    @Test func doneItemIsNeverOverdue() {
        let item = ActionItem(title: "x", category: .other,
                              dueDate: day(-10), status: .done)
        #expect(item.isOverdue == false)
    }

    @Test func noDueDateIsNotOverdue() {
        let item = ActionItem(title: "x", category: .other)
        #expect(item.isOverdue == false)
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
        let item = ActionItem(title: "x", category: .other)
        #expect(item.reminderSchedule().isEmpty)
    }

    @Test func futureItemHasThreeReminders() {
        let item = ActionItem(title: "x", category: .other, dueDate: day(10))
        let schedule = item.reminderSchedule()
        #expect(schedule.count == 3)
        #expect(schedule.map(\.label) == ["3 days before", "1 day before", "Due day"])
    }

    @Test func overdueItemAddsFollowUp() {
        let item = ActionItem(title: "x", category: .other, dueDate: day(-2))
        let schedule = item.reminderSchedule()
        #expect(schedule.count == 4)
        #expect(schedule.last?.label == "Overdue follow-up")
    }

    @Test func reminderDatesAreOffsetFromDueDate() {
        let due = day(10)
        let item = ActionItem(title: "x", category: .other, dueDate: due)
        let schedule = item.reminderSchedule()
        let cal = Calendar.current
        #expect(schedule[0].date == cal.date(byAdding: .day, value: -3, to: due))
        #expect(schedule[1].date == cal.date(byAdding: .day, value: -1, to: due))
        #expect(schedule[2].date == due)
    }
}
