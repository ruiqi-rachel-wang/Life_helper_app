//  ProfileView.swift
//
//  The 4th tab (was "Settings"). Three reachable states: a GUEST ("No account"),
//  a signed-in FREE account, and a signed-in PLUS account — where the identity
//  card grows a profile switcher and the upgrade row becomes the way into Family
//  (all built; the "isn't built yet" note that used to sit here was stale).
//
//  Layout follows Rachel's mockup: an account summary card on top (identity, or a
//  "create account" prompt), then compact grouped sections — SETTINGS, PRIVACY,
//  HELP — instead of the old long inline language list, which made the screen feel
//  cluttered.
//
//  The one control that affects behavior is the LANGUAGE picker: it stores the
//  user's choice, threaded into the scan + guide AI calls. It defaults to the
//  device language but can be overridden (an ESL user may have an English phone
//  yet prefer 中文).
//
//  As of 2026-08-13 this picker drives the ENTIRE app — every screen, Apple's own
//  UI on the next launch, and the RevenueCat paywall — not just the AI's prose.
//  See AppLanguage. It used to change only what the model wrote, which left a
//  tester who picked 中文 with a half-Chinese app.
//

import SwiftUI
import SwiftData
import UserNotifications
import UIKit

struct ProfileView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Environment(AccountStore.self) private var account
    @Environment(PlusStore.self) private var plus
    @Environment(ProfileStore.self) private var profiles
    @Environment(SyncCoordinator.self) private var sync
    @AppStorage(ExplainLanguage.storageKey) private var explainLanguageRaw = ""
    @AppStorage(Metrics.shareUsageKey) private var shareUsage = true   // anonymous usage stats opt-out
    @AppStorage(ReminderScheduler.discreetKey) private var discreetNotifications = false
    @AppStorage(AppSettings.savePhotoKey) private var savePhoto = true // keep scanned photo on the item
    @AppStorage(AppSettings.defaultReminderMinutesKey) private var reminderMinutes = AppSettings.fallbackReminderMinutes
    @State private var notifyStatus = String(localized: "Checking…")
    @State private var notifyOn = false
    @State private var notifyUndetermined = false   // never asked → row can request
    @State private var legalDoc: LegalDoc?
    @State private var showSignIn = false
    @State private var showAccountDetails = false
    @State private var showLanguageSheet = false
    @State private var confirmSignOut = false
    @State private var showPaywall = false
    @State private var showFamilySharing = false

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
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: $showFamilySharing) { FamilySharingView() }
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
                                Text(planLabel).font(.subline).foregroundStyle(Color.faded)
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

                    backupProblemRow

                    // Whose list am I looking at — only worth showing once there's
                    // more than one person on the account.
                    if profiles.hasFamily {
                        divider
                        profileSwitcherStrip
                    }

                    // ONE way into family management, not two.
                    //
                    // When the switcher is on screen it already carries "Manage",
                    // so the Family row underneath was a second door to the same
                    // sheet, stacked directly below the first. Show that row only
                    // when the switcher ISN'T there — i.e. a Plus account with
                    // nobody added yet, where it's the only way in — and keep it
                    // for free accounts, where it's the upgrade prompt.
                    if !profiles.hasFamily {
                        divider
                        plusUpgradeRow
                    }
                }
            }
        } else {
            // Guest: no account yet — data is device-only until they sign in.
            card {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No account").font(.cardTitle).foregroundStyle(Color.ink)
                        Text("Sign in to keep your items backed up.")
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

    // "Free plan" / "Tadah Plus" / "Family Plus · 3 people" — the last only once
    // there's actually a family, so a solo Plus user isn't told about one.
    private var planLabel: String {
        guard plus.isPlus else { return String(localized: "Free plan") }
        guard profiles.hasFamily else { return String(localized: "Tadah Plus") }
        return String(localized: "Family Plus · \(profiles.profiles.count) people")
    }

    // MARK: profile switcher — a row of faces under the identity row
    //
    // Tapping a face changes whose to-dos the whole app shows, so it deliberately
    // sits at the top of Profile where it's easy to find, and the selected one
    // carries a ring.

    private var profileSwitcherStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("VIEWING").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                Spacer()
                Button { showFamilySharing = true } label: {
                    Text("Manage").font(.subline.weight(.semibold)).foregroundStyle(Color.accent)
                }
                .buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(profiles.profiles) { profile in
                        Button { profiles.setActive(profile.id) } label: {
                            VStack(spacing: 5) {
                                ProfileAvatar(initials: profile.initials,
                                              colorIndex: profile.colorIndex,
                                              size: 44,
                                              isSelected: profile.id == profiles.activeProfileID)
                                Text(profile.displayName)
                                    .font(.eyebrow).tracking(0.3)
                                    .foregroundStyle(profile.id == profiles.activeProfileID
                                                     ? Color.ink : Color.faded)
                                    .lineLimit(1)
                            }
                            .frame(width: 60)
                        }
                        .buttonStyle(.plain)
                    }
                    Button { showFamilySharing = true } label: {
                        VStack(spacing: 5) {
                            AddProfileCircle(size: 44)
                            Text("Add").font(.eyebrow).tracking(0.3).foregroundStyle(Color.faded)
                        }
                        .frame(width: 60)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 14)
    }

    // A round monogram avatar, shared with Account Details.
    private func avatar(initials: String) -> some View {
        ZStack {
            Circle().fill(Color.accent.opacity(0.15))
            Text(initials).font(.system(size: 19, weight: .semibold)).foregroundStyle(Color.accent)
        }
        .frame(width: 52, height: 52)
    }

    // NO BACKUP STATUS LIGHT, deliberately (2026-08-13) — but failure is NOT
    // silent (2026-08-16).
    //
    // There used to be a "Backup — Backed up 14 seconds ago" row here that also
    // acted as a manual sync button. That's gone, and stays gone: backing up is
    // an invisible property of having an account, not a chore, and `TadahApp`
    // already syncs on launch and on every foreground/background transition.
    //
    // What the removal took with it, though, was the only place a PERMANENT
    // failure could ever surface. "It retries on the next foreground" is true of a
    // dropped connection; it is not true of a rejected request, an encoding
    // failure, or a response this build can't parse — those fail identically every
    // time, forever, while the user goes on believing their list is safe.
    //
    // So: nothing while sync is merely working or briefly offline, and one honest
    // row once it has failed three times running (SyncCoordinator.backupIsStuck).
    @ViewBuilder
    private var backupProblemRow: some View {
        if sync.backupIsStuck {
            VStack(alignment: .leading, spacing: 8) {
                divider
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16)).foregroundStyle(Color.warn)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Backup isn't working").font(.body14.weight(.semibold))
                            .foregroundStyle(Color.ink)
                        // Says what is and isn't at risk. Their to-dos are all still
                        // here — the failure is about the COPY, and saying so stops
                        // this reading as "your data is gone".
                        Text("Your to-dos are safe on this phone, but they haven't reached your account. Tap to try again.")
                            .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                        // The raw reason, small. Not for the user to act on — it's
                        // so a bug report can say WHAT failed instead of "sync is
                        // broken", which is unfixable from the outside.
                        if let detail = sync.lastError {
                            Text(detail)
                                .font(.eyebrow).foregroundStyle(Color.faded)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    if sync.isSyncing { ProgressView().controlSize(.small) }
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .onTapGesture { retryBackup() }
            }
        }
    }

    private func retryBackup() {
        guard !sync.isSyncing else { return }
        Task { await sync.syncNow(context: modelContext, account: account) }
    }

    // Names once there are some ("Jing, Mom, Dad"), an invitation before that.
    private var familySubtitle: String {
        guard profiles.hasFamily else {
            return String(localized: "Add someone like a parent and manage their letters from here.")
        }
        return profiles.profiles.map(\.displayName).joined(separator: ", ")
    }

    // MARK: Tadah Plus upgrade — a row inside the account card, under the email

    @ViewBuilder
    private var plusUpgradeRow: some View {
        // `familyUnlocked`, not `isPlus`. They differ during a RevenueCat outage,
        // where the gate deliberately fails OPEN — and branching on isPlus there
        // showed a paying subscriber an "Upgrade" button for something they
        // already have.
        if profiles.familyUnlocked {
            // Already Plus: the row becomes the way INTO family management, since
            // that's the thing Plus actually unlocks day to day.
            Button { showFamilySharing = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.2.fill").font(.system(size: 16)).foregroundStyle(Color.accent)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Family").font(.body14.weight(.semibold)).foregroundStyle(Color.ink)
                        Text(familySubtitle)
                            .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13)).foregroundStyle(Color.faint)
                }
                .padding(.top, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Button { showPaywall = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles").font(.system(size: 17)).foregroundStyle(Color.accent)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tadah Plus").font(.body14.weight(.semibold)).foregroundStyle(Color.ink)
                        // A little more on what Plus unlocks (Rachel's ask).
                        // NOT "share tasks" — that implies your mum signs in with her
                        // own Apple ID and you share between accounts, which is a
                        // different product (later_ideas §6). What Plus actually
                        // buys is separate lists on ONE account.
                        Text("Add family members, keep a separate list for each person, and use Tadah on more than one device.")
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
    }

    // MARK: settings (compact rows)

    private var settingsCard: some View {
        card {
            VStack(spacing: 0) {
                sectionHeader("SETTINGS")
                navRow("Language", value: language.displayName) { showLanguageSheet = true }
                divider
                notificationsRow
                divider
                // ALWAYS SHOWN — including when there is a family.
                //
                // It used to be hidden once a family existed, on the theory that
                // each person sets their own time in Family → ⓘ → Edit. But the
                // setting never stopped mattering: "Everyone" to-dos always use
                // it, and any family member who turns OFF "Own reminder time" is
                // told they now follow it. Hiding the only editor left people
                // pointed at a default they had no way to change.
                //
                // The label says which of the two it is, so it can't be mistaken
                // for a second, contradicting copy of Mum's per-person time.
                VStack(alignment: .leading, spacing: 2) {
                    // The time a reminder fires when its task has no time of its
                    // own (plain-date tasks + the daily overdue nudge). Timed
                    // tasks keep their own exact time.
                    DatePicker(selection: reminderTime, displayedComponents: .hourAndMinute) {
                        // Explicit LocalizedStringKey: a ternary between two string
                        // literals types as `String`, which Text renders VERBATIM —
                        // the row would silently stop translating.
                        Text(profiles.hasFamily
                             ? LocalizedStringKey("Default reminder time")
                             : LocalizedStringKey("Reminder time"))
                            .font(.body14).foregroundStyle(Color.ink)
                    }
                    if profiles.hasFamily {
                        Text("Used for “Everyone” to-dos and anyone without their own reminder time.")
                            .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Color.accent)
                .padding(.vertical, 8)
                .onChange(of: reminderMinutes) { _, _ in rescheduleAllItems() }
            }
        }
    }

    // Map the stored minutes-past-midnight to/from the Date the picker wants.
    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: reminderMinutes / 60,
                                      minute: reminderMinutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { newValue in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                reminderMinutes = (c.hour ?? 9) * 60 + (c.minute ?? 0)
            })
    }

    // Existing non-customized reminders + overdue nudges recompute at the new
    // time, so the change applies to items already scheduled, not just new ones.
    private func rescheduleAllItems() {
        if let items = try? modelContext.fetch(FetchDescriptor<ActionItem>()) {
            ReminderScheduler.shared.rescheduleAll(for: items)
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

    // MARK: log out (signed-in only) — the confirmation expands inline, right
    // inside this card, so it stays attached to the button and scrolls with it
    // (no bottom action sheet that sits detached at the edge of the screen).

    private var logOutButton: some View {
        card {
            if confirmSignOut {
                VStack(spacing: 12) {
                    Text("Sign out?").font(.body14.weight(.semibold)).foregroundStyle(Color.ink)
                    Text("Your items are saved — signing back in brings them right back.")
                        .font(.subline).foregroundStyle(Color.faded)
                        .multilineTextAlignment(.center).lineSpacing(2)
                    HStack(spacing: 10) {
                        Button { withAnimation(.easeInOut(duration: 0.2)) { confirmSignOut = false } } label: {
                            Text("Cancel").font(.body14.weight(.semibold)).foregroundStyle(Color.ink)
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 10).stroke(Color.hairD, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        // signOutEverywhere, not signOut: revoke the session on the
                        // server too, so the token really stops working (and the
                        // privacy policy's "signing out ends the session" is true).
                        Button {
                            confirmSignOut = false
                            Task { await account.signOutEverywhere() }
                        } label: {
                            Text("Log out").font(.body14.weight(.semibold)).foregroundStyle(Color.paper)
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.bad))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                Button { withAnimation(.easeInOut(duration: 0.2)) { confirmSignOut = true } } label: {
                    Text("Log out").font(.body14.weight(.semibold)).foregroundStyle(Color.bad)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
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
                .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
            Text(versionText).font(.eyebrow).tracking(0.6).foregroundStyle(Color.faded)
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
                                    // Picking a language rebuilds the whole app in it
                                    // (RootTabView's .id), which tears this sheet down
                                    // anyway — so close it deliberately rather than
                                    // letting it vanish mid-tap. The user lands back on
                                    // a Profile page already in the new language, which
                                    // is the confirmation that the setting took.
                                    Button {
                                        explainLanguageRaw = lang.rawValue
                                        // Redirect string lookups HERE, at the
                                        // source of the change. RootTabView also
                                        // watches the setting, but its `.id()`
                                        // rebuild makes it ambiguous whether that
                                        // onChange survives the identity swap —
                                        // and a language that doesn't apply is
                                        // the whole bug. Idempotent, so both
                                        // firing is fine.
                                        AppLanguage.applyStoredPreference()
                                        showLanguageSheet = false
                                    } label: {
                                        HStack {
                                            Text(lang.displayName).font(.body14).foregroundStyle(Color.ink)
                                            Spacer()
                                            if lang == language {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.accent)
                                            }
                                        }
                                        .frame(minHeight: 44)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        Text(inPickedLanguage("Changes the whole app — every screen, plus the explanations Tadah writes for your scans and guides."))
                            .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
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
            Text("DEBUG").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
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
        .environment(PlusStore())
        .environment(SyncCoordinator.shared)
        .environment(ProfileStore())
}
