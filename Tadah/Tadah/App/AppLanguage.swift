//  AppLanguage.swift
//
//  Makes the Profile → Language picker control the WHOLE app, not just the AI's
//  prose.
//
//  It used to control only what the model wrote (summaries, guide steps), while
//  every button, heading and alert followed the PHONE's language. So a tester on
//  an English phone who picked 中文 got a half-Chinese app — and the language
//  sheet had to admit it in writing ("The app itself follows your phone").
//  That's exactly backwards for who this app is for: someone whose phone is in
//  English because they had to set it up that way, but who reads Chinese.
//
//  Three things have to agree for a language change to take effect everywhere,
//  because iOS resolves strings through three different doors:
//
//   1. `Bundle.main.localizedString(forKey:value:table:)` — the door used by
//      NSLocalizedString and String(localized:). We put a subclass in front of
//      Bundle.main (`object_setClass`, the standard runtime re-class trick) that
//      forwards every lookup to the chosen .lproj.
//   2. SwiftUI's `Text(LocalizedStringKey)`, which resolves lazily at render
//      time against `Environment(\.locale)` — set at the root in RootTabView.
//   3. Apple's own UI (date pickers, share sheets, system alerts), which reads
//      `AppleLanguages` at launch. We write it so those come along on the NEXT
//      launch; nothing in-app waits for a restart.
//
//  Live switching (no "please restart Tadah") is the point — see the `.id()` on
//  the root view, which rebuilds the tree so already-rendered screens re-resolve.
//

import Foundation
import ObjectiveC
import RevenueCat

// Bundle.main, re-classed to this, sends every string lookup to one .lproj.
// Only `localizedString` is overridden — paths, resources and Info.plist reads
// all fall through to the real implementation untouched.
private final class PickedLanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        guard let picked = AppLanguage.pickedBundle else {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
        // `picked` is a plain Bundle (an .lproj directory), never re-classed, so
        // this can't recurse back into here.
        return picked.localizedString(forKey: key, value: value, table: tableName)
    }
}

enum AppLanguage {
    // Read by PickedLanguageBundle on every lookup. nil = fall through to the
    // development localization (English).
    fileprivate nonisolated(unsafe) static var pickedBundle: Bundle?
    private nonisolated(unsafe) static var isInstalled = false

    // Point the app at `language`. Safe to call repeatedly; the re-class happens
    // once. Call it before the first view renders (TadahApp.init) and again
    // whenever the picker changes.
    //
    // `explicit` = the user actually picked this language, as opposed to us
    // resolving "follow the phone". It gates the AppleLanguages write ONLY —
    // see the comment there for why that distinction matters.
    static func apply(_ language: ExplainLanguage, explicit: Bool) {
        if !isInstalled {
            object_setClass(Bundle.main, PickedLanguageBundle.self)
            isInstalled = true
        }
        // `path(forResource:)` still resolves on the re-classed bundle — only
        // string lookups were overridden.
        pickedBundle = Bundle.main.path(forResource: language.lprojCode, ofType: "lproj")
            .flatMap(Bundle.init(path:))

        // Door 3: Apple's own UI. Takes effect next launch — writing it is what
        // makes system date pickers and share sheets eventually agree with the
        // rest of the app. Deliberately does NOT gate anything in Tadah itself.
        //
        // ONLY on an explicit pick. `ExplainLanguage.deviceDefault` reads
        // Locale.current, which reads this key — so writing it while the user is
        // still on "follow my phone" would make the app follow its own last
        // guess forever, and a later change to the phone's language would never
        // reach us. Clearing it when there's no explicit pick restores that.
        if explicit {
            UserDefaults.standard.set([language.lprojCode], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }

        // Door 4: the RevenueCat paywall, which is rendered by their SDK from the
        // dashboard's own localizations and knows nothing about our bundle.
        //
        // `.environment(\.locale)` on RevenueCatUI.PaywallView does NOT do this —
        // a v2 (Paywall Editor) paywall picks its localization from
        // `Purchases.preferredLocales` and then overwrites the environment locale
        // with whatever it chose. So the wrapper in PaywallView.swift was a no-op
        // and the paywall silently followed the phone. This is the supported API.
        if Purchases.isConfigured {
            Purchases.shared.overridePreferredUILocale(language.lprojCode)
        }
    }

    // Resolve the stored preference and apply it. Used at launch, where reading
    // @AppStorage isn't available yet, and again whenever the picker changes.
    static func applyStoredPreference() {
        let raw = UserDefaults.standard.string(forKey: ExplainLanguage.storageKey) ?? ""
        // An unrecognised raw value is "follow the phone", same as empty — match
        // ExplainLanguage.resolve exactly so the two can't disagree.
        let explicit = ExplainLanguage(rawValue: raw) != nil
        apply(ExplainLanguage.resolve(stored: raw), explicit: explicit)
    }
}
