//  UsageDataPrimerView.swift
//
//  The first-launch ASK for usage statistics. Same shape as the notification
//  primer, and shown right after it.
//
//  WHY THIS EXISTS AT ALL, given the setting already lives in Profile → Privacy:
//  a setting nobody is ever pointed at is not really a choice, it's a hiding
//  place. Usage stats were flipped to opt-in on 2026-08-17 for good reasons (see
//  Metrics), and the honest way to run an opt-in is to ask the question out loud
//  once, with a real "no" next to the "yes" — not to leave it switched off in a
//  menu and call that a decision.
//
//  WHAT IT MUST NOT BE. No pre-ticked box, no dark pattern where "No thanks" is
//  a grey whisper under a huge green button, and no consequence for declining:
//  every part of Tadah works exactly the same either way, and the copy says so.
//  Under GDPR consent has to be freely given and as easy to refuse as to accept,
//  and Apple expects the same before any usage data is collected.
//
//  The answer is stored by Metrics.recordUsageConsent — the SAME UserDefaults key
//  the Profile toggle writes, so switching it later just overwrites this, and a
//  "no" here is a real answer that is never re-asked.
//

import SwiftUI

struct UsageDataPrimerView: View {
    // true = share, false = don't. The host records it and moves on.
    var onDecide: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            ZStack {
                Circle().fill(Color.bg).frame(width: 96, height: 96)
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 36)).foregroundStyle(Color.accent)
            }
            .padding(.bottom, 24)

            Text("Help improve Tadah?")
                .font(.serifModal).foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)

            // Says exactly what is sent and what isn't. "Anonymous" is
            // deliberately not claimed anywhere: each event carries a random id
            // that stays the same for this install, which makes it pseudonymous,
            // and the privacy policy says the same thing in the same words.
            Text("Tadah can send a little usage data — which features you use, and whether the to-dos you add get done. Never your documents, your to-dos, your name, or your email.\n\nIt's tied to a random ID for this install, not to you. Everything works the same if you say no, and you can change your mind anytime in Profile → Privacy.")
                .font(.body14).foregroundStyle(Color.faded)
                .multilineTextAlignment(.center).lineSpacing(3)
                .padding(.horizontal, 28)

            Spacer()

            Button { onDecide(true) } label: {
                Text("Share usage data")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.paper)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.ink))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)

            // A real refusal, in the same place and the same weight as the
            // primer's "Not now" — one tap, no maze.
            Button { onDecide(false) } label: {
                Text("No thanks")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(Color.faded)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paper.ignoresSafeArea())
        .interactiveDismissDisabled()   // an unanswered swipe-away is not consent
    }
}

#Preview {
    UsageDataPrimerView(onDecide: { _ in })
}
