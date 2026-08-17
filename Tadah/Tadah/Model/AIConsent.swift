//  AIConsent.swift
//
//  Has the user actually AGREED to send a document's text to OpenAI?
//
//  Scanning reads a document on-device and then sends the recognised text to a
//  third party. That text is whatever is printed on the page: a diagnosis, a
//  visa number, a bank balance, a child's name. Until 2026-08-17 the app did
//  that on the first tap of "Scan a document", with the only disclosure buried in
//  a privacy policy nobody opens.
//
//  That is the wrong default in three separate ways: Apple requires disclosure
//  and permission before personal data goes to a third-party AI service; the FTC
//  recommends affirmative consent for health information OUTSIDE the privacy
//  policy; and independently of either, someone photographing a hospital letter
//  deserves to be told where it is about to go while they can still say no.
//
//  So consent is:
//   • ASKED ONCE, at the moment it becomes real — the first scan — not buried in
//     onboarding where it would be clicked through with everything else.
//   • EXPLICIT. Nothing is sent on "unset". There is no pre-ticked box.
//   • WITHDRAWABLE at any time in Profile → Privacy, which is why this is a
//     stored tri-state and not a one-way "hasSeenOnboarding" flag.
//   • NOT REQUIRED TO USE THE APP. Declining leaves manual entry, guides,
//     reminders and everything else working — the app must not hold itself
//     hostage for data it wants.
//

import Foundation

nonisolated enum AIConsent {
    static let key = "tadah.ai.sendDocumentsConsent"

    // Deliberately a THREE-state answer. "Never asked" and "asked and declined"
    // look identical in a Bool, and telling them apart is what lets the sheet
    // appear exactly once unprompted while Profile can still show the real
    // current setting.
    enum State: Equatable {
        case notAsked
        case granted
        case declined
    }

    static var state: State {
        guard let stored = UserDefaults.standard.object(forKey: key) as? Bool else { return .notAsked }
        return stored ? .granted : .declined
    }

    // May ANYTHING leave the device for OpenAI right now?
    //
    // Deliberately named for the destination, not for one feature. It began as
    // `allowsSendingDocuments` and guarded only scanning — which left the moving
    // and renting guides' local-utility lookup sending a ZIP code and every
    // answer to that guide's questions to OpenAI with no permission at all, and
    // still doing it while "Send scans to AI" was switched off.
    //
    // Every call site that reaches OpenAI asks THIS. If a third one is ever
    // added, it asks this too — a per-feature flag is how the second one got
    // missed.
    //
    // `.notAsked` is false: silence is not agreement, and a build that shipped
    // this inverted would send to OpenAI for everyone who had never seen the sheet.
    static var allowsSendingToAI: Bool { state == .granted }

    static func record(granted: Bool) {
        UserDefaults.standard.set(granted, forKey: key)
    }

    // For the Profile toggle, which needs to write both directions.
    static func set(_ granted: Bool) { record(granted: granted) }
}
