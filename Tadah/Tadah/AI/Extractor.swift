//  Extractor.swift
//
//  The seam between "our code" and "the AI". Everything that turns OCR text
//  into an ExtractionResult conforms to `Extractor`:
//   • OpenAIClient   — the real GPT-4o-mini call (OpenAIClient.swift)
//   • MockExtractor  — canned results for unit tests + SwiftUI previews (no
//                      network, no cost)
//
//  Because both sides of the seam share this protocol, swapping the direct
//  OpenAI call for the Cloudflare Worker later is a one-line change, and the
//  whole pipeline is testable for free.
//

import Foundation

// Which language the AI writes its explanation/steps in. Driven by the Profile
// tab's language picker (Week 8), stored in @AppStorage(storageKey). Defaults to
// the device language but is overridable. This controls only the AI's prose
// (summary + steps); the app's UI chrome is localized separately via the device
// language (String Catalog).
nonisolated enum ExplainLanguage: String, Codable, CaseIterable {
    case english, chinese, spanish

    // @AppStorage key for the user's saved choice (empty = follow the device).
    static let storageKey = "explainLanguage"

    // How we name the language TO the model in the prompt.
    var promptName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "Simplified Chinese"
        case .spanish: return "Spanish"
        }
    }

    // The .lproj resource name for on-device String-Catalog lookups (guide content).
    var lprojCode: String {
        switch self {
        case .english: return "en"
        case .chinese: return "zh-Hans"
        case .spanish: return "es"
        }
    }

    // BCP-47 tag for Apple's on-device Translation framework (Locale.Language).
    var bcp47: String {
        switch self {
        case .english: return "en"
        case .chinese: return "zh-Hans"
        case .spanish: return "es"
        }
    }

    // The label shown in the picker — each language in its own script.
    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "中文"
        case .spanish: return "Español"
        }
    }

    // Map the device locale onto one of our three supported languages. This is
    // the default until the user picks explicitly.
    static var deviceDefault: ExplainLanguage {
        switch Locale.current.language.languageCode?.identifier {
        case "zh": return .chinese
        case "es": return .spanish
        default:   return .english
        }
    }

    // Resolve the stored preference: an empty or unrecognized raw value means
    // "follow the device"; anything else is the user's explicit override.
    static func resolve(stored: String) -> ExplainLanguage {
        ExplainLanguage(rawValue: stored) ?? .deviceDefault
    }
}

nonisolated protocol Extractor {
    /// Turn raw OCR text into a structured ExtractionResult.
    /// - Parameters:
    ///   - text: the raw OCR output.
    ///   - hints: exact fields the rule parser already found (passed to the
    ///     model as ground truth so it doesn't re-guess the amount/date).
    ///   - language: the language the summary + steps should be written in.
    /// Returns one ExtractionResult per action item found. Most documents yield
    /// exactly one; a list (e.g. several appointments) yields several.
    func extract(text: String,
                 hints: RuleBasedParser.Hints,
                 language: ExplainLanguage) async throws -> [ExtractionResult]
}

// A fake Extractor for tests + previews. Returns a canned result, can be told
// to throw, and records whether it was actually called (so a test can prove
// ExtractionService skipped the model on empty OCR).
nonisolated final class MockExtractor: Extractor {
    var stub: [ExtractionResult]
    var error: Error?
    private(set) var callCount = 0
    private(set) var lastText: String?

    init(stub: [ExtractionResult] = [], error: Error? = nil) {
        self.stub = stub
        self.error = error
    }

    func extract(text: String,
                 hints: RuleBasedParser.Hints,
                 language: ExplainLanguage) async throws -> [ExtractionResult] {
        callCount += 1
        lastText = text
        if let error { throw error }
        return stub
    }
}
