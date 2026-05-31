//  InboxGrouping.swift
//
//  Pure logic for splitting items into the Inbox's urgency sections.
//  Lives in the model layer (no SwiftUI) so it's unit-testable without
//  any UI — the view just renders whatever buckets this returns.
//
//  Buckets are mutually exclusive, in priority order:
//    done            → status == .done
//    needsAttention  → overdue (and not done)
//    dueThisWeek     → due within the next 7 days
//    inProgress      → no due date (ongoing) OR some steps checked
//    upcoming        → has a future due date (>7 days) and not started
//

import Foundation

struct InboxBuckets {
    var needsAttention: [ActionItem] = []
    var dueThisWeek: [ActionItem] = []
    var inProgress: [ActionItem] = []
    var upcoming: [ActionItem] = []
    var done: [ActionItem] = []

    var activeCount: Int {
        needsAttention.count + dueThisWeek.count + inProgress.count + upcoming.count
    }
}

extension Array where Element == ActionItem {
    func groupedForInbox(now: Date = .now, calendar: Calendar = .current) -> InboxBuckets {
        var b = InboxBuckets()
        let today = calendar.startOfDay(for: now)

        for item in self {
            if item.status == .done {
                b.done.append(item)
            } else if item.isOverdue {
                b.needsAttention.append(item)
            } else if let due = item.dueDate,
                      let days = calendar.dateComponents([.day], from: today,
                                                         to: calendar.startOfDay(for: due)).day,
                      (0...7).contains(days) {
                b.dueThisWeek.append(item)
            } else if item.dueDate == nil || item.doneCount > 0 {
                // No due date = ongoing, or already started = in progress.
                b.inProgress.append(item)
            } else {
                // Has a future due date (>7 days out) and not started yet.
                b.upcoming.append(item)
            }
        }
        return b
    }
}
