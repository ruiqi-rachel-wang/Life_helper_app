//  GlossaryTests.swift
//
//  The glossary auto-detects jargon in step text and explains it in plain English.
//

import Testing
@testable import Tadah

struct GlossaryTests {

    @Test func findsFormCodesAndExplainsThem() {
        let terms = Glossary.found(in: "Complete Form I-9 and bring your SSN or an ITIN.")
        let labels = terms.map(\.term)
        #expect(labels.contains("I-9"))
        #expect(labels.contains("SSN"))
        #expect(labels.contains("ITIN"))
    }

    @Test func wordBoundaryStopsI9MatchingInsideI94() {
        let terms = Glossary.found(in: "Bring your I-94 record.").map(\.term)
        #expect(terms.contains("I-94"))
        #expect(!terms.contains("I-9"))     // must not match the prefix
    }

    @Test func caseInsensitiveButNoFalsePositives() {
        // "premium" should match; an unrelated sentence should find nothing.
        #expect(Glossary.found(in: "Your monthly PREMIUM is due.").map(\.term).contains("premium"))
        #expect(Glossary.found(in: "Take out the trash on Tuesday.").isEmpty)
    }

    @Test func resultsAreDedupedAndOrdered() {
        let terms = Glossary.found(in: "deductible, deductible, and your premium")
        #expect(terms.map(\.term) == ["deductible", "premium"])   // definition order, no dupes
    }
}
