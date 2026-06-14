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

    // MARK: new guides

    @Test func allSevenGuidesPresent() {
        #expect(Guide.all.count == 7)
    }

    @Test func bankNoSSNAddsITINStepWithIRSLink() {
        let item = ActionItem(from: Guide.bankAccount.build(["ssn": "No — I'll use an ITIN", "type": "Checking"]))
        let itin = item.steps.first { $0.text.contains("Form W-7") }
        #expect(itin != nil)
        #expect(itin?.detail?.links.contains { $0.url.contains("irs.gov") } == true)
    }

    @Test func immigrationCitizenshipUsesN400Link() {
        let item = ActionItem(from: Guide.immigration.build(["task": "Apply for citizenship"]))
        let n400 = item.steps.first { $0.text.contains("N-400") }
        #expect(n400?.detail?.links.contains { $0.url == "https://www.uscis.gov/n-400" } == true)
    }

    @Test func carAccidentWithInjuriesCalls911() {
        let steps = Guide.carAccident.build(["injuries": "Yes", "police": "Yes"]).steps
        #expect(steps.first?.contains("911") == true)
    }

    @Test func doctorFindStepHasHealthcareLink() {
        let item = ActionItem(from: Guide.doctorAppointment.build(["new": "New patient", "kind": "dentist"]))
        let find = item.steps.first { $0.text.contains("in-network") }
        #expect(find?.detail?.links.contains { $0.url.contains("healthcare.gov") } == true)
        #expect(find?.text.contains("dentist") == true)   // templated
    }

    // MARK: Step detail (guides only)

    @Test func movingInternetStepCarriesDetailIntoActionItem() {
        let r = Guide.moving.build(["home": "Renting", "scope": "Same state",
                                    "knowAddress": "Yes", "car": "No"])
        // The utilities/internet milestone has authored detail; others don't.
        #expect(r.detailedSteps.contains { $0.hasDetail })

        let item = ActionItem(from: r)
        let internet = item.steps.first { $0.text.contains("utilities and internet") }
        #expect(internet?.hasDetail == true)
        #expect(internet?.detail?.miniChecklist.contains { $0.text.lowercased().contains("provider") } == true)
    }

    @Test func licenseGatherStepHasDocumentsChecklist() {
        let item = ActionItem(from: Guide.driversLicense.build(["task": "First-time", "state": "Ohio"]))
        let gather = item.steps.first { $0.text.contains("Gather proof") }
        #expect(gather?.hasDetail == true)
        #expect(gather?.detail?.miniChecklist.contains { $0.text.contains("Social Security") } == true)
    }

    @Test func newJobI9StepHasDocumentsAndLink() {
        let item = ActionItem(from: Guide.newJob.build(["type": "W-2 employee", "employer": "Acme"]))
        let i9 = item.steps.first { $0.text.contains("Form I-9") }
        #expect(i9?.hasDetail == true)
        #expect(i9?.detail?.links.contains { $0.url.contains("uscis.gov") } == true)
    }
}
