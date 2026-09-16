//  CallCard.swift
//
//  Where a call shows up, in three pieces:
//    • CallCard — the OFFER, on Review: "Tadah can make this call".
//    • CallStatusCard — the CALL, on the to-do: calling, then the answer, or
//      why it didn't go through.
//    • CallResultCard — the answer alone, which the status card shows.
//
//  "Call now" takes the user from Review straight to the to-do, so everything
//  after the offer happens on the to-do page. None of these views own any
//  networking: CallCenter places and watches every call, so leaving a screen
//  can never cancel one.
//

import SwiftUI

// ── The wire answer → what we keep ──────────────────────────────────────────

extension CallRecord {
    /// Flatten the provider's answer into the handful of fields the card shows.
    ///
    /// Deliberately lossy: the transcript and confidence score stay on the
    /// server. What a person needs off a finished call is what was said, what
    /// was agreed, and what happens next.
    init(_ status: ActionsService.ActionStatus, business: String?) {
        let structured = status.result?.structured
        self.init(business: business,
                  endedAt: status.endedDate ?? Date.now,
                  didFail: status.status != "completed",
                  detail: structured?.detail,
                  summary: status.result?.summary,
                  agreed: structured?.agreed,
                  nextStep: structured?.nextStep,
                  needsUserAction: structured?.needsUserAction == "yes")
    }
}

// ── The offer (Review) ──────────────────────────────────────────────────────

struct CallCard: View {
    let offer: CallOffer
    /// Tapped "Yes, call for me". The owner checks sign-in, Plus and a verified
    /// email first, then opens the confirm page.
    var onSetUp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow("TADAH CAN MAKE THIS CALL", icon: "phone.fill")

            if let business = offer.business, !business.isEmpty {
                Text("\(business) · \(offer.phone)")
                    .font(.cardTitle).foregroundStyle(Color.ink)
            } else {
                Text(offer.phone).font(.cardTitle).foregroundStyle(Color.ink)
            }

            // The suggested goal, quoted so it reads as "what Tadah would ask",
            // not as another instruction to the user.
            Text(offer.goal)
                .font(.body14).foregroundStyle(Color.faded).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onSetUp) {
                Text("Yes, call for me")
                    .font(.cardTitle).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens a page to check the number and what Tadah will ask, before anything is dialled."))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// ── The call (to-do page) ───────────────────────────────────────────────────

struct CallStatusCard: View {
    let phase: CallCenter.Phase
    /// Decides whether a "verify your email" refusal still needs verifying, or
    /// has been fixed since and can simply be tried again.
    let emailVerified: Bool
    var onTryAgain: (CallCenter.Retry) -> Void
    var onVerify: () -> Void
    var onSeePlus: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch phase {
            case .calling(let since, let business, let dryRun):
                callingBody(since: since, business: business, dryRun: dryRun)
            case .finished(let record):
                CallResultCard(record: record)
            case .refused(let refusal):
                refusedBody(refusal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: phase)
    }

    private func callingBody(since: Date, business: String?, dryRun: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(business.map { String(localized: "Calling \($0)…") }
                     ?? String(localized: "Calling…"))
                    .font(.cardTitle).foregroundStyle(Color.ink)
                Spacer(minLength: 8)
                // A live timer, so a call that has gone quiet still looks alive.
                Text(since, style: .timer)
                    .font(.eyebrow).foregroundStyle(Color.faint)
                    .monospacedDigit()
            }
            // True now that the app, not a screen, owns the call: closing this
            // page or the app loses nothing, and the answer is written here the
            // next time Tadah is open.
            Text("You can close this — the answer will be saved to this to-do.")
                .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if dryRun {
                Text("TEST MODE — no call was actually placed")
                    .font(.eyebrow).foregroundStyle(Color.warn)
            }
        }
    }

    private func refusedBody(_ refusal: CallCenter.Refusal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow("CALL DIDN'T GO THROUGH", icon: "exclamationmark.triangle.fill", tint: Color.warn)
            Text(refusal.message)
                .font(.body14).foregroundStyle(Color.ink).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            // One button, and only one that can actually work. "Try again" on a
            // used-up allowance or a signed-out phone would just fail again.
            switch refusal.error {
            case .emailUnverified where !emailVerified:
                action("Verify my email", onVerify)
            case .plusRequired:
                action("See Tadah Plus", onSeePlus)
            case .noSession, .notConfigured, .notInvited, .quotaExceeded:
                EmptyView()
            default:
                action("Try again") { onTryAgain(refusal.retry) }
            }
        }
    }

    private func action(_ title: LocalizedStringKey, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title).font(.body14.weight(.semibold)).foregroundStyle(Color.accent)
        }
        .buttonStyle(.plain)
    }
}

// ── The result, on its own ──────────────────────────────────────────────────
//
// Split out so the SAME view renders a call that ends while the to-do is open
// and one read back from `CallHistory` days later. Two copies of this layout
// would drift, and "the card looks different depending on when you opened it"
// is exactly the kind of drift nobody notices until it ships.
struct CallResultCard: View {
    let record: CallRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow(record.didFail ? "CALL DIDN'T GO THROUGH" : "CALL ENDED",
                    icon: record.didFail ? "phone.down.fill" : "checkmark.circle.fill",
                    tint: record.didFail ? Color.warn : Color.ok)

            // Who and when. The note this card replaced opened with exactly this
            // ("Tadah called Con Edison · 12 Sep"), and dropping it left an
            // answer with no attribution sitting on a to-do days later.
            // ONE catalog key, not two. A second "Tadah called · %@" variant for
            // the no-name case would have been a brand-new English literal, and
            // an untranslated one renders in English inside a Chinese app. The
            // note this card replaced already had the answer: fall back to the
            // localized word for the other party, which the catalog carries.
            Text("Tadah called \(record.business ?? String(localized: "them")) · \(record.endedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.subline).foregroundStyle(Color.faded)
                .fixedSize(horizontal: false, vertical: true)

            // The sentence a person can act on. `detail` comes back in the
            // user's own language — the call was in English, the answer is not.
            if let detail = record.detail, !detail.isEmpty {
                Text(detail)
                    .font(.body14).foregroundStyle(Color.ink).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let summary = record.summary, !summary.isEmpty {
                Text(summary)
                    .font(.body14).foregroundStyle(Color.ink).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else if record.didFail {
                Text("Nobody could be reached. Nothing was agreed.")
                    .font(.body14).foregroundStyle(Color.faded)
            }

            if let agreed = record.agreed, !agreed.isEmpty {
                labelled("AGREED", agreed)
            }
            if let next = record.nextStep, !next.isEmpty {
                labelled("NEXT", next)
            }
            if record.needsUserAction {
                Text("This still needs you — Tadah couldn't finish it on the call.")
                    .font(.subline).foregroundStyle(Color.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Shared by both cards, so the eyebrow and the labelled rows are identical
// wherever a call is shown.
fileprivate func eyebrow(_ key: LocalizedStringKey, icon: String, tint: Color = Color.accent) -> some View {
    HStack(spacing: 6) {
        Image(systemName: icon).font(.system(size: 12)).foregroundStyle(tint)
        Text(key).font(.eyebrow).foregroundStyle(tint)
    }
}

fileprivate func labelled(_ key: LocalizedStringKey, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(key).font(.eyebrow).foregroundStyle(Color.faint)
        Text(value)
            .font(.body14).foregroundStyle(Color.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}
