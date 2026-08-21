//  PaywallView.swift
//
//  The Tadah Plus upgrade screen. Renders the paywall Rachel designs in the
//  RevenueCat dashboard (Paywalls tab) via RevenueCatUI — so copy, layout, and
//  which packages/prices show are all editable there with no app release. This is
//  a thin wrapper so the call site (`PaywallView()` in ProfileView) is unchanged.
//
//  On a successful purchase/restore the `Tadah Pro` entitlement flips, PlusStore's
//  customerInfoStream updates isPlus app-wide, and we close the sheet.
//
//  ⚠️ WHY THIS CHECKS FOR AN OFFERING FIRST
//  RevenueCatUI needs a *current Offering* with products StoreKit can actually
//  fetch. When there isn't one it puts up its own raw alert — the infamous
//  "Error 23: There is an issue with your configuration", with a link to
//  RevenueCat's troubleshooting docs. That is a developer message, and showing it
//  to someone who tapped "Upgrade" is worse than showing nothing: it looks like
//  the app is broken and tells them to go read an SDK guide.
//
//  ⚠️ AND WHY RESTORE IS ALWAYS REACHABLE
//  RevenueCat's paywall is the ONLY place in the app that offers Restore
//  Purchases. So a fallback that simply replaced it would strand anyone who had
//  already paid — reinstalling, or on a new phone, with no way to get their
//  entitlement back. Apple also requires a restore path in any app selling
//  non-consumables/subscriptions. Every state below therefore keeps it.
//
//  A transient network failure is NOT the same as "not for sale yet", so the two
//  are distinguished: one offers Try again, the other says coming soon.
//
//  For local development, `Tadah.storekit` is attached to the scheme's Run action.
//  It removes the App Store Connect dependency for *buying* — StoreKit resolves
//  and transacts the product IDs locally — but it does NOT by itself make the real
//  paywall appear. Offerings are fetched from RevenueCat's backend, not from the
//  local file, so until the dashboard has products with these IDs in an Offering
//  marked Current (with the `Tadah Pro` entitlement), the SDK throws
//  `.configurationError` and this screen correctly says "coming soon".
//

import SwiftUI
import RevenueCat
import RevenueCatUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlusStore.self) private var plus
    // Only so Restore can re-identify this device to RevenueCat first, and so
    // "nothing found" can say the right thing to a guest vs. a signed-in user.
    @Environment(AccountStore.self) private var account
    @AppStorage(ExplainLanguage.storageKey) private var explainLanguageRaw = ""

    private enum Phase: Equatable {
        case checking
        case ready                 // a current offering with packages — show the real paywall
        case notForSaleYet         // reached the store, but nothing is on sale
        case couldNotLoad          // transient: network/backend hiccup, worth retrying
    }

    @State private var phase: Phase = .checking
    @State private var isRestoring = false
    @State private var restoreMessage: String?

    // Follow the in-app language picker (English / 中文 / Español), not just the
    // phone's language — an ESL user may have an English phone but prefer 中文, and
    // that's exactly who we want to reach with the localized paywall.
    //
    // The paywall's language is NOT set here. It used to be, via
    // `.environment(\.locale)` on RevenueCatUI.PaywallView, and that never worked:
    // a v2 (Paywall Editor) paywall chooses its localization from
    // `Purchases.preferredLocales` and then overwrites the environment locale with
    // its choice. AppLanguage.apply now calls `overridePreferredUILocale`, which is
    // the API that actually decides. This property is only for our own fallback copy.
    private var language: ExplainLanguage { ExplainLanguage.resolve(stored: explainLanguageRaw) }

    var body: some View {
        Group {
            switch phase {
            case .checking:
                loading
            case .ready:
                // RevenueCatUI's own PaywallView (module-qualified to avoid
                // clashing with this wrapper's name). The close button lets the
                // user back out; a completed purchase or restore dismisses us.
                RevenueCatUI.PaywallView(displayCloseButton: true)
                    .onPurchaseCompleted { _ in dismiss() }
                    .onRestoreCompleted { info in
                        if info.entitlements[PlusStore.entitlementID]?.isActive == true { dismiss() }
                    }
            case .notForSaleYet:
                fallback(
                    title: String(localized: "Tadah Plus is coming soon"),
                    // Don't promise to notify anyone: there is no mechanism to do
                    // it (no push, and we don't email). Saying "check back" is the
                    // version we can actually honour.
                    body: String(localized: "We're putting the finishing touches on it. Everything you use today stays free — check back soon."),
                    canRetry: false)
            case .couldNotLoad:
                fallback(
                    title: String(localized: "We couldn't load Tadah Plus"),
                    body: String(localized: "Please check your connection and try again."),
                    canRetry: true)
            }
        }
        .task { await checkAvailability() }
        .alert("Restore purchases",
               isPresented: Binding(get: { restoreMessage != nil },
                                    set: { if !$0 { restoreMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreMessage ?? "")
        }
    }

    // MARK: - states

    private var loading: some View {
        ZStack {
            Color.paper.ignoresSafeArea()
            ProgressView()
        }
    }

    // Deliberately says nothing about configuration, SDKs or error codes — from
    // the user's side this is a feature that isn't on sale yet, or a connection
    // that didn't work. Restore stays available in both cases.
    private func fallback(title: String, body: String, canRetry: Bool) -> some View {
        ZStack(alignment: .top) {
            Color.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 28))
                            .foregroundStyle(Color.faint)
                    }
                    .buttonStyle(.plain).accessibilityLabel("Close")
                }
                .padding(.top, 8)

                Spacer()

                VStack(spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 34)).foregroundStyle(Color.accent)
                    Text(title)
                        .font(.serifTitle).tracking(-0.6).foregroundStyle(Color.ink)
                        .multilineTextAlignment(.center)
                    Text(body)
                        .font(.body14).foregroundStyle(Color.faded)
                        .multilineTextAlignment(.center).lineSpacing(3)
                }
                .padding(.horizontal, 28)

                if canRetry {
                    Button("Try again") {
                        phase = .checking
                        Task { await checkAvailability(force: true) }
                    }
                    .font(.body14.weight(.semibold)).foregroundStyle(Color.accent)
                    .padding(.top, 18)
                }

                Spacer()

                // ALWAYS present. Someone who already subscribed must be able to
                // get their access back even when nothing is currently on sale.
                VStack(spacing: 8) {
                    Button {
                        Task { await restore() }
                    } label: {
                        HStack(spacing: 8) {
                            if isRestoring { ProgressView().controlSize(.small) }
                            Text("Restore purchases").font(.body14.weight(.semibold))
                        }
                        .foregroundStyle(Color.ink)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRestoring)

                    Text("Already subscribed? Bring your Plus access to this phone.")
                        .font(.subline).foregroundStyle(Color.faded)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 28)
            }
            .padding(.horizontal, 22)
        }
    }

    // MARK: - actions

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        switch await plus.restore(as: account.account?.userID) {
        case .restored:
            dismiss()                       // entitlement is back; nothing more to say
        case .expired:
            restoreMessage = String(localized: "Your previous Tadah Plus subscription has expired. Choose a plan above to start again.")
        case .nothingToRestore:
            // TWO DIFFERENT DEAD ENDS, and the old single line answered neither.
            // Restore reads the receipt of the Apple ID in Settings → Media &
            // Purchases — nothing to do with a Tadah account. So a guest who
            // bought Plus while signed in needs to be told to sign in (the
            // entitlement follows the account on its own), and a signed-in user
            // needs to be told to check WHICH Apple ID this phone is on.
            restoreMessage = account.isSignedIn
                ? String(localized: "We couldn't find a Tadah Plus purchase on your account, or on the Apple ID signed in to this phone. If you bought it with a different Apple ID, switch to that one in Settings and try again.")
                : String(localized: "We couldn't find a purchase on the Apple ID signed in to this phone. If you bought Tadah Plus while signed in to a Tadah account, sign in to that account instead — your membership comes back with it.")
        case .failed:
            // Distinct from "nothing found" — this one is worth trying again.
            restoreMessage = String(localized: "We couldn't reach the App Store. Please check your connection and try again.")
        }
    }

    // Ask RevenueCat whether there's a current offering with at least one package
    // BEFORE handing over.
    //
    // Not every thrown error means "try again". Until the products exist in App
    // Store Connect and sit in a Current Offering, RevenueCat doesn't return an
    // empty list — it THROWS `.configurationError` (the SDK's error 23). Sending
    // that to the retry screen told the user to check their connection, which is
    // both wrong and unactionable: their network is fine, and no amount of tapping
    // Retry will change the answer until the store side is set up.
    //
    // So the split is by whether the user can do anything about it:
    //   • setup isn't finished  → "coming soon", no retry (it's our work, not theirs)
    //   • couldn't reach it     → "check your connection", retry
    private func checkAvailability(force: Bool = false) async {
        guard force || phase == .checking else { return }
        do {
            let offerings = try await Purchases.shared.offerings()
            let packages = offerings.current?.availablePackages ?? []
            phase = packages.isEmpty ? .notForSaleYet : .ready
        } catch {
            phase = Self.isStoreNotSetUp(error) ? .notForSaleYet : .couldNotLoad
        }
    }

    // Permanent "there is nothing to sell yet" conditions, as opposed to transient
    // ones. Anything unrecognised stays retryable — a wrong "coming soon" hides a
    // real outage, which is the worse of the two mistakes.
    static func isStoreNotSetUp(_ error: Error) -> Bool {
        guard let code = error as? RevenueCat.ErrorCode else { return false }
        switch code {
        case .configurationError, .productNotAvailableForPurchaseError:
            return true
        default:
            return false
        }
    }
}
