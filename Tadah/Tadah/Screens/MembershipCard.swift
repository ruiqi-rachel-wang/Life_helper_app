//  MembershipCard.swift
//
//  "Am I paying for this, and when does it renew?" — the question people open
//  the account page to answer, and which the app had no answer for at all.
//
//  WHAT AN APP CAN AND CANNOT DO ABOUT AN APP STORE SUBSCRIPTION. Apple owns
//  cancellation, plan changes and payment details; an app may not cancel a
//  subscription itself, and there is no pause on the App Store (that's Google
//  Play). So this shows everything we genuinely know and hands off to Apple's own
//  screen for the rest. A fake "Cancel" that merely deep-links would be worse
//  than a button that says where it goes.
//
//  ⚠️ USED FROM TWO PLACES, and that is the point. It lives in Account Details
//  for signed-in users AND in the Profile card for signed-out ones, because you
//  can buy Plus without ever making an account — and until 2026-08-17 those
//  buyers had no route to their own subscription anywhere in the app.
//

import SwiftUI
import StoreKit
import UIKit

struct MembershipCard: View {
    @Environment(PlusStore.self) private var plus
    // Restore re-identifies this device to RevenueCat before asking the App
    // Store, and "nothing found" says something different to a guest.
    @Environment(AccountStore.self) private var account
    @Environment(\.openURL) private var openURL
    @State private var isRestoring = false
    @State private var restoreMessage: String?

    var body: some View {
        membershipCard
            // Ask the App Store directly, not RevenueCat's cache. This is the one
            // screen that states a renewal date, and a cancellation made in the
            // App Store's Settings reaches the app no other way — there is no
            // callback for it, so without this the card keeps promising a renewal
            // that is not going to happen.
            .task { await plus.refresh(fresh: true) }
    }

    //
    // WHAT YOU CAN AND CANNOT DO ABOUT A SUBSCRIPTION FROM INSIDE AN APP.
    //
    // Apple owns cancellation, plan changes and payment details — an app may not
    // cancel an App Store subscription itself, and there is no pause on the App
    // Store at all (that is a Google Play feature). So the honest design is: show
    // everything we actually know, and hand off to Apple's own screen for the
    // rest. A fake "Cancel" that just deep-links is worse than a button that says
    // where it goes.
    //
    // Shown to everyone, including free users, because "am I paying for this, and
    // when does it renew?" is exactly the question people open this page to answer
    // — and finding nothing is what makes them email support.
    @ViewBuilder
    private var membershipCard: some View {
        card {
            VStack(alignment: .leading, spacing: 0) {
                fieldLabel("MEMBERSHIP")

                HStack(spacing: 12) {
                    Image(systemName: plus.isPlus ? "star.circle.fill" : "person.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(plus.isPlus ? Color.accent : Color.faded)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(planTitle).font(.body14).foregroundStyle(Color.ink)
                        Text(planDetail).font(.subline).foregroundStyle(planDetailColor).lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                }
                .padding(.vertical, 12)

                if plus.membership != nil {
                    divider
                    // Goes to Apple's subscription screen, which is where renewing,
                    // switching monthly/yearly, changing the card and cancelling
                    // all actually happen. Named for where it goes.
                    Button { openAppleSubscriptions() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.up.forward.app").font(.system(size: 15))
                                .foregroundStyle(Color.accent).frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Manage in the App Store").font(.body14).foregroundStyle(Color.ink)
                                Text("Cancel, switch between monthly and yearly, or update your payment method. Apple handles subscriptions, so this opens their settings.")
                                    .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                divider
                // SAYS WHERE IT LOOKS. Plus is bought from the App Store, so a
                // restore reads the receipt of the Apple ID this phone is signed
                // in to — the Tadah account has nothing to do with it. Without
                // that sentence the button looks broken to anyone who expected
                // it to find a purchase made under a different Apple ID.
                Button { Task { await restore() } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 15))
                            .foregroundStyle(Color.accent).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Restore purchases").font(.body14).foregroundStyle(Color.ink)
                            Text("Brings back a subscription bought with the Apple ID signed in to this phone.")
                                .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if isRestoring { ProgressView().controlSize(.small) }
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isRestoring)

                if let restoreMessage {
                    Text(restoreMessage)
                        .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 12)
                }
            }
        }
    }

    private var planTitle: String {
        switch plus.membershipState {
        case .unknown:
            // NOT "Free plan". Before RevenueCat answers we genuinely don't know,
            // and guessing "free" tells a paying subscriber they aren't one.
            return String(localized: "Checking your membership…")
        case .free:
            return String(localized: "Free plan")
        case .subscribed(let m):
            guard m.isActive else { return String(localized: "Tadah Plus") }
            return m.isYearly ? String(localized: "Tadah Plus · Yearly")
                              : String(localized: "Tadah Plus · Monthly")
        }
    }

    // The line people actually came for: when does money move, or when does this
    // stop working. Each state says the DATE, because "active" alone answers
    // nothing.
    private var planDetail: String {
        let m: PlusStore.Membership
        switch plus.membershipState {
        case .unknown:
            return String(localized: "One moment while we check with the App Store.")
        case .free:
            return String(localized: "You're on the free plan. Tadah Plus adds family lists, more scans, and more devices.")
        case .subscribed(let found):
            m = found
        }
        let when = m.expirationDate.map { Self.dateText($0) }
        if m.hasBillingProblem {
            return String(localized: "There's a problem with your payment. Update your payment method in the App Store to keep Tadah Plus.")
        }
        if !m.isActive {
            return when.map { String(localized: "Your Plus membership ended on \($0).") }
                ?? String(localized: "Your Plus membership has ended.")
        }
        if m.willRenew {
            return when.map { String(localized: "Renews automatically on \($0).") }
                ?? String(localized: "Renews automatically.")
        }
        // Cancelled but still paid up — the most confusing state, so it says both
        // that it is ending AND that it still works until then.
        return when.map { String(localized: "Cancelled — you keep Tadah Plus until \($0), then it won't renew.") }
            ?? String(localized: "Cancelled — it won't renew.")
    }

    private var planDetailColor: Color {
        guard case .subscribed(let m) = plus.membershipState else { return Color.faded }
        if m.hasBillingProblem { return Color.bad }
        if !m.isActive { return Color.warn }
        return Color.faded
    }

    private static func dateText(_ d: Date) -> String {
        d.formatted(.dateTime.day().month(.wide).year())
    }

    private func openAppleSubscriptions() { Self.openAppleSubscriptions(openURL) }

    // Static so the account-deletion dialog can offer the same hand-off without a
    // second copy of the fallback logic.
    static func openAppleSubscriptions(_ openURL: OpenURLAction) {
        let fallback = URL(string: "https://apps.apple.com/account/subscriptions")
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else {
            if let fallback { openURL(fallback) }
            return
        }
        // `try?` swallowed the throw, so a failing sheet left the button doing
        // NOTHING — the worst outcome for the one control that leads to
        // cancelling. Fall through to the App Store URL instead.
        Task { @MainActor in
            do { try await AppStore.showManageSubscriptions(in: scene) }
            catch { if let fallback { openURL(fallback) } }
        }
    }

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        switch await plus.restore(as: account.account?.userID) {
        case .restored:
            restoreMessage = String(localized: "Your Tadah Plus membership is back on this phone.")
        case .expired:
            restoreMessage = String(localized: "Your previous Tadah Plus subscription has expired. You can start it again from the Tadah Plus screen.")
        case .nothingToRestore:
            restoreMessage = account.isSignedIn
                ? String(localized: "We couldn't find a Tadah Plus purchase on your account, or on the Apple ID signed in to this phone. If you bought it with a different Apple ID, switch to that one in Settings and try again.")
                : String(localized: "We couldn't find a purchase on the Apple ID signed in to this phone. If you bought Tadah Plus while signed in to a Tadah account, sign in to that account instead — your membership comes back with it.")
        case .failed:
            restoreMessage = String(localized: "We couldn't reach the App Store. Please check your connection and try again.")
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.hair).frame(height: 1)
    }

    private func fieldLabel(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded).padding(.bottom, 6)
    }

    private func card<C: View>(@ViewBuilder _ inner: () -> C) -> some View {
        inner()
            .padding(16)
            .background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }
}
