//  ItemActions.swift
//
//  The ONE place "mark this item done" and "delete this item" live, so the
//  three entry points — the Detail screen button, the Inbox swipe, and the
//  notification "Mark done" action — can't drift apart. Each used to hand-roll
//  the metric log + recurring-spawn + prune, which is exactly the kind of thing
//  that silently diverges.
//

import Foundation
import SwiftData

@MainActor
enum ItemActions {
    // Mark an item done: log the completion metric, set status, cancel its
    // reminders, and — for a recurring item — spawn + schedule the next cycle and
    // prune the series to at most one active + one done. Idempotent: an
    // already-done item no-ops (so a stale notification tap can't double-count).
    // Callers on an autosaving @Query/@Bindable context don't need to save;
    // the notification delegate (its own ModelContext) saves afterward.
    static func complete(_ item: ActionItem, in context: ModelContext) {
        guard item.status != .done else { return }
        Metrics.record(.completed, itemID: item.id, onTime: item.doneOnTime())
        item.status = .done
        ReminderScheduler.shared.cancel(itemID: item.id)
        guard let next = item.makeNextOccurrence() else { return }
        item.seriesID = item.effectiveSeriesID          // link parent + new cycle
        next.seriesID = item.effectiveSeriesID
        context.insert(next)
        pruneSeries(item.effectiveSeriesID, in: context)
        ReminderScheduler.shared.reschedule(for: next)
    }

    // Delete an item and cancel its pending reminders. (Single occurrence — the
    // recurring "just this one vs. all future" choice stays on the Detail screen,
    // where there's room to ask.)
    static func delete(_ item: ActionItem, in context: ModelContext) {
        ReminderScheduler.shared.cancel(itemID: item.id)
        context.delete(item)
    }

    // Keep a recurring series to one active + one done, deleting the rest.
    private static func pruneSeries(_ sid: UUID, in context: ModelContext) {
        let descriptor = FetchDescriptor<ActionItem>(predicate: #Predicate { $0.seriesID == sid })
        guard let members = try? context.fetch(descriptor) else { return }
        for redundant in ActionItem.redundantInSeries(members) {
            ReminderScheduler.shared.cancel(itemID: redundant.id)
            context.delete(redundant)
        }
    }
}
