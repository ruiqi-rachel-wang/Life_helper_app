//  TaskLimit.swift
//
//  Per-tier cap on how many items the task list can hold. Every real item counts
//  regardless of status (todo / in progress / done) — the user deletes to make
//  room. Seeded example items (isExample) don't count. Pass `plus:` from
//  PlusStore.isPlus:
//    • Free: 20 items.
//    • Plus: 100 items.
//
//  Recurrence's auto-generated next occurrences are deliberately NOT gated here:
//  a repeating task must be able to roll forward even when the list is full.
//

import Foundation
import SwiftData

nonisolated enum TaskLimit {
    static let max = 20        // free
    static let maxPlus = 100   // Plus

    static func cap(plus: Bool) -> Int { plus ? maxPlus : max }

    // How many real items exist right now (examples excluded).
    static func count(_ context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<ActionItem>(predicate: #Predicate { !$0.isExample })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    static func remaining(_ context: ModelContext, plus: Bool = false) -> Int {
        Swift.max(0, cap(plus: plus) - count(context))
    }

    static func isFull(_ context: ModelContext, plus: Bool = false) -> Bool {
        remaining(context, plus: plus) == 0
    }

    // A user-facing reason when the list is full, else nil.
    static func blockedReason(_ context: ModelContext, plus: Bool = false) -> String? {
        isFull(context, plus: plus)
            ? String(localized: "Your list is full at \(cap(plus: plus)) items. Delete one to add another.")
            : nil
    }
}
