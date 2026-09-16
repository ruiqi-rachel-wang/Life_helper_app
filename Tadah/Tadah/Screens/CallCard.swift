//  CallCard.swift
//
//  "Tadah can make this call" — the one place the calling feature is offered.
//
//  It lives on REVIEW, between the steps card and the notes card, because that
//  is the moment attention is highest: the user has just scanned a letter and is
//  reading what it means. A to-do the user never reopens would never surface it.
//
//  ONE CARD, THREE STATES, IN PLACE. It morphs — offer → calling → result —
//  rather than pushing a screen and coming back, so the answer appears exactly
//  where the question was asked. Only the confirm step is a separate page.
//
//  The card is deliberately dumb: it owns no networking. `CallController` holds
//  the state machine so the same card can later sit on Detail with the saved
//  to-do's call on it.
//

import SwiftUI

// ── State ───────────────────────────────────────────────────────────────────

@MainActor @Observable
final class CallController {
    enum Phase: Equatable {
        case offer
        case calling(since: Date)
        case finished(CallRecord)
        case failed(String)
    }

    var phase: Phase = .offer
    var actionID: String?
    /// Set when the Worker is in dry-run, so a call that never dialled can't be
    /// mistaken for a real one during testing.
    var wasDryRun = false

    private var watcher: Task<Void, Never>?

    var isBusy: Bool { if case .calling = phase { return true }; return false }

    /// Start a call and watch it to completion.
    ///
    /// `onFinished` fires once with the terminal status, so the caller can write
    /// the result onto the to-do. It is NOT called when the watch times out —
    /// the call isn't lost then, we simply stopped looking, and the answer
    /// arrives with the next sync.
    ///
    /// `recoverPlus` is the one second chance this feature gets: see `place`.
    func start(_ request: ActionsService.CallRequest,
               itemID: UUID?,
               business: String? = nil,
               recoverPlus: (@MainActor () async -> Bool)? = nil,
               onFinished: @escaping @MainActor (CallRecord) -> Void) {
        guard !isBusy else { return }
        phase = .calling(since: Date())
        watcher?.cancel()
        watcher = Task { [weak self] in
            do {
                let placed = try await Self.place(request, recoverPlus: recoverPlus)
                guard let self else { return }
                self.actionID = placed.actionID
                self.wasDryRun = placed.dryRun
                if let itemID { PendingCall.remember(placed.actionID, business: business, for: itemID) }

                let final = try await ActionsService.awaitResult(placed.actionID)
                guard !Task.isCancelled else { return }
                if final.isFinished {
                    let record = CallRecord(final, business: business)
                    self.phase = .finished(record)
                    if let itemID { PendingCall.forget(itemID) }
                    onFinished(record)
                }
                // Not finished = we stopped watching, not a failure. Leave the
                // card in .calling; the result lands on the to-do via sync.
            } catch {
                guard let self, !Task.isCancelled else { return }
                let message = (error as? ActionsService.ActionError)?.errorDescription
                    ?? String(localized: "Tadah couldn't place the call. Please try again.")
                self.phase = .failed(message)
            }
        }
    }

    /// Place the call — and don't believe a "Plus required" the phone disagrees
    /// with until it has checked.
    ///
    /// The Worker asks RevenueCat about the ACCOUNT's id and fails closed; this
    /// device reads the receipt in front of it. When a `logIn` never landed
    /// (offline sign-in, a subscription bought as a guest) the purchase sits
    /// under an id the Worker never asks about, and a subscriber is told to buy
    /// what they already own. `recoverPlus` re-files it and we try once more.
    ///
    /// ONE retry, never a loop. The recovery is idempotent, so a second pass
    /// could only reach the same answer more slowly — and this is the code path
    /// that spends money on a phone line, which is the last place to put
    /// automatic retries. If the recovery finds no subscription, the ORIGINAL
    /// error is rethrown: the user then sees the paywall message, and it's true.
    private static func place(_ request: ActionsService.CallRequest,
                              recoverPlus: (@MainActor () async -> Bool)?) async throws -> ActionsService.Placed {
        do {
            return try await ActionsService.placeCall(request)
        } catch let error as ActionsService.ActionError where error.needsPlus {
            guard let recoverPlus, await recoverPlus() else { throw error }
            return try await ActionsService.placeCall(request)
        }
    }

    /// Pick up a call that was already running when the screen opened.
    func resume(actionID: String, itemID: UUID?,
                business: String? = nil,
                onFinished: @escaping @MainActor (CallRecord) -> Void) {
        guard !isBusy else { return }
        self.actionID = actionID
        phase = .calling(since: Date())
        watcher?.cancel()
        watcher = Task { [weak self] in
            let final = try? await ActionsService.awaitResult(actionID)
            guard let self, !Task.isCancelled, let final else { return }
            if final.isFinished {
                let record = CallRecord(final, business: business)
                self.phase = .finished(record)
                if let itemID { PendingCall.forget(itemID) }
                onFinished(record)
            }
        }
    }

    func stopWatching() { watcher?.cancel(); watcher = nil }
}

// ── The wire answer → what we keep ──────────────────────────────────────────

extension CallRecord {
    /// Flatten the provider's answer into the handful of fields the card shows.
    ///
    /// Deliberately lossy: the transcript and confidence score stay on the
    /// server. What a person needs off a finished call is what was said, what
    /// was agreed, and what happens next — keeping more would mean storing a
    /// recording of someone's phone call on the device.
    init(_ status: ActionsService.ActionStatus, business: String?) {
        let structured = status.result?.structured
        self.init(business: business,
                  endedAt: Date.now,
                  didFail: status.status != "completed",
                  detail: structured?.detail,
                  summary: status.result?.summary,
                  agreed: structured?.agreed,
                  nextStep: structured?.nextStep,
                  needsUserAction: structured?.needsUserAction == "yes")
    }
}

// ── The card ────────────────────────────────────────────────────────────────

struct CallCard: View {
    let offer: CallOffer
    @Bindable var controller: CallController
    /// Tapped "Yes, call for me" — the owner opens the confirm page.
    var onSetUp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch controller.phase {
            case .offer:                 offerBody
            case .calling(let since):    callingBody(since: since)
            case .finished(let record):  CallResultCard(record: record)
            case .failed(let message):   failedBody(message)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: controller.phase)
    }

    // 1 ── Offer
    private var offerBody: some View {
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
    }

    // 2 ── Calling
    private func callingBody(since: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(offer.business.map { String(localized: "Calling \($0)…") }
                     ?? String(localized: "Calling…"))
                    .font(.cardTitle).foregroundStyle(Color.ink)
                Spacer(minLength: 8)
                // A live timer, so a call that has gone quiet still looks alive.
                Text(since, style: .timer)
                    .font(.eyebrow).foregroundStyle(Color.faint)
                    .monospacedDigit()
            }
            // The single most useful sentence here: the call does not depend on
            // this screen staying open.
            Text("You can close this — the answer will be saved to this to-do.")
                .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if controller.wasDryRun {
                Text("TEST MODE — no call was actually placed")
                    .font(.eyebrow).foregroundStyle(Color.warn)
            }
        }
    }

    // 4 ── Failed to start
    private func failedBody(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow("CALL DIDN'T GO THROUGH", icon: "exclamationmark.triangle.fill", tint: Color.warn)
            Text(message)
                .font(.body14).foregroundStyle(Color.ink).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: { controller.phase = .offer }) {
                Text("Try again").font(.body14.weight(.semibold)).foregroundStyle(Color.accent)
            }
            .buttonStyle(.plain)
        }
    }

    // ── bits ────────────────────────────────────────────────────────────────

}

// ── The result, on its own ──────────────────────────────────────────────────
//
// Split out of CallCard so the SAME view renders a call that just ended on
// Review and one read back from `CallHistory` on a saved to-do. Two copies of
// this layout would drift, and "the card looks different depending on where you
// opened it" is exactly the kind of drift nobody notices until it ships.
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
