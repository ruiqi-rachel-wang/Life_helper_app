//  PaywallView.swift
//
//  The Tadah Plus upgrade screen. Renders the paywall Rachel designs in the
//  RevenueCat dashboard (Paywalls tab) via RevenueCatUI — so copy, layout, and
//  which packages/prices show are all editable there with no app release. This is
//  a thin wrapper so the call site (`PaywallView()` in ProfileView) is unchanged.
//
//  Requires the current Offering to have a Paywall attached in the dashboard;
//  otherwise RevenueCatUI shows its default template.
//
//  On a successful purchase/restore the `Tadah Pro` entitlement flips, PlusStore's
//  customerInfoStream updates isPlus app-wide, and we close the sheet.
//

import SwiftUI
import RevenueCat
import RevenueCatUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ExplainLanguage.storageKey) private var explainLanguageRaw = ""

    // Follow the in-app language picker (English / 中文 / Español), not just the
    // phone's language — an ESL user may have an English phone but prefer 中文, and
    // that's exactly who we want to reach with the localized paywall. When the
    // picker is unset, `resolve` returns the device language, so this still falls
    // back to the phone's locale. Must match the paywall's localizations in the
    // RevenueCat dashboard (en / es / zh-Hans).
    private var language: ExplainLanguage { ExplainLanguage.resolve(stored: explainLanguageRaw) }

    var body: some View {
        // RevenueCatUI's own PaywallView (module-qualified to avoid clashing with
        // this wrapper's name). The close button lets the user back out; a
        // completed purchase or restore dismisses us.
        RevenueCatUI.PaywallView(displayCloseButton: true)
            .environment(\.locale, Locale(identifier: language.lprojCode))
            .onPurchaseCompleted { _ in dismiss() }
            .onRestoreCompleted { info in
                if info.entitlements[PlusStore.entitlementID]?.isActive == true { dismiss() }
            }
    }
}
