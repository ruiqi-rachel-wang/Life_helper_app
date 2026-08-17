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

    // May a document's recognised text leave the device right now?
    //
    // The ONLY question the scan path should ask. `.notAsked` is false: silence
    // is not agreement, and a build that shipped this check inverted would send
    // documents to OpenAI for every user who had never seen the sheet.
    static var allowsSendingDocuments: Bool { state == .granted }

    static func record(granted: Bool) {
        UserDefaults.standard.set(granted, forKey: key)
    }

    // For the Profile toggle, which needs to write both directions.
    static func set(_ granted: Bool) { record(granted: granted) }
}
