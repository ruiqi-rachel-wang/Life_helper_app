//  ProfileView.swift
//
//  The 4th tab (was "Settings"). A guest profile for now — no accounts yet —
//  but this is where account / family sharing / paid-plan features will land,
//  so they're scaffolded as "coming soon" rows.
//
//  The one piece that affects product behavior today is the LANGUAGE picker:
//  it stores the user's choice and is threaded into the scan + guide AI calls
//  (CreateView / GuidesView). It defaults to the device language but can be
//  overridden — the ESL user may have an English phone yet prefer 中文. Only the
//  AI's prose respects this; the app's own UI chrome stays English in Phase 1.
//

import SwiftUI
import UserNotifications

struct ProfileView: View {
    @AppStorage(ExplainLanguage.storageKey) private var explainLanguageRaw = ""
    @State private var notifyStatus = "Checking…"
    #if DEBUG
    @State private var metrics = MetricsSummary()
    #endif

    private var language: ExplainLanguage { ExplainLanguage.resolve(stored: explainLanguageRaw) }

    var body: some View {
        ZStack(alignment: .top) {
            Color.paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    profileCard
                    languageCard       // top — the one wired control
                    accountCard        // coming-soon scaffolding
                    settingsCard
                    #if DEBUG
                    debugCard
                    #endif
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 14)
                .padding(.top, 60)
            }
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

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ACCOUNT").font(.eyebrow).tracking(1.4).foregroundStyle(Color.faded)
            Text("Profile").font(.serifTitle).tracking(-0.8).foregroundStyle(Color.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.bottom, 2)
    }

    // MARK: guest profile header

    private var profileCard: some View {
        card {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.bg)
                    Image(systemName: "person.fill")
                        .font(.system(size: 22)).foregroundStyle(Color.faded)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Guest").font(.cardTitle).foregroundStyle(Color.ink)
                    Text("Saved on this device only").font(.subline).foregroundStyle(Color.faded)
                }
                Spacer()
            }
        }
    }

    // MARK: language (the wired control)

    private var languageCard: some View {
        card {
            VStack(alignment: .leading, spacing: 0) {
                Text("EXPLAIN DOCUMENTS IN").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                    .padding(.bottom, 10)

                ForEach(Array(ExplainLanguage.allCases.enumerated()), id: \.element) { index, lang in
                    if index != 0 { Rectangle().fill(Color.hairD).frame(height: 1) }
                    Button { explainLanguageRaw = lang.rawValue } label: {
                        HStack {
                            Text(lang.displayName).font(.body14).foregroundStyle(Color.ink)
                            Spacer()
                            if lang == language {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.accent)
                            }
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Text("Defaults to your phone's language. Applies to new scans and most guides. A few sensitive guides (money, immigration, medical) stay in English and on your device. The app's own labels stay in English for now.")
                    .font(.subline).foregroundStyle(Color.faint)
                    .padding(.top, 10)
            }
        }
    }

    // MARK: account — coming soon

    private var accountCard: some View {
        card {
            VStack(alignment: .leading, spacing: 0) {
                Text("ACCOUNT").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                    .padding(.bottom, 4)
                comingSoonRow("Sign in", "person.badge.key", first: true)
                comingSoonRow("Family sharing", "person.2")
                comingSoonRow("Notie Plus", "sparkles")
            }
        }
    }

    private func comingSoonRow(_ title: String, _ symbol: String, first: Bool = false) -> some View {
        VStack(spacing: 0) {
            if !first { Rectangle().fill(Color.hairD).frame(height: 1) }
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15)).foregroundStyle(Color.faint)
                    .frame(width: 22)
                Text(title).font(.body14).foregroundStyle(Color.faded)
                Spacer()
                Text("SOON")
                    .font(.eyebrow).tracking(0.8).foregroundStyle(Color.faded)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.bg))
            }
            .padding(.vertical, 12)
        }
    }

    // MARK: settings

    private var settingsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                Text("NOTIFICATIONS").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                Text(notifyStatus).font(.subline).foregroundStyle(Color.ink)
            }
        }
    }

    #if DEBUG
    // Kept separate from real settings so it never looks shippable.
    private var debugCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DEBUG").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faint)

            metricsPanel

            Button {
                ReminderScheduler.shared.fireTestReminder()
            } label: {
                Text("Send a test reminder (5s)")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.paper)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.ink))
            }
            .buttonStyle(.plain)
            Text("Lock the app to see the banner.")
                .font(.eyebrow).tracking(0.4).foregroundStyle(Color.faint)
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .onAppear { metrics = Metrics.summary() }
    }

    // The local launch metric, computed from this device's event log.
    private var metricsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LAUNCH METRIC · THIS DEVICE").font(.eyebrow).tracking(0.8).foregroundStyle(Color.faded)
            metricRow("Confirmed", "\(metrics.confirmed)")
            metricRow("Completed", "\(metrics.completed)  ·  \(pct(metrics.completionRate))")
            metricRow("Done on time", "\(metrics.completedOnTime)/\(metrics.completedWithDue)  ·  \(pct(metrics.onTimeRate))")
            if !metrics.bySource.isEmpty {
                Text("Confirmed by: " + metrics.bySource.sorted { $0.key < $1.key }
                        .map { "\($0.key) \($0.value)" }.joined(separator: " · "))
                    .font(.subline).foregroundStyle(Color.faded)
            }
            HStack(spacing: 12) {
                if let url = Metrics.exportURL() {
                    ShareLink(item: url) {
                        Label("Export", systemImage: "square.and.arrow.up").font(.subline).foregroundStyle(Color.accent)
                    }
                }
                Spacer()
                Button("Reset") { Metrics.reset(); metrics = Metrics.summary() }
                    .font(.subline).foregroundStyle(Color.bad)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hair, lineWidth: 1))
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.body14).foregroundStyle(Color.faded)
            Spacer()
            Text(value).font(.body14).foregroundStyle(Color.ink)
        }
    }

    private func pct(_ r: Double) -> String { String(format: "%.0f%%", r * 100) }
    #endif

    // MARK: shared card shell (mirrors Detail/Review)

    private func card<C: View>(@ViewBuilder _ inner: () -> C) -> some View {
        inner()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }
}

#Preview {
    ProfileView()
}
