//  ConsentDefaultTests.swift
//
//  These pin two DEFAULTS, and the reason they deserve a test is that getting
//  either backwards is invisible in the UI and expensive in the real world.
//
//  A `?? true` where a `?? false` belongs sends every never-asked user's
//  documents to OpenAI, or uploads analytics from people who never agreed. The
//  app looks identical either way — no screen changes, no error, nothing to
//  notice in review. The only thing standing between that and a shipped build is
//  an assertion, so here it is.
//
//  Both settings read UserDefaults.standard (they are consulted from non-SwiftUI
//  code paths), so each test saves and restores the real value rather than
//  leaving the simulator's state changed for whatever runs next.
//

import Testing
import Foundation
@testable import Tadah

@MainActor
struct ConsentDefaultTests {

    private func withCleanDefault<T>(_ key: String, _ body: () throws -> T) rethrows -> T {
        let d = UserDefaults.standard
        let saved = d.object(forKey: key)
        defer { saved == nil ? d.removeObject(forKey: key) : d.set(saved, forKey: key) }
        d.removeObject(forKey: key)
        return try body()
    }

    // SILENCE IS NOT AGREEMENT. Never having been asked must read exactly like
    // having said no, on the one code path that puts a document on the network.
    @Test func documentsAreNotSentUntilTheUserAgrees() {
        withCleanDefault(AIConsent.key) {
            #expect(AIConsent.state == .notAsked)
            #expect(AIConsent.allowsSendingToAI == false)

            AIConsent.record(granted: false)
            #expect(AIConsent.state == .declined)
            #expect(AIConsent.allowsSendingToAI == false)

            AIConsent.record(granted: true)
            #expect(AIConsent.state == .granted)
            #expect(AIConsent.allowsSendingToAI == true)

            // Withdrawable — the Profile toggle writes the same key, and turning
            // it back off has to actually stop future scans.
            AIConsent.set(false)
            #expect(AIConsent.allowsSendingToAI == false)
        }
    }

    // THE SECOND PATH TO OPENAI. The moving/renting utility lookup sent a ZIP and
    // every answer to that guide's questions with no permission check at all, and
    // kept doing it while "Send scans to AI" was off — a per-feature flag is
    // exactly how it got missed. Declining must silence BOTH paths.
    @Test func decliningAlsoStopsTheGuideUtilityLookup() {
        withCleanDefault(AIConsent.key) {
            let answers = ["home": "Renting", "knowAddress": "Yes", "zip": "78701"]

            AIConsent.record(granted: false)
            // The question isn't even asked…
            #expect(!Guide.moving.visibleQuestions(answers).contains { $0.id == "zip" })
            #expect(!Guide.rentingNewPlace.visibleQuestions(answers).contains { $0.id == "zip" })
            // …and a stale answer carrying a ZIP still can't trigger the call.
            #expect(Guide.moving.usesScanQuota(for: answers) == false)
            #expect(Guide.rentingNewPlace.usesScanQuota(for: ["zip": "78701"]) == false)

            AIConsent.record(granted: true)
            #expect(Guide.moving.visibleQuestions(answers).contains { $0.id == "zip" })
            #expect(Guide.moving.usesScanQuota(for: answers) == true)
        }
    }

    // Analytics are OPT-IN. This flipped from opt-out on 2026-08-17.
    @Test func usageStatsStayOnTheDeviceUntilSwitchedOn() {
        withCleanDefault(Metrics.shareUsageKey) {
            #expect(Metrics.uploadsEnabled == false)          // unset → off

            UserDefaults.standard.set(true, forKey: Metrics.shareUsageKey)
            #expect(Metrics.uploadsEnabled == true)           // explicit yes is honoured

            UserDefaults.standard.set(false, forKey: Metrics.shareUsageKey)
            #expect(Metrics.uploadsEnabled == false)
        }
    }

    // ASKED ONCE, AND A "NO" STAYS NO. The first-launch sheet (FirstRunPrompts)
    // appears only while the answer is `.notAsked`, so if declining didn't count
    // as an answer the app would ask the same question at every single launch —
    // which is nagging, not consent. Both answers must therefore leave
    // `.notAsked` behind, and only one of them may switch uploads on.
    @Test func decliningUsageStatsCountsAsAnAnswerAndIsNotReAsked() {
        withCleanDefault(Metrics.shareUsageKey) {
            #expect(Metrics.usageConsent == .notAsked)

            Metrics.recordUsageConsent(false)
            #expect(Metrics.usageConsent == .declined)        // answered — don't ask again
            #expect(Metrics.uploadsEnabled == false)

            Metrics.recordUsageConsent(true)
            #expect(Metrics.usageConsent == .granted)
            #expect(Metrics.uploadsEnabled == true)

            // The Profile toggle writes the same key, and switching it back off
            // has to stop uploads AND still count as answered.
            UserDefaults.standard.set(false, forKey: Metrics.shareUsageKey)
            #expect(Metrics.usageConsent == .declined)
            #expect(Metrics.uploadsEnabled == false)
        }
    }
}
