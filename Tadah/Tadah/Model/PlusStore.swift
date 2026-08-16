//  PlusStore.swift
//
//  The Tadah Plus entitlement, as seen by the app (Part 3 monetization). One
//  source of truth for "is this user Plus?" — read from RevenueCat's CustomerInfo
//  and kept live via its customerInfoStream, so a purchase / restore / expiry
//  flips the whole UI without any manual refresh.
//
//  The identifier `plus` MUST match the Entitlement identifier in the RevenueCat
//  dashboard (Product catalog → Entitlements). If they drift, isPlus stays false.
//

import Foundation
import Observation
import RevenueCat

@MainActor
@Observable
final class PlusStore {
    // Must equal the RevenueCat entitlement identifier EXACTLY. RevenueCat won't
    // let you rename an entitlement, and this project's is "Tadah Pro" (its Display
    // Name is "Tadah Plus" — that's what users see). If you ever make a clean
    // `plus` entitlement, this is the only line to change.
    static let entitlementID = "Tadah Pro"

    private(set) var isPlus = false
    // Have we heard from RevenueCat AT ALL yet? `isPlus` starts false, so without
    // this a subscriber's Plus features would blink off at every launch until the
    // first CustomerInfo lands — and would stay off entirely if RevenueCat were
    // unreachable. Anything that HIDES a paid feature must wait for this, the same
    // "unknown tier is treated as Plus" rule the Worker's cap check uses.
    private(set) var tierKnown = false

    // WHAT EVERY PAID GATE SHOULD ASK. Fails OPEN: a tier we haven't heard about
    // yet counts as Plus.
    //
    // `isPlus` alone is the raw answer from RevenueCat, and it starts false — so
    // during an outage, or in the seconds before the first CustomerInfo lands, a
    // paying subscriber was handed free-tier scan quotas and a 20-item list cap,
    // and shown "See Tadah Plus" for something they already pay for. Family
    // profiles already got this right via `familyUnlocked`; scans and task limits
    // were still reading `isPlus` directly.
    //
    // It's the same rule the Worker applies when it can't determine a tier, and
    // the cost of being wrong is asymmetric: briefly generous to a lapsed user,
    // versus visibly breaking what a paying one bought.
    //
    // Use `isPlus` ONLY where the truth itself is the subject — the "Free plan"
    // badge in Profile, and what a restore actually restored.
    var paidFeaturesUnlocked: Bool { !tierKnown || isPlus }

    init() {
        Task {
            await refresh()
            await listenForChanges()
        }
    }

    // One-shot fetch (used on launch + after restore).
    func refresh() async {
        guard let info = try? await Purchases.shared.customerInfo() else { return }
        apply(info)
    }

    // What a restore attempt actually did. "Nothing to restore" and "we couldn't
    // reach the store" are different situations and need different words: the
    // first is final, the second is worth retrying. Collapsing both into a bare
    // Bool told a paying user on a flaky connection that they had never bought
    // anything.
    enum RestoreResult: Equatable {
        case restored          // entitlement is active again
        case nothingToRestore  // reached the store; this Apple ID has no purchase
        case failed            // couldn't reach the store — retryable
    }

    // Restore a previous purchase (e.g. new device / reinstall).
    @discardableResult
    func restore() async -> RestoreResult {
        do {
            apply(try await Purchases.shared.restorePurchases())
            return isPlus ? .restored : .nothingToRestore
        } catch {
            return .failed
        }
    }

    // Live updates: RevenueCat pushes a new CustomerInfo whenever entitlements
    // change (purchase, renewal, expiry), so the UI reacts on its own.
    private func listenForChanges() async {
        for await info in Purchases.shared.customerInfoStream {
            apply(info)
        }
    }

    private func apply(_ info: CustomerInfo) {
        isPlus = info.entitlements[Self.entitlementID]?.isActive == true
        tierKnown = true
    }
}
