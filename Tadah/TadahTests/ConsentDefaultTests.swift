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
            #expect(AIConsent.allowsSendingDocuments == false)

            AIConsent.record(granted: false)
            #expect(AIConsent.state == .declined)
            #expect(AIConsent.allowsSendingDocuments == false)

            AIConsent.record(granted: true)
            #expect(AIConsent.state == .granted)
            #expect(AIConsent.allowsSendingDocuments == true)

            // Withdrawable — the Profile toggle writes the same key, and turning
            // it back off has to actually stop future scans.
            AIConsent.set(false)
            #expect(AIConsent.allowsSendingDocuments == false)
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
}
