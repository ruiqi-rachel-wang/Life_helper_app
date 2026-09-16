//  CallWatcher.swift
//
//  Makes sure a finished call's answer is never lost, whatever the user does
//  with the app while it runs.
//
//  WHY THIS EXISTS. A call was watched by the Review screen, and only by the
//  Review screen: `ReviewView.onDisappear` cancelled the watch, so leaving the
//  page threw away the only thing that would have written the answer down. The
//  card meanwhile promised "You can close this — the answer will be saved to
//  this to-do", which was false. And nothing else could cover for it: the Worker
//  keeps the result in its own `actions` table and never writes to `tasks` (task
//  payloads are opaque to it by design), so "it arrives with the next sync" was
//  not true either. A real call takes minutes. People put the phone down.
//
//  So the watch belongs to the APP, not to a screen. `PendingCall` already
//  recorded which call belongs to which to-do; nothing ever read it back. This
//  reads it back.
//
//  ⚠️ IT ONLY EVER READS. `ActionsService.status` asks the Worker how a call
//  we already paid for is going. Nothing here can start, re-start or bill a
//  call — the one thing this feature must never do by itself is dial.
//

import Foundation

@MainActor
enum CallWatcher {

    /// Calls being watched right now, so a relaunch-then-foreground (or Review
    /// watching the same call live) can't put two pollers on one action.
    private static var watching: Set<String> = []

    /// Pick up every call this phone started and hasn't seen the end of.
    ///
    /// Safe to call as often as you like: already-watched calls are skipped, and
    /// a call that has already been written down is no longer in `PendingCall`.
    static func resumeAll() {
        for (itemID, call) in PendingCall.all {
            watch(call, for: itemID)
        }
    }

    /// Watch one call to its end and write the answer beside its to-do.
    static func watch(_ call: PendingCall.InFlight, for itemID: UUID) {
        guard !watching.contains(call.actionID) else { return }
        watching.insert(call.actionID)

        Task {
            defer { watching.remove(call.actionID) }

            // `awaitResult` gives up watching after its timeout WITHOUT throwing
            // and hands back the last thing it saw. That is not a failure and
            // must not clear the breadcrumb — the call is still running, and the
            // next launch picks it up again.
            guard let final = try? await ActionsService.awaitResult(call.actionID),
                  final.isFinished
            else { return }

            CallHistory.save(CallRecord(final, business: call.business), for: itemID)
            PendingCall.forget(itemID)
        }
    }
}
