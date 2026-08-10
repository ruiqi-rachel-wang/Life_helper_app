//  TaskLimit.swift
//
//  Per-tier cap on how many items a list can hold. Every real item counts
//  regardless of status (todo / in progress / done) — the user deletes to make
//  room. Seeded example items (isExample) don't count. Pass `plus:` from
//  PlusStore.isPlus:
//    • Free: 20 items (one profile, so 20 in total).
//    • Plus: 100 items PER PROFILE — a family of four isn't fighting over one
//      shared pool, and each person's list feels like their own.
//
//  Counting is scoped to a BUCKET: one profile, or — for nil — the family list
//  of to-dos that belong to nobody in particular. Items saved before profiles
//  existed are adopted onto the owner at launch (ProfileStore), so nil after that
//  genuinely means "for the whole family", not "unassigned leftover".
//
//  Recurrence's auto-generated next occurrences are deliberately NOT gated here:
//  a repeating task must be able to roll forward even when the list is full.
//

import Foundation
import SwiftData

nonisolated enum TaskLimit {
    static let max = 20        // free
    static let maxPlus = 100   // Plus, per profile

    static func cap(plus: Bool) -> Int { plus ? maxPlus : max }

    // How many real items sit in one BUCKET (examples excluded). A bucket is
    // exactly one profile — or, for nil, the family list that belongs to nobody
    // in particular. Counting family items against every person would mean one
    // shared errand eating four people's allowances at once.
    static func count(_ context: ModelContext, profileID: UUID? = nil) -> Int {
        let descriptor: FetchDescriptor<ActionItem>
        if let profileID {
            descriptor = FetchDescriptor(predicate: #Predicate {
                !$0.isExample && $0.profileID == profileID
            })
        } else {
            descriptor = FetchDescriptor(predicate: #Predicate {
                !$0.isExample && $0.profileID == nil
            })
        }
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    static func remaining(_ context: ModelContext, plus: Bool = false, profileID: UUID? = nil) -> Int {
        Swift.max(0, cap(plus: plus) - count(context, profileID: profileID))
    }

    static func isFull(_ context: ModelContext, plus: Bool = false, profileID: UUID? = nil) -> Bool {
        remaining(context, plus: plus, profileID: profileID) == 0
    }

    // A user-facing reason when the list is full, else nil.
    static func blockedReason(_ context: ModelContext, plus: Bool = false,
                              profileID: UUID? = nil) -> String? {
        isFull(context, plus: plus, profileID: profileID)
            ? String(localized: "This list is full at \(cap(plus: plus)) items. Delete one to add another.")
            : nil
    }
}
