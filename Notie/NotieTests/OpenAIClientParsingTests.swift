//  OpenAIClientParsingTests.swift
//
//  Tests the tolerant parsing of the model's JSON (ExtractionJSON.parse) — no
//  network. These guard the real failure mode the live smoke test exposed: the
//  model returning "confidence": "high" (a string) used to throw away the whole
//  result under strict Codable. Each field must coerce independently.
//

import Testing
import Foundation
@testable import Notie

struct OpenAIClientParsingTests {
    private func dec(_ s: String) -> Decimal { Decimal(string: s)! }

    @Test func confidenceAsStringDoesNotBreakParsing() {
        let json = #"{"sender":"IRS","confidence":"high"}"#
        let r = ExtractionJSON.parse(json)
        #expect(r != nil)
        #expect(r?.sender == "IRS")
        #expect(r?.confidence == 0.9)   // "high" → 0.9, not a decode failure
    }

    @Test func confidenceAsNumber() {
        #expect(ExtractionJSON.parse(#"{"confidence":0.8}"#)?.confidence == 0.8)
    }

    @Test func amountAsNumberOrString() {
        #expect(ExtractionJSON.parse(#"{"amount":86.42}"#)?.amount == dec("86.42"))
        #expect(ExtractionJSON.parse(#"{"amount":"1,234.56"}"#)?.amount == dec("1234.56"))
    }

    @Test func nullsAndMissingFieldsTolerated() {
        let r = ExtractionJSON.parse(#"{"amount":null,"sender":"","dueDate":"null"}"#)
        #expect(r != nil)
        #expect(r?.amount == nil)
        #expect(r?.sender == nil)        // empty string → nil
        #expect(r?.dueDate == nil)       // literal "null" string → nil
    }

    @Test func categoryMapsToEnumOrNil() {
        #expect(ExtractionJSON.parse(#"{"category":"government"}"#)?.category == .government)
        #expect(ExtractionJSON.parse(#"{"category":"UTILITY"}"#)?.category == .utility)
        #expect(ExtractionJSON.parse(#"{"category":"spaceship"}"#)?.category == nil)
    }

    @Test func repeatsParsing() {
        #expect(ExtractionJSON.parse(#"{"repeats":"monthly"}"#)?.repeats == .monthly)
        #expect(ExtractionJSON.parse(#"{"repeats":"every:30"}"#)?.repeats == .everyNDays(30))
        #expect(ExtractionJSON.parse(#"{"repeats":null}"#)?.repeats == nil)
    }

    @Test func dueDateAndStepsAndSteps() {
        let json = #"{"dueDate":"2026-07-01","steps":["Pay it.","","Save receipt."]}"#
        let r = ExtractionJSON.parse(json)
        let c = Calendar.current.dateComponents([.year, .month, .day], from: r!.dueDate!)
        #expect((c.year, c.month, c.day) == (2026, 7, 1))
        #expect(r?.steps == ["Pay it.", "Save receipt."])   // blank step dropped
    }

    @Test func otherIDsParsing() {
        let json = #"""
        {"accountNumber":"A4C33C","otherIDs":[{"label":"eTicket","value":"0162108515648"},{"value":"X9"},{"label":"empty","value":""}]}
        """#
        let r = ExtractionJSON.parse(json)
        #expect(r?.accountNumber == "A4C33C")
        #expect(r?.otherIDs == [DocID(label: "eTicket", value: "0162108515648"),
                                DocID(label: "ID", value: "X9")])   // empty value dropped; missing label → "ID"
    }

    @Test func otherIDsDefaultsToEmpty() {
        #expect(ExtractionJSON.parse(#"{"sender":"x"}"#)?.otherIDs == [])
    }

    @Test func malformedJSONReturnsNil() {
        #expect(ExtractionJSON.parse("not json at all") == nil)
        #expect(ExtractionJSON.parse("[1,2,3]") == nil)     // array, not an object
    }
}
