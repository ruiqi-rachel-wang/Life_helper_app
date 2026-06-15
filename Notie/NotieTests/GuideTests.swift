//  GuideTests.swift
//
//  The guide checklists are deterministic (build(answers:) is pure), so we can
//  unit-test the branching + answer templating with no network.
//

import Testing
import Foundation
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

    @Test func movingUnknownAddressDefersForwardingNoTempForward() {
        let steps = Guide.moving.build(["home": "Renting", "knowAddress": "Not yet"])
            .steps.joined(separator: "\n").lowercased()
        #expect(!steps.contains("temporary mail forwarding"))      // removed per feedback
        #expect(steps.contains("once you have your new address"))
    }

    @Test func movingMoveDateSetsDueDate() {
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let r = Guide.moving.build(["home": "Renting", "moveDate": GuideDate.encode(date)])
        #expect(r.dueDate == date)
        // The "set your move date as the reminder" note drops once a date is given.
        #expect(!r.notes.contains { $0.contains("Set your move date as the reminder") })
        // No date → no due date.
        #expect(Guide.moving.build(["home": "Renting"]).dueDate == nil)
    }

    @Test func movingHasNoVoterRegistrationStep() {
        let steps = Guide.moving.build(["home": "Renting", "scope": "Another state",
                                        "newState": "New York", "knowAddress": "Yes", "car": "Yes"])
            .steps.joined(separator: "\n").lowercased()
        #expect(!steps.contains("vote"))
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

    @Test func allGuidesPresent() {
        let ids = Set(Guide.all.map(\.id))
        #expect(Guide.all.count == 11)
        for id in ["taxes", "ssn_itin", "school_enrollment", "health_insurance"] {
            #expect(ids.contains(id))
        }
    }

    @Test func newGuidesLinkToOfficialSources() {
        let cases: [(String, [String: String], String)] = [
            ("taxes", [:], "irs.gov"),
            ("ssn_itin", ["which": "SSN (I can work in the U.S.)"], "ssa.gov"),
            ("health_insurance", ["source": "On my own (Marketplace)"], "healthcare.gov"),
            ("school_enrollment", ["newcomer": "Yes — new to the U.S."], "ncela.ed.gov"),
        ]
        for (id, answers, host) in cases {
            let item = ActionItem(from: Guide.all.first { $0.id == id }!.build(answers))
            let urls = item.steps.flatMap { $0.detail?.links ?? [] }.map(\.url)
            #expect(urls.contains { $0.contains(host) }, "\(id) should link \(host)")
        }
    }

    @Test func questionsHideWhenIrrelevant() {
        func visibleIDs(_ id: String, _ a: [String: String]) -> Set<String> {
            Set(Guide.all.first { $0.id == id }!.visibleQuestions(a).map(\.id))
        }
        // License "car" only for tasks with a registration; not renewal/replacement.
        #expect(visibleIDs("drivers_license", ["task": "First-time"]).contains("car"))
        #expect(!visibleIDs("drivers_license", ["task": "Renewal"]).contains("car"))
        // Moving "newState" only when moving to another state.
        #expect(!visibleIDs("moving", ["scope": "Same state"]).contains("newState"))
        #expect(visibleIDs("moving", ["scope": "Another state"]).contains("newState"))
        // Doctor "insurer" only when insured; new job "work" hidden for contractors.
        #expect(!visibleIDs("doctor_appointment", ["insurance": "No"]).contains("insurer"))
        #expect(!visibleIDs("new_job", ["type": "Contractor / 1099"]).contains("work"))
    }

    @Test func carAccidentIsAutoCategory() {
        #expect(Guide.all.first { $0.id == "car_accident" }?.category == .auto)
    }

    // MARK: provenance + AI-risk metadata

    private func guide(_ id: String) -> Guide { Guide.all.first { $0.id == id }! }

    @Test func sensitiveTopicsAreFlaggedAsSensitive() {
        for id in ["immigration", "bank_account", "doctor_appointment", "car_accident",
                   "taxes", "ssn_itin", "school_enrollment", "health_insurance"] {
            #expect(guide(id).risk == .sensitive)
        }
        #expect(guide("moving").risk == .general)
        #expect(guide("new_job").risk == .general)
    }

    @Test func guidesCarryOfficialSourceAndReviewDate() {
        #expect(guide("immigration").officialSource?.contains("uscis.gov") == true)
        #expect(guide("moving").officialSource?.contains("usps") == true)
        #expect(!guide("immigration").lastReviewed.isEmpty)
    }

    @Test func bankNoSSNAddsITINStepWithIRSLink() {
        let item = ActionItem(from: Guide.bankAccount.build(["ssn": "No — I'll use an ITIN"]))
        let itin = item.steps.first { $0.text.contains("Apply for an ITIN") }
        #expect(itin != nil)
        #expect(itin?.text.contains("Call a few banks first") == true)   // advises checking before applying
        #expect(itin?.detail?.links.contains { $0.url.contains("irs.gov") } == true)
    }

    @Test func bankCompareStepHasCFPBLink() {
        let item = ActionItem(from: Guide.bankAccount.build(["ssn": "Yes", "type": "Checking"]))
        let compare = item.steps.first { $0.text.hasPrefix("Compare banks") }
        #expect(compare?.detail?.links.contains { $0.url.contains("consumerfinance.gov") } == true)
    }

    @Test func bankCoversDeniedAndNoAddressCases() {
        let r = Guide.bankAccount.build(["ssn": "Yes", "type": "Checking"])
        let notes = r.notes.joined(separator: "\n").lowercased()
        #expect(notes.contains("second-chance"))            // denied-before path
        #expect(notes.contains("proof of address"))          // no-address path
        #expect(r.steps.joined().lowercased().contains("no-overdraft"))   // low-fee path
    }

    @Test func newJobInternshipAndSecurityNotes() {
        let intern = Guide.newJob.build(["type": "Internship", "employer": "Acme"])
        #expect(intern.notes.contains { $0.lowercased().contains("paid internships") })
        // Security note appears for any employee-type role.
        #expect(intern.notes.contains { $0.contains("official HR portal") })
        #expect(intern.steps.contains { $0.contains("first paycheck") })
    }

    @Test func immigrationRenamedAndScopedConservatively() {
        let g = Guide.all.first { $0.id == "immigration" }!
        #expect(g.title == "USCIS paperwork")
        let r = g.build(["task": "Apply for citizenship"])
        #expect(r.notes.contains { $0.contains("doesn't cover every visa type") })
    }

    @Test func immigrationCitizenshipUsesN400Link() {
        let item = ActionItem(from: Guide.immigration.build(["task": "Apply for citizenship"]))
        let n400 = item.steps.first { $0.detail?.links.contains { $0.url == "https://www.uscis.gov/n-400" } == true }
        #expect(n400 != nil)
        #expect(n400?.text.contains("File Form N-400") == true)
    }

    @Test func emergencyGuidesPut911OnTheBannerNotInSteps() {
        for id in ["car_accident", "doctor_appointment"] {
            let g = Guide.all.first { $0.id == id }!
            #expect(g.emergencyNote?.contains("911") == true)        // 911 is on the first page
            // ...and never inside the checklist steps, for any answer combination.
            let answers = id == "car_accident"
                ? [["injuries": "No", "fault": "Me"], ["injuries": "Yes", "fault": "The other driver"], ["injuries": "Not sure", "fault": "Not sure / shared"]]
                : [["new": "New patient", "kind": "dentist"], ["insurance": "No", "kind": "primary care"]]
            for a in answers {
                #expect(!g.build(a).steps.joined(separator: "\n").contains("911"))
            }
        }
    }

    @Test func everyStateDMVLinkIsOfficial() {
        for s in USStates.all {
            let host = URL(string: Guide.dmvURL(s))?.host ?? ""
            #expect(host.hasSuffix(".gov") || host.hasSuffix(".us"),
                    "Non-official DMV link for \(s): \(Guide.dmvURL(s))")
        }
    }

    @Test func carAccidentHitAndRunUsesUninsuredMotorist() {
        let steps = Guide.carAccident.build(["what": "Hit-and-run (they left)"]).steps.joined(separator: "\n").lowercased()
        #expect(steps.contains("hit-and-run"))           // police report required
        #expect(steps.contains("uninsured-motorist"))    // claim path
    }

    @Test func carAccidentClaimVariesByWhatHappened() {
        let otherHit = Guide.carAccident.build(["what": "The other driver hit me"]).steps.joined(separator: "\n")
        #expect(otherHit.contains("the other driver's insurer"))   // neutral wording, not "at-fault"
        #expect(!otherHit.lowercased().contains("at-fault"))
        let single = Guide.carAccident.build(["what": "Single-car accident"]).steps.joined(separator: "\n")
        #expect(single.contains("your own insurer"))
        #expect(otherHit.lowercased().contains("repair"))          // full arc → repair
    }

    @Test func carAccidentTowAndLeftSceneBranches() {
        let tow = Guide.carAccident.build(["drivable": "No — needs a tow"]).steps.joined(separator: "\n").lowercased()
        #expect(tow.contains("tow"))
        let later = Guide.carAccident.build(["when": "Earlier — I've left"]).steps.joined(separator: "\n").lowercased()
        #expect(!later.contains("move to safety"))        // skips at-scene steps
        #expect(later.contains("police report"))
    }

    @Test func carAccidentUninsuredAndNoFaultNotes() {
        let r = Guide.carAccident.build(["other": "Yes", "fault": "The other driver"])
        let notes = r.notes.joined(separator: "\n").lowercased()
        #expect(notes.contains("uninsured-motorist"))     // other-driver-uninsured fallback
        #expect(notes.contains("no-fault"))
    }

    @Test func doctorWithInsurerNamesItButKeepsLinkOfficial() {
        let item = ActionItem(from: Guide.doctorAppointment.build(
            ["insurance": "Yes", "insurer": "Aetna", "new": "New patient", "kind": "dentist"]))
        let find = item.steps.first { $0.text.contains("in-network") }
        #expect(find?.text.contains("Aetna") == true)                               // insurer named in the step
        #expect(find?.detail?.links.allSatisfy { $0.url.contains(".gov") } == true)  // but every link stays official
    }

    @Test func noGuideLinksToNonOfficialSites() {
        // Every authored link across all guides must be a government (.gov/.us) site.
        for guide in Guide.all {
            let item = ActionItem(from: guide.build([:]))
            for step in item.steps {
                for link in step.detail?.links ?? [] {
                    let host = URL(string: link.url)?.host ?? ""
                    #expect(host.hasSuffix(".gov") || host.hasSuffix(".us"),
                            "Non-official link in \(guide.id): \(link.url)")
                }
            }
        }
    }

    @Test func doctorFindStepHasHealthcareLink() {
        let item = ActionItem(from: Guide.doctorAppointment.build(["new": "New patient", "kind": "dentist"]))
        let find = item.steps.first { $0.text.contains("in-network") }
        #expect(find?.detail?.links.contains { $0.url.contains("healthcare.gov") } == true)
        #expect(find?.text.contains("dentist") == true)   // templated
    }

    // MARK: Save-items now live in item-level DETAILS (otherIDs), not step fields

    @Test func carAccidentSavesClaimDetails() {
        let item = ActionItem(from: Guide.carAccident.build([:]))
        #expect(item.otherIDs.contains { $0.label == "Claim number" })
    }

    @Test func doctorReturnVisitSkipsFindAndBring() {
        let newp = Guide.doctorAppointment.build(["insurance": "Yes", "new": "New patient", "kind": "dentist"]).steps.joined(separator: "\n")
        #expect(newp.contains("in-network"))            // new patient: find a doctor
        #expect(newp.contains("Bring your insurance card"))   // and bring card + ID

        let ret = Guide.doctorAppointment.build(["insurance": "Yes", "new": "Return visit", "kind": "dentist"]).steps.joined(separator: "\n")
        #expect(!ret.lowercased().contains("in-network"))     // return: no need to find one
        #expect(!ret.contains("Bring your insurance card"))   // already on file
        #expect(ret.contains("book your visit"))
    }

    @Test func doctorSavesProviderDetails() {
        let item = ActionItem(from: Guide.doctorAppointment.build(["new": "New patient", "kind": "dentist"]))
        #expect(item.otherIDs.contains { $0.label == "Provider name" })
    }

    @Test func immigrationSavesReceiptNumber() {
        let item = ActionItem(from: Guide.immigration.build(["task": "Check my case status"]))
        #expect(item.otherIDs.contains { $0.label == "Receipt number" })
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
        #expect(gather?.detail?.miniChecklist.contains { $0.text.contains("SSN") } == true)
        #expect(gather?.detail?.miniChecklist.contains { $0.text.contains("lawful presence") } == true)
    }

    @Test func newJobI9StepHasDocumentsAndLink() {
        let item = ActionItem(from: Guide.newJob.build(["type": "W-2 employee", "employer": "Acme"]))
        let i9 = item.steps.first { $0.text.contains("Form I-9") }
        #expect(i9?.hasDetail == true)
        #expect(i9?.detail?.links.contains { $0.url.contains("uscis.gov") } == true)
    }
}
