//  TourGuide.swift
//
//  Drives the first-run tour shown directly on the real screens (Inbox intro →
//  Add tab → the Add page's three ways in → Review's "Add to inbox" → the new
//  Inbox row) instead of a separate walkthrough screen. Evernote-style coach
//  marks since 2026-07-13 (Rachel's screenshot) — see notes/future_features.md for
//  the iteration history. Persisted "seen" state stays the existing
//  `didShowWelcomeTour` AppStorage key (RootTabView flips it once `step`
//  returns to nil).
//

import SwiftUI

@Observable
final class TourGuide {
    // Int raw value doubles as the page-dot index on the cards.
    enum Step: Int, CaseIterable { case welcome, addTab, create, reviewAdd, inboxRow }
    var step: Step?

    static let stepCount = Step.allCases.count

    func start() { step = .welcome }

    // Next buttons move strictly one card forward — a harmless no-op if the
    // tour isn't running or is already past this step.
    func advance(from expected: Step) {
        guard step == expected else { return }
        step = Step(rawValue: expected.rawValue + 1)   // nil after the last step
    }

    // Real-action milestones jump the tour forward to wherever the user
    // actually IS — e.g. reaching the Add tab lands on .create no matter which
    // inbox card was up, and the Review screen appearing lands on .reviewAdd
    // even when the user came in sideways via the Guides tab. Never moves
    // backward, never starts a tour that isn't running.
    func catchUp(to target: Step) {
        guard let current = step, current.rawValue < target.rawValue else { return }
        step = target
    }

    func finish() { step = nil }
}
