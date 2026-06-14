//  Glossary.swift
//
//  Plain-English definitions of the jargon that trips up newcomers — form codes
//  (I-9, ITIN, W-7…) and insurance/legal terms. Step Detail scans its own text
//  and shows a "What these mean" card for any term it finds, so the user never
//  has to know the acronym in advance. Auto-applied to guides AND scanned docs.
//
//  Definitions are intentionally plain and general — not legal/tax advice.
//

import Foundation

nonisolated struct GlossaryTerm: Identifiable, Equatable {
    let term: String        // the label shown ("ITIN")
    let pattern: String     // regex used to detect it (defaults to the term)
    let plain: String       // one-line plain-English meaning
    var id: String { term }

    init(_ term: String, pattern: String? = nil, _ plain: String) {
        self.term = term
        self.pattern = pattern ?? NSRegularExpression.escapedPattern(for: term)
        self.plain = plain
    }
}

nonisolated enum Glossary {
    // Ordered by how often newcomers hit them. `found(in:)` preserves this order.
    static let all: [GlossaryTerm] = [
        // Immigration / work-authorization
        .init("SSN", "Social Security Number — a 9-digit number the U.S. uses to track your earnings and taxes."),
        .init("ITIN", "Individual Taxpayer Identification Number — a tax ID from the IRS for people who can't get an SSN."),
        .init("I-9", "The form a new employee fills out to prove they're allowed to work in the U.S."),
        .init("I-94", "Your arrival/departure record — it shows your immigration status and how long you can stay."),
        .init("EAD", "Employment Authorization Document — the work permit card that proves you can work."),
        .init("N-400", "The application to become a U.S. citizen (naturalization)."),
        .init("I-765", "The application for a work permit (EAD)."),
        .init("I-90", "The form to renew or replace a green card."),
        .init("W-7", "The IRS form you file to get an ITIN."),
        .init("green card", "The card showing you're a lawful permanent resident of the U.S."),
        .init("lawful presence", "Proof you're legally in the U.S. — like a passport, visa, green card, or work permit."),
        // Tax / pay
        .init("W-2", "The form an employer sends showing your wages and the taxes withheld for the year."),
        .init("W-4", "The form that tells your employer how much tax to withhold from each paycheck."),
        .init("W-9", "The form a contractor (1099) fills out to give a client their taxpayer ID."),
        .init("1099", "Income paid to a contractor — taxes are NOT withheld, so you handle them yourself."),
        // Health insurance
        .init("in-network", "Doctors and hospitals that have a deal with your plan — they cost you much less."),
        .init("deductible", "What you pay out of pocket before insurance starts covering costs."),
        .init("premium", "The monthly amount you pay to keep an insurance plan."),
        .init("copay", "A fixed fee you pay for a visit or prescription (like $25)."),
        .init("FQHC", "A community health center that treats everyone and charges based on your income."),
        // Auto insurance
        .init("collision coverage", "Pays to repair your car after a crash — no matter who was at fault."),
        .init("comprehensive coverage", "Pays for non-crash damage — theft, weather, fire, hitting an animal."),
        .init("third-party claim", "A claim you file against the OTHER driver's insurance when they caused it."),
        .init("liability coverage", "Pays for the other person's injuries or damage when you're at fault."),
    ]

    /// Glossary terms whose word appears in `text`, in definition order, deduped.
    static func found(in text: String) -> [GlossaryTerm] {
        guard !text.isEmpty else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return all.filter { term in
            // \b boundaries so "I-9" doesn't match inside "I-94", and casing is ignored.
            guard let rx = try? NSRegularExpression(
                pattern: "\\b" + term.pattern + "\\b", options: [.caseInsensitive]) else { return false }
            return rx.firstMatch(in: text, range: range) != nil
        }
    }
}
