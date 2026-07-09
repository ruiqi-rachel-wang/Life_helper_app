//  WatchListFixTests.swift
//
//  Tests for the pre-ship review's watch-list fixes:
//   • AmountParsing — decimal comma vs thousands comma
//   • ActionItem.shiftedReminders — custom reminders follow a moved due date
//

import Testing
import Foundation
@testable import Cuevi

struct AmountParsingTests {

    @Test func plainDotAmounts() {
        #expect(AmountParsing.decimal(from: "42.17") == Decimal(string: "42.17"))
        #expect(AmountParsing.decimal(from: "$1,234.56") == Decimal(string: "1234.56"))
        #expect(AmountParsing.decimal(from: "") == nil)
        #expect(AmountParsing.decimal(from: "abc") == nil)
    }

    @Test func decimalCommaReadsAsDecimalPoint() {
        // What a Spanish/German-keyboard user types: comma IS the decimal.
        #expect(AmountParsing.decimal(from: "12,50") == Decimal(string: "12.50"))
        #expect(AmountParsing.decimal(from: "7,5") == Decimal(string: "7.5"))
    }

    @Test func thousandsCommasAreDropped() {
        // Three digits after a single comma = US thousands, not a decimal.
        #expect(AmountParsing.decimal(from: "1,234") == Decimal(string: "1234"))
        #expect(AmountParsing.decimal(from: "1,234,567") == Decimal(string: "1234567"))
    }

    @Test func commaWithDotIsThousands() {
        #expect(AmountParsing.decimal(from: "1,234.5") == Decimal(string: "1234.5"))
    }
}

struct ShiftedRemindersTests {

    private func day(_ offset: Int, hour: Int = 9) -> Date {
        let base = Calendar.current.date(byAdding: .day, value: offset,
                                         to: Calendar.current.startOfDay(for: .now))!
        return Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: base)!
    }

    @Test func remindersSlideByTheSameDayDelta() {
        let reminders = [ReminderItem(date: day(2), note: "bring passport"),
                         ReminderItem(date: day(4, hour: 15))]
        // Due moves 3 days later → every reminder moves 3 days, times/notes kept.
        let shifted = ActionItem.shiftedReminders(reminders, fromDue: day(5), toDue: day(8))
        #expect(shifted.map(\.date) == [day(5), day(7, hour: 15)])
        #expect(shifted[0].note == "bring passport")
    }

    @Test func unchangedDateOrNoOldDueLeavesRemindersAlone() {
        let reminders = [ReminderItem(date: day(1))]
        #expect(ActionItem.shiftedReminders(reminders, fromDue: day(3), toDue: day(3)) == reminders)
        #expect(ActionItem.shiftedReminders(reminders, fromDue: nil, toDue: day(3)) == reminders)
    }

    @Test func movingEarlierShiftsBackwards() {
        let reminders = [ReminderItem(date: day(6, hour: 8))]
        let shifted = ActionItem.shiftedReminders(reminders, fromDue: day(7), toDue: day(5))
        #expect(shifted.map(\.date) == [day(4, hour: 8)])
    }
}
