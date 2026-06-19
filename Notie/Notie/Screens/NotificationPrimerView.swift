//  NotificationPrimerView.swift
//
//  First-launch explainer shown BEFORE the iOS notification prompt. Plaino is
//  built around reminding people before a bill / appointment / form is due, so
//  we tell the user WHY it matters first (a bare system prompt with no context
//  gets dismissed, and iOS only lets you ask once). "Turn on reminders" then
//  triggers the real system permission sheet.
//

import SwiftUI

struct NotificationPrimerView: View {
    // Called after the user decides (allow or "not now") so the host can dismiss
    // and remember we've asked.
    var onDecide: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            ZStack {
                Circle().fill(Color.bg).frame(width: 96, height: 96)
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 40)).foregroundStyle(Color.accent)
            }
            .padding(.bottom, 24)

            Text("Don't miss a deadline")
                .font(.serifModal).foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)

            Text("Plaino works by reminding you before a bill, appointment, or form is due. Turn on notifications so those reminders can actually reach you — without them, Plaino can't nudge you in time.")
                .font(.body14).foregroundStyle(Color.faded)
                .multilineTextAlignment(.center).lineSpacing(3)
                .padding(.horizontal, 28)

            Spacer()

            Button {
                Task {
                    await ReminderScheduler.shared.requestAuthorization()
                    onDecide()
                }
            } label: {
                Text("Turn on reminders")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.paper)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.ink))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)

            Button { onDecide() } label: {
                Text("Not now")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(Color.faded)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paper.ignoresSafeArea())
        .interactiveDismissDisabled()   // make it a deliberate choice, not a swipe-away
    }
}

#Preview {
    NotificationPrimerView(onDecide: {})
}
