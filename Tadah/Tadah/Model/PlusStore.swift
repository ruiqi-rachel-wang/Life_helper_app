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

    // WHAT THE ACCOUNT PAGE NEEDS TO SHOW ABOUT A SUBSCRIPTION.
    //
    // Everything here comes from RevenueCat's EntitlementInfo. Deliberately a
    // plain snapshot rather than the SDK type, so the view never has to know the
    // SDK and this can be built in a preview or a test.
    //
    // ⚠️ THERE IS NO "PAUSE". Apple's App Store has no subscription-pause feature
    // (that's Google Play), so offering one would be a button that cannot work.
    // Cancelling also cannot happen in-app — Apple owns that screen, and the only
    // correct thing we can do is send people to it.
    struct Membership: Equatable {
        var isActive: Bool
        var willRenew: Bool
        var expirationDate: Date?
        var productIdentifier: String
        var hasBillingProblem: Bool
        var isYearly: Bool { productIdentifier.contains("yearly") || productIdentifier.contains("annual") }
    }

    // nil means NOT SUBSCRIBED — but only once `tierKnown` is true. Before that
    // it means "we haven't heard yet", and the two must not be shown the same
    // way: a subscriber opening this screen during a slow launch was briefly
    // labelled "Free plan", which is the app telling a paying customer they
    // aren't one. Views should ask `membershipState`, not this.
    private(set) var membership: Membership?

    // What the account page should actually render.
    enum MembershipState: Equatable {
        case unknown                  // RevenueCat hasn't answered — say nothing yet
        case free                     // answered, and there is no subscription
        case subscribed(Membership)   // answered, and here are the details
    }

    var membershipState: MembershipState {
        guard tierKnown else { return .unknown }
        guard let membership else { return .free }
        return .subscribed(membership)
    }

    init() {
        Task {
            await refresh()
            await listenForChanges()
        }
    }

    // One-shot fetch (used on launch + after restore).
    // `fresh: true` goes to the network instead of RevenueCat's cache.
    //
    // WHY IT HAS TO EXIST: cancelling a subscription happens in the App Store's
    // own Settings, and nothing tells the app. customerInfoStream only fires when
    // RevenueCat itself has news — a purchase, a restore, an expiry — and a
    // cancellation is none of those. Plain customerInfo() then answers from cache,
    // so the account page went on saying "Renews automatically on the 4th" to
    // someone who had already cancelled, until the app was relaunched.
    //
    // The default stays cached: launch and sign-in call this and must not add a
    // network round trip to every cold start. Only the screen that SHOWS the
    // renewal date asks for the truth.
    func refresh(fresh: Bool = false) async {
        let info = fresh
            ? try? await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent)
            : try? await Purchases.shared.customerInfo()
        guard let info else { return }
        apply(info)
    }

    // What a restore attempt actually did. "Nothing to restore" and "we couldn't
    // reach the store" are different situations and need different words: the
    // first is final, the second is worth retrying. Collapsing both into a bare
    // Bool told a paying user on a flaky connection that they had never bought
    // anything.
    enum RestoreResult: Equatable {
        case restored          // entitlement is active again
        case expired           // the purchase EXISTS but has lapsed — renew, don't re-buy
        case nothingToRestore  // reached the store; this Apple ID has no purchase
        case failed            // couldn't reach the store — retryable
    }

    // Restore a previous purchase (e.g. new device / reinstall).
    //
    // WHAT RESTORE ACTUALLY USES — and it is NOT the Tadah account, nor Sign in
    // with Apple (which this app no longer has). A subscription is bought from
    // the App Store, so it belongs to the Apple ID in Settings → Media &
    // Purchases, and `restorePurchases` re-reads THAT receipt. It works signed
    // out, on a fresh install, with no Tadah account in existence.
    //
    // The Tadah account is the SECOND route, and it needs no button at all:
    // sign-in calls `Purchases.logIn(userID)`, so the entitlement follows the
    // account onto a new phone by itself (TadahApp does the same on every
    // launch). Restore is for the case where there is no account to sign in to.
    //
    // `accountUserID` — pass the signed-in user's id when there is one. Those
    // logIn calls are `try?`: offline they silently don't happen, and this device
    // is then still on an ANONYMOUS RevenueCat id. Restoring into that id
    // attaches the receipt to a throwaway user, and the Worker — which asks
    // RevenueCat about our account id when it checks the tier — keeps handing a
    // paying user free-tier limits. So re-identify first, then restore.
    @discardableResult
    func restore(as accountUserID: String? = nil) async -> RestoreResult {
        if let accountUserID, Purchases.shared.appUserID != accountUserID {
            _ = try? await Purchases.shared.logIn(accountUserID)
        }
        do {
            apply(try await Purchases.shared.restorePurchases())
            if isPlus { return .restored }
            // AN EXPIRED PURCHASE IS NOT "no purchase". Someone whose card failed
            // last month, tapping Restore to fix it, was told this Apple ID had
            // never bought anything — which reads as "we lost your money" and is
            // the single worst thing to say to a lapsed paying customer. The
            // entitlement is still there, just inactive, so say what's true.
            if membership != nil { return .expired }
            return .nothingToRestore
        } catch {
            return .failed
        }
    }

    // TIE THIS DEVICE TO A TADAH ACCOUNT — and bring a guest's purchase with it.
    //
    // Buying Plus never needs an account (App Review, guideline 5.1.1, 2026-09-07),
    // so a normal order of events is: buy as a guest, on RevenueCat's anonymous
    // id for this install, and sign in later for the family and multi-device
    // half of what Plus sells. `logIn` handles the common case by itself — an
    // anonymous id signing in to a BRAND-NEW account is aliased to it, and the
    // subscription comes along.
    //
    // It does NOT handle signing in to an account that already exists. Every
    // Tadah account already carries an anonymous alias from the install that
    // created it, and that is exactly the case RevenueCat documents as "no merge,
    // no transfer". The guest's subscription then stays on the old anonymous id,
    // and this phone would LOSE Plus by signing in — the worst possible reward for
    // making an account. So when the device was Plus a moment ago and the account
    // isn't, post the receipt again under the account id: with the project's
    // restore behaviour (Transfer to new App User ID, RevenueCat's default) the
    // subscription moves to the account, where the Worker's tier check can see
    // it. ⚠️ Do not switch that setting to "Keep with original App User ID" — it
    // makes this exact step fail with an error.
    func identify(as accountUserID: String) async {
        let hadPlusAsGuest = tierKnown && isPlus
        guard let result = try? await Purchases.shared.logIn(accountUserID) else { return }
        apply(result.customerInfo)
        guard hadPlusAsGuest, !isPlus else { return }
        if let restored = try? await Purchases.shared.restorePurchases() { apply(restored) }
    }

    // THE PHONE AND THE SERVER DISAGREE ABOUT WHO IS PAYING — fix the phone's side.
    //
    // This device decides Plus from the App Store receipt in front of it. The
    // Worker decides it by asking RevenueCat about the TADAH ACCOUNT's id
    // (GET /v1/subscribers/<userID>, fail-closed). Those are the same question
    // only while a `logIn` has actually landed — and every logIn in this app is
    // `try?`, so an offline sign-in, an app killed mid-sign-in, or a
    // subscription bought as a guest can leave the purchase filed under an id
    // the Worker never asks about. The app then shows Plus while the server
    // answers "Tadah Plus is needed", which is the most confusing pair of
    // answers we can hand a paying customer.
    //
    // Re-file the purchase under the account id: identify, then post the receipt
    // again. With the project's restore behaviour (Transfer to new App User ID)
    // that MOVES the subscription onto the account — exactly the id the Worker
    // reads. ⚠️ Same dependency as `identify`: "Keep with original App User ID"
    // makes this step fail instead of fixing anything.
    //
    // Returns whether RevenueCat now reports Plus FOR THE ACCOUNT ID, i.e.
    // whether the thing the server just refused is worth trying again. `false`
    // is real information rather than a failure: there genuinely is no active
    // subscription on this account, so the paywall message is TRUE.
    @discardableResult
    func reattachToAccount(_ accountUserID: String) async -> Bool {
        #if DEBUG
        // Print BOTH ids EVERY time, not only on a mismatch. "They already match"
        // is the answer that rules out this entire class of bug and points at the
        // subscription itself instead (a lapsed sandbox purchase, a renewal in its
        // payment grace period) — which is worth one console line to learn.
        print("[PlusStore] server refused Plus · RevenueCat id \(Purchases.shared.appUserID) · Tadah account \(accountUserID)")
        #endif
        if Purchases.shared.appUserID != accountUserID {
            guard let result = try? await Purchases.shared.logIn(accountUserID) else { return false }
            apply(result.customerInfo)
        }
        // Never post a receipt into an anonymous id: attaching the purchase to a
        // throwaway user is what produced this mismatch in the first place.
        guard Purchases.shared.appUserID == accountUserID else { return false }
        // Restore even when `isPlus` already looks true — that flag can be this
        // device's cached answer about a DIFFERENT id, which is precisely the
        // case where the server is right and the phone is wrong.
        // ⚠️ A THROWN RESTORE MUST NOT READ AS SUCCESS. `try?` + `return isPlus`
        // returned the value this object was ALREADY carrying — `true`, since the
        // phone thinks it's Plus — so a restore that errored (which is exactly
        // what "Keep with original App User ID" does to this call) reported that
        // the receipt had been re-filed when nothing had moved, and the retry
        // walked into the same refusal.
        let restored = try? await Purchases.shared.restorePurchases()
        if let restored { apply(restored) }
        // ⚠️ DON'T LEAVE A CLAIM ON SCREEN THAT THE SERVER HAS JUST REFUSED.
        //
        // Reaching here means the Worker said this account is not Plus and the
        // receipt did not change its mind — yet `isPlus` may still be `true`,
        // either cached from before the subscription lapsed or left untouched
        // because the restore threw. Profile then goes on saying "Tadah Plus" to
        // someone every server check treats as free, which is precisely how a
        // whole evening gets spent debugging the wrong half of the system.
        //
        // `fresh: true` on purpose: the default read answers from RevenueCat's
        // cache, and the cache is the thing under suspicion. This is the one
        // moment we have PROOF the phone and the server disagree, so it is worth
        // the round trip — it costs nothing on the normal path, which never gets
        // here at all.
        if restored == nil || !isPlus { await refresh(fresh: true) }
        #if DEBUG
        print("[PlusStore] re-filed under \(accountUserID) · restore \(restored == nil ? "FAILED" : "ok") · isPlus = \(isPlus)")
        #endif
        return restored != nil && isPlus
    }

    // Live updates: RevenueCat pushes a new CustomerInfo whenever entitlements
    // change (purchase, renewal, expiry), so the UI reacts on its own.
    private func listenForChanges() async {
        for await info in Purchases.shared.customerInfoStream {
            apply(info)
        }
    }

    // FORGET THE PERSON WHO JUST SIGNED OUT.
    //
    // Purchases.logOut() switches RevenueCat to a fresh anonymous user, but this
    // object keeps whatever the last CustomerInfo said until the stream happens to
    // emit again — and nothing guarantees it does promptly. The Profile page then
    // shows the DEPARTED user's plan and renewal date, and offers "Manage in the
    // App Store" (which only appears when `membership != nil`), to whoever is
    // holding the phone next.
    //
    // Reset to "not known yet" rather than to "free": we genuinely don't know yet.
    // `.unknown` renders as "One moment while we check with the App Store" instead
    // of asserting a free plan we haven't verified, and `paidFeaturesUnlocked`
    // stays permissive while tierKnown is false, so a signed-out Plus buyer is not
    // briefly downgraded mid-session.
    //
    // The truth comes straight back: if this Apple ID really is entitled, the
    // stream (or Restore) re-applies it within moments.
    func forgetSignedOutUser() {
        membership = nil
        isPlus = false
        tierKnown = false
    }

    private func apply(_ info: CustomerInfo) {
        let entitlement = info.entitlements[Self.entitlementID]
        isPlus = entitlement?.isActive == true
        // Kept even once it has EXPIRED, so the account page can say "ended on
        // the 4th" instead of silently going blank — someone whose card failed
        // needs to see what happened, not an empty space where their plan was.
        membership = entitlement.map {
            Membership(isActive: $0.isActive,
                       willRenew: $0.willRenew,
                       expirationDate: $0.expirationDate,
                       productIdentifier: $0.productIdentifier,
                       hasBillingProblem: $0.billingIssueDetectedAt != nil)
        }
        tierKnown = true
    }
}
