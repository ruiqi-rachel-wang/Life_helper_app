//  ProfileView.swift
//
//  The 4th tab (was "Settings"). Two reachable states today: a GUEST ("No
//  account") and a signed-in FREE account (Part 3, phase 1). The signed-in
//  Family-Plus layout — a FAMILY section + more settings moved under Account —
//  is drawn in the design mockups and lands with the Plus phase (see
//  future_features.md Part 3), so it isn't built here yet.
//
//  Layout follows Rachel's mockup: an account summary card on top (identity, or a
//  "create account" prompt), then compact grouped sections — SETTINGS, PRIVACY,
//  HELP — instead of the old long inline language list, which made the screen feel
//  cluttered.
//
//  The one control that affects behavior is the LANGUAGE picker: it stores the
//  user's choice, threaded into the scan + guide AI calls. It defaults to the
//  device language but can be overridden (an ESL user may have an English phone
//  yet prefer 中文). Only the AI's prose respects this; the app's own UI chrome
//  follows the iPhone's language (String Catalog), independent of this setting.
//

import SwiftUI
import SwiftData
import UserNotifications
import UIKit

struct ProfileView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Environment(AccountStore.self) private var account
    @AppStorage(ExplainLanguage.storageKey) private var explainLanguageRaw = ""
    @AppStorage(Metrics.shareUsageKey) private var shareUsage = true   // anonymous usage stats opt-out
    @AppStorage(ReminderScheduler.discreetKey) private var discreetNotifications = false
    @AppStorage(AppSettings.savePhotoKey) private var savePhoto = true // keep scanned photo on the item
    @State private var notifyStatus = String(localized: "Checking…")
    @State private var notifyOn = false
    @State private var notifyUndetermined = false   // never asked → row can request
    @State private var legalDoc: LegalDoc?
    @State private var showSignIn = false
    @State private var showAccountDetails = false
    @State private var showLanguageSheet = false
    @State private var confirmSignOut = false
    @State private var showPlusComingSoon = false

    // Which legal document the in-app sheet is showing.
    private enum LegalDoc: Int, Identifiable { case privacy, terms; var id: Int { rawValue } }
    #if DEBUG
    @State private var metrics = MetricsSummary()
    #endif

    private var language: ExplainLanguage { ExplainLanguage.resolve(stored: explainLanguageRaw) }

    // Support inbox (placeholder role address; see build plan). Feedback opens Mail.
    private let supportEmail = "support.tadah@gmail.com"

    // Resolve a string in the PICKED explain-language (not the phone's), so a
    // helper note appears in whatever language the user just selected — the same
    // on-device bundle lookup ExtractionResult.localized() uses.
    private func inPickedLanguage(_ s: String) -> String {
        let bundle = Bundle.main.path(forResource: language.lprojCode, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? .main
        return bundle.localizedString(forKey: s, value: s, table: nil)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    accountSummaryCard
                    settingsCard
                    privacyCard
                    helpCard
                    if account.isSignedIn { logOutButton }
                    footer
                    #if DEBUG
                    debugCard
                    #endif
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 14)
                .padding(.top, 60)
            }
        }
        .task { await refreshNotify() }
        .sheet(item: $legalDoc) { doc in
            switch doc {
            case .privacy: LegalDocumentView(title: "Privacy Policy", markdown: LegalContent.privacyPolicy)
            case .terms:   LegalDocumentView(title: "Terms & Disclaimers", markdown: LegalContent.terms)
            }
        }
        .sheet(isPresented: $showSignIn) { SignInView() }
        .sheet(isPresented: $showAccountDetails) { AccountDetailsView() }
        .sheet(isPresented: $showLanguageSheet) { languageSheet }
        .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { account.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your items stay on this device — signing back in brings them right back.")
        }
        .alert("Family sharing is coming with Tadah Plus", isPresented: $showPlusComingSoon) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Soon you'll be able to add family members (like a parent) and manage their mail from your account. We'll let you know when it's ready.")
        }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PROFILE").font(.eyebrow).tracking(1.4).foregroundStyle(Color.faded)
            Text("My Settings").font(.serifTitle).tracking(-0.8).foregroundStyle(Color.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.bottom, 2)
    }

    // MARK: account summary (identity, or the create-account prompt)

    @ViewBuilder
    private var accountSummaryCard: some View {
        if let account = account.account {
            // Signed in: identity row → Account Details, with the Plus upgrade
            // folded in right below the email (its own tappable row).
            card {
                VStack(spacing: 0) {
                    Button { showAccountDetails = true } label: {
                        HStack(spacing: 14) {
                            avatar(initials: account.initials)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.displayName).font(.cardTitle).foregroundStyle(Color.ink)
                                Text("Free plan").font(.subline).foregroundStyle(Color.faded)
                                if !account.email.isEmpty {
                                    Text(account.email).font(.subline).foregroundStyle(Color.faded)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13)).foregroundStyle(Color.faint)
                        }
                        .padding(.bottom, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    divider

                    plusUpgradeRow
                }
            }
        } else {
            // Guest: no account yet — data is device-only until they sign in.
            card {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No account").font(.cardTitle).foregroundStyle(Color.ink)
                        Text("Your information stays on this phone.")
                            .font(.subline).foregroundStyle(Color.faded)
                    }
                    Button { showSignIn = true } label: {
                        Text("Create a free account").font(.body14.weight(.semibold))
                            .foregroundStyle(Color.paper)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.ink))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // A round monogram avatar, shared with Account Details.
    private func avatar(initials: String) -> some View {
        ZStack {
            Circle().fill(Color.accent.opacity(0.15))
            Text(initials).font(.system(size: 19, weight: .semibold)).foregroundStyle(Color.accent)
        }
        .frame(width: 52, height: 52)
    }

    // MARK: Tadah Plus upgrade — a row inside the account card, under the email

    private var plusUpgradeRow: some View {
        Button { showPlusComingSoon = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.system(size: 17)).foregroundStyle(Color.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tadah Plus").font(.body14.weight(.semibold)).foregroundStyle(Color.ink)
                    // A little more on what Plus unlocks (Rachel's ask).
                    Text("Add family members, share tasks, and use Tadah on more than one device.")
                        .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text("UPGRADE")
                    .font(.eyebrow).tracking(0.8).foregroundStyle(Color.accent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.accent.opacity(0.12)))
            }
            .padding(.top, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: settings (compact rows)

    private var settingsCard: some View {
        card {
            VStack(spacing: 0) {
                sectionHeader("SETTINGS")
                navRow("Language", value: language.displayName) { showLanguageSheet = true }
                divider
                notificationsRow
            }
        }
    }

    // Tap requests permission if we've never asked (e.g. "Not now" on the primer);
    // once iOS has decided, deep-link to Settings instead.
    private var notificationsRow: some View {
        Button {
            if notifyUndetermined {
                Task { await ReminderScheduler.shared.requestAuthorization(); await refreshNotify() }
            } else if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                rowContent(title: "Notifications",
                           value: notifyOn ? String(localized: "On") : String(localized: "Off"),
                           chevron: true)
                if !notifyOn {
                    Text("Reminders are how Tadah keeps you on top of deadlines — turn them on to get the most out of the app.")
                        .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: privacy

    private var privacyCard: some View {
        card {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("PRIVACY")

                toggleRow("Save uploaded photos", isOn: $savePhoto)
                divider
                // Phrased positively + ON by default, to match the other toggles.
                // Off → discreet notifications (the lock screen shows "Tadah").
                toggleRow("Show details in notifications", isOn: Binding(
                    get: { !discreetNotifications },
                    set: { discreetNotifications = !$0 }))
                    .onChange(of: discreetNotifications) { _, _ in
                        if let items = try? modelContext.fetch(FetchDescriptor<ActionItem>()) {
                            ReminderScheduler.shared.rescheduleAll(for: items)
                        }
                    }
                divider
                toggleRow("Share anonymous app data", isOn: $shareUsage)
                divider
                navRow("Privacy Policy", value: nil) { legalDoc = .privacy }
                divider
                navRow("Terms of Use", value: nil) { legalDoc = .terms }
            }
        }
    }

    // MARK: log out (signed-in only) — a plain centered action, per the mockup

    private var logOutButton: some View {
        Button { confirmSignOut = true } label: {
            card {
                Text("Log out").font(.body14.weight(.semibold)).foregroundStyle(Color.bad)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: help

    private var helpCard: some View {
        card {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("HELP")
                Button {
                    if let url = URL(string: "mailto:\(supportEmail)") { openURL(url) }
                } label: {
                    Text(supportEmail).font(.body14).foregroundStyle(Color.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: footer — legal disclaimer + version

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tadah is informational only — not legal, tax, immigration, financial, or medical advice. It uses AI, which can make mistakes; please double-check important details with official sources or a professional.")
                .font(.subline).foregroundStyle(Color.faint).lineSpacing(2)
            Text(versionText).font(.eyebrow).tracking(0.6).foregroundStyle(Color.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.top, 2)
    }

    // MARK: language sheet (moved off the main screen to declutter)

    private var languageSheet: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        card {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(ExplainLanguage.allCases.enumerated()), id: \.element) { index, lang in
                                    if index != 0 { divider }
                                    Button { explainLanguageRaw = lang.rawValue } label: {
                                        HStack {
                                            Text(lang.displayName).font(.body14).foregroundStyle(Color.ink)
                                            Spacer()
                                            if lang == language {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.accent)
                                            }
                                        }
                                        .padding(.vertical, 13)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        Text(inPickedLanguage("Only changes the language Tadah uses to explain your scans and guides. The app itself follows your phone."))
                            .font(.subline).foregroundStyle(Color.faint).lineSpacing(2)
                            .padding(.horizontal, 8)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showLanguageSheet = false }.font(.body14.weight(.semibold))
                }
            }
        }
    }

    // MARK: small row builders

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 10)
    }

    private var divider: some View { Rectangle().fill(Color.hairD).frame(height: 1) }

    // A tappable row: title on the left, an optional value + chevron on the right.
    private func navRow(_ title: LocalizedStringKey, value: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowContent(title: title, value: value, chevron: true).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rowContent(title: LocalizedStringKey, value: String?, chevron: Bool) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.body14).foregroundStyle(Color.ink)
            Spacer()
            if let value { Text(value).font(.body14).foregroundStyle(Color.faded) }
            if chevron {
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Color.faint)
            }
        }
        .padding(.vertical, 12)
    }

    // Plain toggle row — settings here are self-explanatory, so no helper text.
    private func toggleRow(_ title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).font(.body14).foregroundStyle(Color.ink)
        }
        .tint(Color.accent)
        .padding(.vertical, 12)
    }

    // MARK: notifications status

    private func refreshNotify() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notifyOn = status == .authorized
        notifyUndetermined = status == .notDetermined
        switch status {
        case .authorized:    notifyStatus = String(localized: "On — reminders will be delivered.")
        case .denied:        notifyStatus = String(localized: "Off — enable in iOS Settings to get reminders.")
        case .notDetermined: notifyStatus = String(localized: "Off — tap to turn on reminders.")
        case .provisional:   notifyStatus = String(localized: "Quiet delivery.")
        case .ephemeral:     notifyStatus = String(localized: "Temporary.")
        @unknown default:    notifyStatus = String(localized: "Unknown.")
        }
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "TADAH \(v) (\(b))"
    }

    // MARK: shared card shell (mirrors Detail/Review)

    private func card<C: View>(@ViewBuilder _ inner: () -> C) -> some View {
        inner()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }

    #if DEBUG
    // Kept separate from real settings so it never looks shippable.
    private var debugCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DEBUG").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faint)
            metricsPanel
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
}

#Preview {
    ProfileView()
        .environment(AccountStore())
}
