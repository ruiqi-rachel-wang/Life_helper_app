//  GuideTests.swift
//
//  The guide checklists are deterministic (build(answers:) is pure), so we can
//  unit-test the branching + answer templating with no network.
//

import Testing
@testable import Notie

struct GuideTests {

    // MARK: Moving

    @Test func movingRentingAnotherStateWithCar() {
        let r = Guide.moving.build([
            "home": "Renting", "scope": "Another state",
            "newState": "New York", "knowAddress": "Yes", "car": "Yes",
        ])
        let steps = r.steps.joined(separator: "\n")
        #expect(r.category == .housing)
        #expect(steps.contains("New York"))                 // state templated in
        #expect(steps.contains("landlord"))                  // renter branch
        #expect(steps.contains("renters insurance"))
        #expect(steps.lowercased().contains("plates"))       // car + cross-state
        #expect(steps.contains("usps.com/move"))
    }

    @Test func movingOwnIncludesMortgageNotLandlord() {
        let steps = Guide.moving.build(["home": "Own my home", "scope": "Same state", "car": "No"])
            .steps.joined(separator: "\n")
        #expect(steps.contains("mortgage"))
        #expect(!steps.contains("landlord"))
    }

    @Test func movingUnknownAddressUsesTemporaryForwarding() {
        let steps = Guide.moving.build(["home": "Renting", "knowAddress": "Not yet"])
            .steps.joined(separator: "\n").lowercased()
        #expect(steps.contains("temporary mail forwarding"))
        #expect(!steps.contains("usps.com/move"))
    }

    // MARK: New job — W-2 vs contractor branch

    @Test func newJobW2HasI9W4AndDirectDeposit() {
        let steps = Guide.newJob.build(["type": "W-2 employee", "employer": "Acme Co", "work": "Remote"])
            .steps.joined(separator: "\n")
        #expect(steps.contains("Acme Co"))
        #expect(steps.contains("I-9"))
        #expect(steps.lowercased().contains("direct deposit"))
        #expect(steps.lowercased().contains("equipment"))    // remote → equipment
    }

    @Test func newJobContractorUsesW9NotI9() {
        let steps = Guide.newJob.build(["type": "Contractor / 1099", "employer": "Acme"])
            .steps.joined(separator: "\n")
        #expect(steps.contains("W-9"))
        #expect(!steps.contains("Complete Form I-9"))   // no W-2 I-9/W-4 requirement
        #expect(steps.lowercased().contains("quarterly"))
    }

    @Test func newJobNotSureAddsClarifyNote() {
        let r = Guide.newJob.build(["type": "Not sure", "employer": "Acme"])
        #expect(r.notes.contains { $0.contains("W-2 employee or a 1099") })
    }

    // MARK: Driver's license — task branches

    @Test func licenseOutOfStateTransfer() {
        let steps = Guide.driversLicense.build(["task": "Out-of-state transfer", "state": "New York", "car": "Yes"])
            .steps.joined(separator: "\n")
        #expect(steps.contains("Exchange your out-of-state license"))
        #expect(steps.contains("New York"))
        #expect(steps.lowercased().contains("register your out-of-state vehicle"))
    }

    @Test func licenseFirstTimeDiffersFromRenewal() {
        let first = Guide.driversLicense.build(["task": "First-time", "state": "Texas"]).steps.joined(separator: "\n")
        let renew = Guide.driversLicense.build(["task": "Renewal", "state": "Texas"]).steps.joined(separator: "\n")
        #expect(first.contains("road test"))
        #expect(renew.lowercased().contains("renew"))
        #expect(first != renew)
    }

    @Test func emptyAnswersFallBackToDefaults() {
        let steps = Guide.driversLicense.build([:]).steps.joined(separator: "\n")
        #expect(steps.contains("your state"))   // default fill, no crash
    }
}
