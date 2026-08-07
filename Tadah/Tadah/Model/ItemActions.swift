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
        item.touch()
        ReminderScheduler.shared.cancel(itemID: item.id)
        // Before the recurring-spawn guard below, so a plain (non-recurring)
        // completion syncs too. The debounce coalesces this with the spawn.
        SyncCoordinator.shared.noteLocalChange()
        guard let next = item.makeNextOccurrence() else { return }
        item.seriesID = item.effectiveSeriesID          // link parent + new cycle
        next.seriesID = item.effectiveSeriesID
        context.insert(next)
        pruneSeries(item.effectiveSeriesID, in: context)
        ReminderScheduler.shared.reschedule(for: next)
    }

    // Reopen a done item: back to active and reschedule its still-future
    // reminders. Idempotent (an active item no-ops). The Inbox re-buckets it by
    // urgency; a part-checked item reads as in-progress via its derived state.
    static func reopen(_ item: ActionItem) {
        guard item.status == .done else { return }
        item.status = .todo
        item.touch()
        ReminderScheduler.shared.reschedule(for: item)
        SyncCoordinator.shared.noteLocalChange()
    }

    // Delete an item and cancel its pending reminders. (Single occurrence — the
    // recurring "just this one vs. all future" choice stays on the Detail screen,
    // where there's room to ask.) Leaves a tombstone so the deletion syncs.
    static func delete(_ item: ActionItem, in context: ModelContext) {
        ReminderScheduler.shared.cancel(itemID: item.id)
        tombstone(item, in: context)
        context.delete(item)
        SyncCoordinator.shared.noteLocalChange()
    }

    // Record that a real item was deleted, so cross-device sync can propagate it.
    // Examples aren't user data and never sync, so they get no tombstone.
    static func tombstone(_ item: ActionItem, in context: ModelContext) {
        guard !item.isExample else { return }
        context.insert(TaskTombstone(id: item.id))
    }

    // Keep a recurring series to one active + one done, deleting the rest.
    private static func pruneSeries(_ sid: UUID, in context: ModelContext) {
        let descriptor = FetchDescriptor<ActionItem>(predicate: #Predicate { $0.seriesID == sid })
        guard let members = try? context.fetch(descriptor) else { return }
        for redundant in ActionItem.redundantInSeries(members) {
            ReminderScheduler.shared.cancel(itemID: redundant.id)
            tombstone(redundant, in: context)
            context.delete(redundant)
        }
    }
}
