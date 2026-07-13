//  TourGuide.swift
//
//  Drives the first-run tour shown directly on the real screens (Inbox intro →
//  Add tab → Review's "Add to inbox" → the new Inbox row) instead of a separate
//  walkthrough screen. Reworked 2026-07-13 to Evernote-style coach marks
//  (Rachel: solid accent card, title + body, page dots, Next button, dimmed
//  screen behind the intro steps) — see future_features.md for the iteration
//  history. Persisted "seen" state stays the existing `didShowWelcomeTour`
//  AppStorage key (RootTabView flips it once `step` returns to nil).
//

import SwiftUI

@Observable
final class TourGuide {
    // Int raw value doubles as the page-dot index on the cards.
    enum Step: Int, CaseIterable { case welcome, addTab, reviewAdd, inboxRow }
    var step: Step?

    static let stepCount = Step.allCases.count

    func start() { step = .welcome }

    // Moves forward only if the card currently showing is the one that fired —
    // a harmless no-op if the tour isn't running or is already past this step.
    func advance(from expected: Step) {
        guard step == expected else { return }
        let next = Step(rawValue: expected.rawValue + 1)
        step = next   // nil after the last step = tour finished
    }

    func finish() { step = nil }
}
