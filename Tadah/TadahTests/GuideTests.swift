//  GuideTests.swift
//
//  The guide checklists are deterministic (build(answers:) is pure), so we can
//  unit-test the branching + answer templating with no network.
//

import Testing
import Foundation
@testable import Tadah

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

    @Test func rentingCoversLeaseDepositUtilitiesInsurance() {
        let r = Guide.rentingNewPlace.build(["signed": "Not yet"])
        let steps = r.steps.joined(separator: "\n").lowercased()
        #expect(r.category == .housing)
        #expect(steps.contains("lease"))
        #expect(steps.contains("deposit"))
        #expect(steps.contains("renters insurance"))
        #expect(r.detailedSteps.contains { $0.detail != nil })   // utility step has detail
    }

    @Test func buyingCoversOnlyPreApprovalThroughOffer() {
        // The guide is a single path now — no stage question — and stops at an
        // accepted offer; inspection/closing is a separate follow-up guide the
        // user starts once they actually have an offer.
        let buying = Guide.buyingHome.build([:])
        let s = buying.steps.joined(separator: "\n").lowercased()
        #expect(s.contains("pre-approved"))
        #expect(s.contains("make an offer"))
        #expect(!s.contains("inspection"))
        #expect(!s.contains("closing disclosure"))
        // Must NOT tell the user to open a Closing guide that doesn't exist yet.
        #expect(buying.notes.contains { $0.lowercased().contains("after your offer is accepted") })
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
        #expect(Guide.all.count == 14)
        for id in ["taxes", "ssn_itin", "school_enrollment", "health_insurance",
                   "moving", "renting", "buying", "start_business"] {
            #expect(ids.contains(id))
        }
    }

    @Test func newGuidesLinkToOfficialSources() {
        let cases: [(String, [String: String], String)] = [
            ("taxes", [:], "irs.gov"),
            ("ssn_itin", ["which": "SSN (I can work in the U.S.)"], "ssa.gov"),
            ("health_insurance", ["source": "On my own (Marketplace)"], "healthcare.gov"),
            ("school_enrollment", ["newcomer": "Yes — new to the U.S."], "ncela.ed.gov"),
            ("start_business", [:], "sba.gov"),
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
                   "taxes", "ssn_itin", "school_enrollment", "health_insurance",
                   "start_business", "new_job"] {
            #expect(guide(id).risk == .sensitive)
        }
        #expect(guide("moving").risk == .general)
    }

    @Test func guidesCarryStructuredOfficialSource() {
        let uscis = guide("immigration").source
        #expect(uscis?.domain == "uscis.gov")
        #expect(uscis?.jurisdiction == .federal)
        #expect(guide("moving").source?.domain == "usps.com")
        // A guide whose facts vary by state is marked per-state, not federal.
        #expect(guide("drivers_license").source?.jurisdiction == .perState)
    }

    @Test func everyGuideHasAnAuditableHttpsSource() {
        for g in Guide.all {
            #expect(g.source != nil, "\(g.id) is missing a source citation")
            #expect(g.source?.url.hasPrefix("https://") == true, "\(g.id) source url not https")
            #expect(g.source?.domain.isEmpty == false, "\(g.id) source domain empty")
        }
    }

    @Test func bankNoSSNAddsITINStepWithIRSLink() {
        // The answer value is "No SSN", not "No — I'll use an ITIN": the old option
        // presumed an ITIN was the answer, when in fact many banks and credit
        // unions open accounts without an SSN at all (CFPB). This test caught the
        // rename by producing NO itin step — a build closure comparing against a
        // retired string fails silently, so the value belongs in a test.
        let item = ActionItem(from: Guide.bankAccount.build(["ssn": "No SSN"]))
        let itin = item.steps.first { $0.text.contains("Apply for an ITIN") }
        #expect(itin != nil)
        // Leads with "you don't need one", then what to ask — the step must not
        // send someone to apply for an ITIN they may not need.
        #expect(itin?.text.contains("do not need one") == true)
        #expect(itin?.text.contains("Call a few first") == true)
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
        // "Internship" was retired as an option: it isn't a tax classification, and
        // picking it routed an unpaid intern through W-2 paperwork. The value is
        // now "Unpaid" — a rename that would otherwise fail silently, since the
        // build closure compares against a string literal.
        let intern = Guide.newJob.build(["type": "Unpaid", "employer": "Acme"])
        #expect(intern.notes.contains { $0.lowercased().contains("no tax forms") })
        // Security note appears for any employee-type role.
        #expect(intern.notes.contains { $0.contains("official HR portal") })
    }

    // AN UNPAID ROLE MUST NOT GET THE PAID-EMPLOYEE CHECKLIST.
    //
    // This test previously asserted the OPPOSITE — it required an unpaid intern to
    // be handed "Check your first paycheck" — so the contradiction was pinned in
    // place: the steps said file a W-4 and check your pay rate while the note
    // underneath said there is no pay and no tax form.
    @Test func unpaidRoleGetsNoPayrollOrTaxWithholdingSteps() {
        let unpaid = Guide.newJob.build(["type": "Unpaid", "employer": "Acme"]).steps.joined(separator: "\n")
        #expect(!unpaid.contains("first paycheck"))
        #expect(!unpaid.contains("direct deposit"))
        // It may MENTION the W-4 to say there isn't one; it must never instruct
        // the user to complete one.
        #expect(!unpaid.contains("Complete Form I-9"))
        #expect(!unpaid.contains("and Form W-4 (tax withholding)"))
        #expect(!unpaid.lowercased().contains("benefits (health"))
        // It gets the thing that actually matters instead: pin down what the role is.
        #expect(unpaid.lowercased().contains("volunteer"))

        // A paid W-2 role is untouched.
        let paid = Guide.newJob.build(["type": "W-2 employee", "employer": "Acme"]).steps.joined(separator: "\n")
        #expect(paid.contains("first paycheck"))
        #expect(paid.contains("W-4"))
    }

    // Removing conditions and replacing a card are DIFFERENT filings, and the card
    // term alone doesn't decide which. A conditional resident with a lost card
    // files I-90; one with an expiring card must not.
    @Test func greenCardRoutesOnReasonNotJustCardTerm() {
        func steps(_ a: [String: String]) -> String {
            Guide.immigration.build(a).steps.joined(separator: "\n")
        }
        let base = ["task": "Renew or replace green card"]

        let expiringConditional = steps(base.merging(["cardYears": "2 years", "reason": "Expiring or expired"]) { _, b in b })
        #expect(expiringConditional.contains("I-751"))
        #expect(expiringConditional.contains("Do NOT file Form I-90"))

        // Lost/stolen/damaged is I-90 even on a 2-year card.
        let lostConditional = steps(base.merging(["cardYears": "2 years", "reason": "Lost, stolen, or damaged"]) { _, b in b })
        #expect(lostConditional.contains("File Form I-90"))
        #expect(lostConditional.contains("I-751"))   // …with the expiry caveat attached

        // "Not sure" must not quietly become I-90 with no warning.
        let unsure = steps(base.merging(["cardYears": "Not sure"]) { _, b in b })
        #expect(unsure.contains("CONDITIONAL"))

        // The 90-day window is the JOINT-filing rule, not a blanket one.
        #expect(expiringConditional.contains("waiver"))
    }

    // The USCIS address warning is the highest-cost thing in the moving guide to
    // miss, and a misplaced brace hid it from everyone who knew their new address.
    @Test func uscisAddressWarningShowsRegardlessOfKnowingTheAddress() {
        for knows in ["Yes", "Not yet"] {
            let s = Guide.moving.build(["home": "Renting", "scope": "Same state",
                                        "knowAddress": knows, "car": "No"]).steps.joined(separator: "\n")
            #expect(s.contains("USPS forwarding does NOT update USCIS"))
        }
    }

    // A hit-and-run means the other driver is UNIDENTIFIED, not uninsured, and the
    // step has to tell you to call your own insurer.
    @Test func hitAndRunClaimStepIsAboutYourOwnInsurer() {
        let r = Guide.carAccident.build(["what": "Hit-and-run (they left)"])
        let steps = r.steps.joined(separator: "\n")
        #expect(steps.contains("Report it to your own insurer"))
        #expect(!steps.contains("If the other driver is uninsured, ask your insurer"))
        // Never state the police report as universally required.
        #expect(!steps.lowercased().contains("it's required for a hit-and-run claim"))
        // UM is the coverage that answers a hit-and-run, so the note belongs here.
        #expect(r.notes.contains { $0.contains("uninsured-motorist") })
    }

    // A `hasPrefix` matcher fails SILENTLY when the copy it mirrors is reworded —
    // the step keeps rendering, just with no detail and no official link. This one
    // had been dead for a while: the builder says "Start your SSN application…"
    // while the matcher still looked for "Apply for an SSN online".
    @Test func everyAuthoredStepDetailActuallyAttaches() {
        let ssn = Guide.ssnItin.build(["which": "SSN"])
        let apply = ssn.detailedSteps.first { $0.text.hasPrefix("Start your SSN application") }
        #expect(apply?.hasDetail == true)
        #expect(apply?.detail?.links.contains { $0.url.contains("ssa.gov") } == true)
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

    // MARK: Start a business — structure / goods / hiring branches

    @Test func startBusinessLLCFilesWithStateAndGetsEIN() {
        let item = ActionItem(from: Guide.startBusiness.build(
            ["kind": "Online store (e-commerce)", "structure": "LLC", "employees": "No", "state": "Texas"]))
        let steps = item.steps.map(\.text).joined(separator: "\n")
        #expect(steps.contains("Form your LLC"))
        #expect(steps.contains("Secretary of State"))                 // LLC files with the state (de-interpolated for on-device localization)
        #expect(steps.lowercased().contains("sales-tax permit"))       // sells goods
        #expect(!steps.lowercased().contains("hiring?"))              // no employees
        let ein = item.steps.first { $0.text.hasPrefix("Get a free EIN") }
        #expect(ein?.detail?.links.contains { $0.url.contains("irs.gov") } == true)
    }

    @Test func startBusinessSoleProprietorSkipsLLCFiling() {
        let steps = Guide.startBusiness.build(
            ["kind": "Freelance / solo service", "structure": "Just me (sole proprietor)", "state": "Ohio"])
            .steps.joined(separator: "\n")
        #expect(steps.contains("As a sole proprietor"))
        #expect(!steps.contains("Form your LLC"))
        #expect(!steps.lowercased().contains("sales-tax permit"))     // a service, no goods
    }

    @Test func startBusinessHiringAndRestaurantAddSteps() {
        let steps = Guide.startBusiness.build(
            ["kind": "Physical shop or restaurant", "structure": "LLC", "employees": "Yes", "state": "Utah"])
            .steps.joined(separator: "\n")
        #expect(steps.contains("Hiring?"))                            // employees branch
        #expect(steps.lowercased().contains("health permit"))         // restaurant branch
    }

    @Test func everyStateDMVLinkIsOfficial() {
        for s in USStates.all {
            let host = URL(string: Guide.dmvURL(s))?.host ?? ""
            #expect(host.hasSuffix(".gov") || host.hasSuffix(".us"),
                    "Non-official DMV link for \(s): \(Guide.dmvURL(s))")
        }
    }

    // Renamed from …UsesUninsuredMotorist: the guide no longer names UM, PIP,
    // collision or comprehensive. Which coverage applies depends on the state and
    // the policy, and this is read minutes after a crash — so it says report it and
    // ask. What must survive is the ACTION: report to police, keep the number.
    @Test func carAccidentHitAndRunTellsYouToReportAndKeepTheNumber() {
        let steps = Guide.carAccident.build(["what": "Hit-and-run (they left)"]).steps.joined(separator: "\n").lowercased()
        #expect(steps.contains("hit-and-run"))
        #expect(steps.contains("report number"))         // evidence to keep
        #expect(!steps.contains("uninsured-motorist"))   // no coverage teaching
        #expect(!steps.contains("collision or comprehensive"))
    }

    @Test func carAccidentClaimVariesByWhatHappened() {
        let otherHit = Guide.carAccident.build(["what": "The other driver hit me"]).steps.joined(separator: "\n")
        #expect(otherHit.contains("the other driver's insurer"))   // neutral wording, not "at-fault"
        #expect(!otherHit.lowercased().contains("at-fault"))
        // The guide no longer names specific coverages (collision / comprehensive /
        // PIP) — those vary by state and policy, and this is read right after a
        // crash. It says report it and ask which coverage applies.
        let single = Guide.carAccident.build(["what": "Single-car accident"]).steps.joined(separator: "\n")
        #expect(single.lowercased().contains("your insurer"))
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
        // Both notes now point at the insurer rather than teaching UM / no-fault /
        // PIP, which depend on the state and the policy.
        #expect(notes.contains("uninsured"))
        #expect(!notes.contains("no-fault"))
        #expect(notes.contains("ask your insurer"))
    }

    @Test func doctorInNetworkStepKeepsLinkOfficial() {
        let item = ActionItem(from: Guide.doctorAppointment.build(
            ["insurance": "Yes", "insurer": "Aetna", "new": "New patient", "kind": "dentist"]))
        let find = item.steps.first { $0.text.contains("in-network") }
        // Step text is de-interpolated (no insurer/kind spliced in) so it can be
        // translated on-device; the point is the step exists and links stay official.
        #expect(find != nil)
        #expect(find?.detail?.links.allSatisfy { $0.url.contains(".gov") } == true)
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

    // THE FREE-QUOTA GATE MUST MATCH WHAT ACTUALLY SPENDS A SCAN.
    //
    // GuidesView blocks a guide before building it; the charge (ScanQuota.record)
    // happens only when there is a utilities step for a real ZIP to personalize.
    // "Buying a home" used to satisfy the gate's old rule — general guide + valid
    // ZIP — while having no utilities step at all, so a free user out of scans was
    // turned away from a checklist that would never have called the AI. Its ZIP
    // question is gone, and the gate now asks the built checklist.
    @MainActor
    @Test func onlyGuidesThatReallyCallTheAISpendAScan() {
        // Renting has the utilities step: a real ZIP does spend one.
        #expect(Guide.rentingNewPlace.usesScanQuota(for: ["zip": "78701"]))
        // …and no ZIP means no lookup, so it doesn't.
        #expect(!Guide.rentingNewPlace.usesScanQuota(for: [:]))
        #expect(!Guide.rentingNewPlace.usesScanQuota(for: ["zip": "not a zip"]))

        // Buying is pre-offer — no utilities step, and no ZIP question any more.
        #expect(!Guide.buyingHome.usesScanQuota(for: ["zip": "78701"]))
        #expect(!Guide.buyingHome.questions.contains { $0.id == "zip" })

        // Questions that were asked and then never read are gone too.
        #expect(!Guide.schoolEnrollment.questions.contains { $0.id == "state" })
        #expect(!Guide.healthInsurance.questions.contains { $0.id == "state" })
    }

    @Test func utilitiesDetailBreaksOutEachUtility() {
        // The shared utilities detail must name each utility on its own line
        // (electricity, gas, water, internet/WiFi) — not bundle them together.
        let lines = Guide.utilitiesDetail.miniChecklist.map { $0.text.lowercased() }
        for utility in ["electricity", "gas", "water", "internet"] {
            #expect(lines.contains { $0.contains(utility) })
        }
    }

    @Test func zipUtilitiesDetailNamesProvidersWithContacts() {
        let providers = [
            LocalUtility(kind: "Electricity", name: "Austin Energy",
                         website: "austinenergy.com", phone: "512-494-9400", inPerson: nil),
            LocalUtility(kind: "Internet", name: "Google Fiber",
                         website: "fiber.google.com", phone: nil, inPerson: nil),
        ]
        let detail = Guide.utilitiesDetail(forZip: "78701", providers: providers)
        let lines = detail?.miniChecklist.map(\.text) ?? []
        // Names + their contact methods appear; the verify caveat leads.
        #expect(lines.first?.contains("78701") == true)
        #expect(lines.contains { $0.contains("Austin Energy") && $0.contains("austinenergy.com") && $0.contains("512-494-9400") })
        #expect(lines.contains { $0.contains("Google Fiber") })
        // Empty lookup → nil, so the caller keeps the generic detail.
        #expect(Guide.utilitiesDetail(forZip: "78701", providers: []) == nil)
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

    // MARK: language — every guide, every step, on the device

    // A step that splices in a value travels as format + value (StepFormat) so the
    // FORMAT can be the catalog key. Localizing must put the value back.
    @Test func packedStepsSpliceTheirValueBackInOnLocalize() {
        let r = Guide.driversLicense
            .build(["task": "Out-of-state transfer", "state": "New York", "car": "Yes"])
            .localized(.english)
        let steps = r.steps.joined(separator: "\n")
        #expect(steps.contains("Exchange your out-of-state license for a New York license"))
        #expect(steps.contains("Register your out-of-state vehicle in New York"))
        #expect(!steps.contains(StepFormat.separator))
    }

    // Belt and braces: even a result that never went through `localized`, the
    // separator must never reach storage (and therefore the screen).
    @Test func savedItemNeverCarriesAFormatSeparator() {
        for guide in Guide.all {
            let answers = ["state": "Ohio", "newState": "Ohio", "employer": "Acme",
                           "task": "First-time", "scope": "Another state", "car": "Yes"]
            let item = ActionItem(from: guide.build(answers))
            #expect(!item.steps.contains { $0.text.contains(StepFormat.separator) },
                    "\(guide.id) leaked a step-format separator")
        }
    }

    // THE regression test for the mixed-language guide (Chinese title, Chinese step
    // details, English steps). Guide steps used to be translated only by the AI, so
    // any slow or failed call left them in English. They now come from the String
    // Catalog, so every step of every guide must contain Chinese characters.
    @Test func everyGuideStepIsTranslatedIntoChinese() {
        let answers = ["state": "Ohio", "newState": "Ohio", "employer": "Acme",
                       "task": "First-time", "scope": "Another state", "car": "Yes",
                       "home": "Renting", "knowAddress": "Yes"]
        let hasChinese = { (s: String) in s.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } }
        for guide in Guide.all {
            let r = guide.build(answers).localized(.chinese)
            for step in r.steps {
                #expect(hasChinese(step), "\(guide.id) step left untranslated: \(step)")
            }
            // NOTES TOO. This checked only `steps`, and the notes are where the
            // caveats live — "this doesn't cover every visa type", "unpaid roles
            // have no tax forms", the territory scope. A reader who needs the
            // translation needs those most, and an untranslated one was invisible
            // to the suite.
            for note in r.notes {
                #expect(hasChinese(note), "\(guide.id) note left untranslated: \(note)")
            }
        }
    }

    // The same coverage, on the branches the fixed answer set above never reaches.
    // Every one of these is a path a real user takes, and each was reworded on
    // 2026-08-16 — a reworded step silently falls back to English if nobody adds
    // the catalog entry, which is exactly how it would ship broken.
    @Test func rewordedBranchesAreTranslatedToo() {
        let hasChinese = { (s: String) in s.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } }
        let cases: [(Guide, [String: String])] = [
            (Guide.newJob, ["type": "Unpaid", "employer": "Acme"]),
            (Guide.newJob, ["type": "Contractor / 1099", "employer": "Acme"]),
            (Guide.immigration, ["task": "Renew or replace green card", "cardYears": "2 years",
                                 "reason": "Expiring or expired"]),
            (Guide.immigration, ["task": "Renew or replace green card", "cardYears": "2 years",
                                 "reason": "Lost, stolen, or damaged"]),
            (Guide.immigration, ["task": "Renew or replace green card", "cardYears": "Not sure"]),
            (Guide.carAccident, ["what": "Hit-and-run (they left)"]),
            (Guide.bankAccount, ["ssn": "No SSN"]),
            (Guide.bankAccount, ["ssn": "Not sure"]),
            (Guide.healthInsurance, ["source": "On my own (Marketplace)", "lifeEvent": "Yes"]),
            (Guide.startBusiness, ["kind": "Online store (e-commerce)", "structure": "LLC",
                                   "employees": "Not yet", "state": "Ohio"]),
            (Guide.buyingHome, ["stage": "Working with an agent", "firstTime": "Yes"]),
        ]
        for (guide, answers) in cases {
            let r = guide.build(answers).localized(.chinese)
            for line in r.steps + r.notes {
                #expect(hasChinese(line), "\(guide.id) \(answers) left untranslated: \(line)")
            }
        }
    }
}
