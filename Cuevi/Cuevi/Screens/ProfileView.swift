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
//  AI's prose respects this picker; the app's own UI chrome follows the iPhone's
//  language separately (String Catalog), independent of this setting.
//

import SwiftUI
import UserNotifications
import UIKit

struct ProfileView: View {
    @Environment(\.openURL) private var openURL
    @AppStorage(ExplainLanguage.storageKey) private var explainLanguageRaw = ""
    @State private var notifyStatus = String(localized: "Checking…")
    @State private var notifyOn = false
    @State private var legalDoc: LegalDoc?

    // Which legal document the in-app sheet is showing.
    private enum LegalDoc: Int, Identifiable { case privacy, terms; var id: Int { rawValue } }
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
                    legalCard          // privacy policy, terms, disclaimer, version
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
            notifyOn = settings.authorizationStatus == .authorized
            switch settings.authorizationStatus {
            case .authorized:    notifyStatus = String(localized: "On — reminders will be delivered.")
            case .denied:        notifyStatus = String(localized: "Off — enable in iOS Settings to get reminders.")
            case .notDetermined: notifyStatus = String(localized: "Not yet asked.")
            case .provisional:   notifyStatus = String(localized: "Quiet delivery.")
            case .ephemeral:     notifyStatus = String(localized: "Temporary.")
            @unknown default:    notifyStatus = String(localized: "Unknown.")
            }
        }
        .sheet(item: $legalDoc) { doc in
            switch doc {
            case .privacy: LegalDocumentView(title: "Privacy Policy", markdown: LegalContent.privacyPolicy)
            case .terms:   LegalDocumentView(title: "Terms & Disclaimers", markdown: LegalContent.terms)
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

                Text("This sets the language Cuevi uses to explain your documents (it defaults to your phone's language). The app itself follows your phone's language. A few sensitive guides — money, immigration, medical — stay in English on your device.")
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
                comingSoonRow("Cuevi Plus", "sparkles")
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

    // Tapping opens the iOS Settings page for Cuevi so the user can flip
    // notifications on/off. We can't toggle that from inside the app — iOS only
    // lets us deep-link to Settings.
    private var settingsCard: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        } label: {
            card {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOTIFICATIONS").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                        Text(notifyStatus).font(.subline).foregroundStyle(Color.ink)
                        // Cuevi depends on reminders — say so when they're off.
                        if !notifyOn {
                            Text("Reminders are how Cuevi keeps you on top of deadlines — turn them on in Settings to get the most out of the app.")
                                .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13)).foregroundStyle(Color.faint)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: about & legal

    // Required for an App Store release and the most important risk control for
    // Cuevi: a clear "informational only / AI can be wrong" disclaimer, always
    // reachable. Tapping a row opens the document IN-APP (LegalDocumentView), with
    // text from LegalContent (generated from the repo's legal/*.md).
    private var legalCard: some View {
        card {
            VStack(alignment: .leading, spacing: 0) {
                Text("ABOUT & LEGAL").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                    .padding(.bottom, 4)
                legalRow("Privacy Policy", "hand.raised", first: true) { legalDoc = .privacy }
                legalRow("Terms & Disclaimers", "doc.text") { legalDoc = .terms }

                Text("Cuevi is informational only — not legal, tax, immigration, financial, or medical advice. It uses AI, which can make mistakes; please double-check important details with official sources or a professional.")
                    .font(.subline).foregroundStyle(Color.faint).lineSpacing(2)
                    .padding(.top, 10)

                Text(versionText).font(.eyebrow).tracking(0.6).foregroundStyle(Color.faint)
                    .padding(.top, 12)
            }
        }
    }

    private func legalRow(_ title: LocalizedStringKey, _ symbol: String, first: Bool = false,
                          action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            if !first { Rectangle().fill(Color.hairD).frame(height: 1) }
            Button(action: action) {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(.system(size: 15)).foregroundStyle(Color.faded)
                        .frame(width: 22)
                    Text(title).font(.body14).foregroundStyle(Color.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12)).foregroundStyle(Color.faint)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "PLAINO \(v) (\(b))"
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
