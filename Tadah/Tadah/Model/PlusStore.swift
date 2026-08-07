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

    // Restore a previous purchase (e.g. new device / reinstall). Returns whether
    // the user is Plus afterward, so the caller can show a result.
    @discardableResult
    func restore() async -> Bool {
        if let info = try? await Purchases.shared.restorePurchases() { apply(info) }
        return isPlus
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
    }
}
