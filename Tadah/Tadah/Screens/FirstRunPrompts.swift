//  FirstRunPrompts.swift
//
//  The one-time questions Tadah asks on a fresh install, played as PAGES INSIDE
//  A SINGLE SHEET rather than as a queue of sheets.
//
//  Why one sheet: dismissing a sheet and presenting the next one in the same
//  breath is the classic way to get a half-animated, occasionally stuck modal in
//  SwiftUI, and the user sees the app blink at them. Here the sheet is presented
//  once and simply swaps its page, so the second question slides in with nothing
//  to race.
//
//  Which questions appear is decided by the caller (RootTabView) and passed in —
//  a step is included only if it hasn't been answered yet, so a returning user
//  who already made both choices sees nothing at all.
//
//  ⚠️ NOT THE PLACE FOR THE AI CONSENT. That one is asked at the first scan, on
//  purpose (see AIConsent): it is the question with real consequences, and
//  burying it in a first-launch stack is exactly how it would get tapped through
//  along with everything else.
//

import SwiftUI

struct FirstRunPrompts: View {
    enum Step: Equatable {
        case notifications   // explain reminders, then trigger the iOS prompt
        case usageData       // ask before any usage statistics are uploaded
    }

    let steps: [Step]
    // Called once every step has been answered — the host dismisses the sheet.
    var onFinish: () -> Void

    @State private var index = 0

    var body: some View {
        Group {
            // Bounds-checked rather than clamped: an empty `steps` (the caller
            // shouldn't present this at all in that case) must not crash the
            // first launch of the app — it just finishes immediately.
            if index < steps.count {
                switch steps[index] {
                case .notifications:
                    NotificationPrimerView { advance() }
                case .usageData:
                    UsageDataPrimerView { granted in
                        Metrics.recordUsageConsent(granted)
                        // A "yes" here is retroactive: events already logged
                        // locally (this launch, and any from before the answer)
                        // become sendable, and flush is what actually sends them.
                        // Without this they'd sit on the device until some later
                        // trigger.
                        if granted { Metrics.flush() }
                        advance()
                    }
                }
            } else {
                Color.paper.ignoresSafeArea().onAppear { onFinish() }
            }
        }
        .transition(.opacity)
    }

    private func advance() {
        if index + 1 < steps.count {
            withAnimation(.easeInOut(duration: 0.2)) { index += 1 }
        } else {
            onFinish()
        }
    }
}

#Preview {
    FirstRunPrompts(steps: [.notifications, .usageData], onFinish: {})
}
