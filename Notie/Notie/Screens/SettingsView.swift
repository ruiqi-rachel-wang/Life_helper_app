//  SettingsView.swift
//
//  Language, reminder timing, privacy, notifications, export.
//
//  Mostly a stub until Week 8. For now it carries a DEBUG-only button to
//  fire a test reminder in 5 seconds, so the notification banner + action
//  buttons can be verified without waiting for a real due date.
//

import SwiftUI
import UserNotifications

struct SettingsView: View {
    @State private var notifyStatus = "Checking…"

    var body: some View {
        ZStack(alignment: .top) {
            Color.paper.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Text("PREFERENCES")
                    .font(.eyebrow).tracking(1.4).foregroundStyle(Color.faded)
                Text("Settings")
                    .font(.serifTitle).tracking(-0.8).foregroundStyle(Color.ink)
                    .padding(.top, 4)

                // Notifications status row.
                VStack(alignment: .leading, spacing: 6) {
                    Text("NOTIFICATIONS").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                    Text(notifyStatus).font(.subline).foregroundStyle(Color.ink)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
                .padding(.top, 18)

                #if DEBUG
                Button {
                    ReminderScheduler.shared.fireTestReminder()
                } label: {
                    Text("Send a test reminder (5s)")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.paper)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.ink))
                }
                .buttonStyle(.plain)
                .padding(.top, 12)

                Text("DEBUG ONLY · lock the app to see the banner")
                    .font(.eyebrow).tracking(0.4).foregroundStyle(Color.faint)
                    .padding(.top, 8)
                #endif

                Text("Language, reminder timing, privacy, export — coming in Week 8.")
                    .font(.subline).foregroundStyle(Color.faint)
                    .padding(.top, 18)

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 60)
        }
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized:    notifyStatus = "On — reminders will be delivered."
            case .denied:        notifyStatus = "Off — enable in iOS Settings to get reminders."
            case .notDetermined: notifyStatus = "Not yet asked."
            case .provisional:   notifyStatus = "Quiet delivery."
            case .ephemeral:     notifyStatus = "Temporary."
            @unknown default:    notifyStatus = "Unknown."
            }
        }
    }
}

#Preview {
    SettingsView()
}
