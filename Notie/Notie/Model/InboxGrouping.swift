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
//    inProgress      → some steps checked
//    upcoming        → everything else
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
            } else if item.doneCount > 0 {
                b.inProgress.append(item)
            } else {
                b.upcoming.append(item)
            }
        }
        return b
    }
}
