//  TourGuide.swift
//
//  Drives the first-run hints shown directly on the real screens (Inbox → Add
//  tab, Review → Add to inbox, Inbox → the new row) instead of a separate
//  walkthrough screen. Reworked 2026-07-12 (Rachel: no separate screen, no
//  slideshow — on-page, transparent background, an arrow telling you what to
//  do). Persisted "seen" state stays the existing `didShowWelcomeTour`
//  AppStorage key (RootTabView flips it once `step` returns to nil).
//

import SwiftUI

@Observable
final class TourGuide {
    enum Step { case addTab, reviewAdd, inboxRow }
    var step: Step?

    func start() { step = .addTab }

    // Moves forward only if the hint currently showing is the one that fired —
    // a harmless no-op if the tour isn't running or is already past this step.
    func advance(from expected: Step) {
        guard step == expected else { return }
        switch expected {
        case .addTab:    step = .reviewAdd
        case .reviewAdd: step = .inboxRow
        case .inboxRow:  step = nil
        }
    }

    func finish() { step = nil }
}
