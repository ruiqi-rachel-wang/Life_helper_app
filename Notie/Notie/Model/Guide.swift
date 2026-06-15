//  Guide.swift
//
//  Adaptive life guides (Week 7). Each guide is HARDCODED and deterministic:
//  a few questions whose answers pick/fill a base checklist. The structure is
//  never decided by AI — only the optional polish pass (OpenAIClient.polish, and
//  only for non-sensitive guides) rewords it. `build(answers:)` is pure → easy to
//  unit-test.
//
//  UI-free: a guide carries an `ItemCategory` (the view derives color/symbol via
//  ItemStyle), and `build` returns the shared `ExtractionResult`, so guides feed
//  the same Review screen scans use.
//

import Foundation

// One hardcoded question. `choice` = pick one option; `text` = free input;
// `state` = pick a US state from a list (states are too many for pills).
nonisolated struct GuideQuestion: Identifiable, Equatable {
    enum Kind: Equatable { case choice([String]); case text(String); case state; case date }
    let id: String
    let prompt: String
    let kind: Kind
}

// A `.date` answer is stored in the answers dict as a time-interval string.
// These helpers keep encode/decode in one place.
nonisolated enum GuideDate {
    static func encode(_ d: Date) -> String { String(d.timeIntervalSinceReferenceDate) }
    static func decode(_ s: String?) -> Date? {
        guard let s, let t = Double(s) else { return nil }
        return Date(timeIntervalSinceReferenceDate: t)
    }
}

// How careful we are with a guide's topic. `.sensitive` (immigration, money,
// medical, legal) NEVER goes to the AI polish pass — it stays on the device.
nonisolated enum GuideRisk { case general, sensitive }

nonisolated struct Guide: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let category: ItemCategory
    let questions: [GuideQuestion]
    // Deterministic: answers (questionID → chosen option / typed text / state) →
    // a tailored ExtractionResult (the AI polish is a separate pass).
    let build: ([String: String]) -> ExtractionResult

    // Provenance / safety metadata (review-team requested). lastReviewed is when a
    // human last checked this guide's facts against the official source.
    var officialSource: String? = nil       // primary official site (label form)
    var lastReviewed: String = "June 2026"
    var risk: GuideRisk = .general
    // Shown as a prominent banner on the guide's FIRST page (the questions screen)
    // — e.g. "call 911 if this is an emergency" — so urgent help never hides inside
    // the checklist. nil for guides with no emergency dimension.
    var emergencyNote: String? = nil
}

// US states + DC for the `.state` question kind.
nonisolated enum USStates {
    static let all = [
        "Alabama", "Alaska", "Arizona", "Arkansas", "California", "Colorado",
        "Connecticut", "Delaware", "District of Columbia", "Florida", "Georgia",
        "Hawaii", "Idaho", "Illinois", "Indiana", "Iowa", "Kansas", "Kentucky",
        "Louisiana", "Maine", "Maryland", "Massachusetts", "Michigan", "Minnesota",
        "Mississippi", "Missouri", "Montana", "Nebraska", "Nevada", "New Hampshire",
        "New Jersey", "New Mexico", "New York", "North Carolina", "North Dakota",
        "Ohio", "Oklahoma", "Oregon", "Pennsylvania", "Rhode Island",
        "South Carolina", "South Dakota", "Tennessee", "Texas", "Utah", "Vermont",
        "Virginia", "Washington", "West Virginia", "Wisconsin", "Wyoming",
    ]
}

// MARK: - The authored guides (3 deep for Week 7; more to come)

extension Guide {
    // Stamp provenance/risk onto a guide (returns a copy).
    private func meta(source: String? = nil, risk: GuideRisk = .general,
                      emergency: String? = nil) -> Guide {
        var g = self
        g.officialSource = source
        g.risk = risk
        g.emergencyNote = emergency
        return g
    }

    static let all: [Guide] = [
        moving.meta(source: "USPS (usps.com/move)"),
        bankAccount.meta(source: "Consumer Financial Protection Bureau (consumerfinance.gov)", risk: .sensitive),
        newJob.meta(source: "USCIS Form I-9 (uscis.gov)"),
        driversLicense.meta(),   // source varies by state DMV
        immigration.meta(source: "USCIS (uscis.gov)", risk: .sensitive),
        carAccident.meta(risk: .sensitive,
                         emergency: "If anyone is hurt or in danger, call 911 now."),
        doctorAppointment.meta(source: "HealthCare.gov", risk: .sensitive,
                               emergency: "If this is a medical emergency, call 911 or go to the ER. For urgent problems that can't wait, a walk-in urgent care may be faster than an appointment."),
    ]

    private static func val(_ a: [String: String], _ key: String, default def: String) -> String {
        let v = a[key] ?? ""
        return v.isEmpty ? def : v
    }

    // MARK: Step detail (authored — AI may reword, must not invent live facts)

    // Shown on every guide: these are general checklists, not official/legal
    // advice — confirm specifics on the official site, and the user can edit.
    static let referenceNote = "General guide — check the official site, and edit any step."

    // The official federal portal that links out to every state DMV — used as a
    // safe fallback when we don't have a specific state's URL (we never link to a
    // web search or a non-government site).
    static let usaGovDMV = "https://www.usa.gov/motor-vehicle-services"

    // Official (government) DMV/licensing site per state — agencies, not
    // businesses, so safe to link directly. Best-effort; verify periodically as
    // agencies rename pages. Unknown → the official USA.gov DMV portal (all 51 listed).
    static func dmvURL(_ state: String) -> String {
        let map: [String: String] = [
            "Alabama": "https://www.alea.gov/dps/driver-license",
            "Alaska": "https://doa.alaska.gov/dmv/",
            "Arizona": "https://azdot.gov/mvd",
            "Arkansas": "https://www.dfa.arkansas.gov/driver-services/",
            "California": "https://www.dmv.ca.gov",
            "Colorado": "https://dmv.colorado.gov",
            "Connecticut": "https://portal.ct.gov/dmv",
            "Delaware": "https://www.dmv.de.gov",
            "District of Columbia": "https://dmv.dc.gov",
            "Florida": "https://www.flhsmv.gov",
            "Georgia": "https://dds.georgia.gov",
            "Hawaii": "https://hidmv.ehawaii.gov",
            "Idaho": "https://itd.idaho.gov/dmv/",
            "Illinois": "https://www.ilsos.gov",
            "Indiana": "https://www.in.gov/bmv/",
            "Iowa": "https://iowadot.gov/mvd",
            "Kansas": "https://www.ksrevenue.gov/dmv.html",
            "Kentucky": "https://drive.ky.gov",
            "Louisiana": "https://www.dps.louisiana.gov/omv",
            "Maine": "https://www.maine.gov/sos/bmv/",
            "Maryland": "https://mva.maryland.gov",
            "Massachusetts": "https://www.mass.gov/rmv",
            "Michigan": "https://www.michigan.gov/sos",
            "Minnesota": "https://dps.mn.gov/divisions/dvs",
            "Mississippi": "https://www.dps.ms.gov",
            "Missouri": "https://dor.mo.gov/driver-license/",
            "Montana": "https://dojmt.gov/driving/",
            "Nebraska": "https://dmv.nebraska.gov",
            "Nevada": "https://dmv.nv.gov",
            "New Hampshire": "https://www.dmv.nh.gov",
            "New Jersey": "https://www.nj.gov/mvc/",
            "New Mexico": "https://www.mvd.newmexico.gov",
            "New York": "https://dmv.ny.gov",
            "North Carolina": "https://www.ncdot.gov/dmv",
            "North Dakota": "https://www.dot.nd.gov/dmv",
            "Ohio": "https://www.bmv.ohio.gov",
            "Oklahoma": "https://oklahoma.gov/service.html",
            "Oregon": "https://www.oregon.gov/odot/dmv/",
            "Pennsylvania": "https://www.dmv.pa.gov",
            "Rhode Island": "https://dmv.ri.gov",
            "South Carolina": "https://dmv.sc.gov",
            "South Dakota": "https://dps.sd.gov/driver-licensing",
            "Tennessee": "https://www.tn.gov/safety/driver-services.html",
            "Texas": "https://www.dps.texas.gov/section/driver-license",
            "Utah": "https://dld.utah.gov",
            "Vermont": "https://dmv.vermont.gov",
            "Virginia": "https://www.dmv.virginia.gov",
            "Washington": "https://www.dol.wa.gov",
            "West Virginia": "https://transportation.wv.gov/DMV/",
            "Wisconsin": "https://wisconsindot.gov",
            "Wyoming": "https://www.dot.state.wy.us",
        ]
        return map[state] ?? usaGovDMV
    }

    // Wrap milestone strings as checklist steps, attaching authored detail (with
    // the user's state, for links) to the heavy ones via a per-guide lookup.
    private static func detailed(_ steps: [String], state: String,
                                 _ detail: (String, String) -> StepDetail?) -> [ChecklistStep] {
        steps.map { ChecklistStep(text: $0, detail: detail($0, state)) }
    }

    private static func movingDetail(_ text: String, _ state: String) -> StepDetail? {
        if text.contains("utilities and internet") { return internetDetail }
        if text.contains("driver's license") || text.contains("license/ID") {
            return StepDetail(
                explanation: "Update your license/ID address at the DMV — many states require this within ~10–30 days.",
                links: [StepLink(label: "Open the \(state) DMV", url: dmvURL(state))])
        }
        if text.contains("Arrange the move") { return movingOptionsDetail }
        return nil
    }
    static let movingOptionsDetail = StepDetail(
        explanation: "Decide HOW you'll move. Common options, cheapest to priciest: do-it-yourself truck rental, a portable storage container you load yourself, or full-service movers. Get a couple of quotes before booking.",
        miniChecklist: [
            "Estimate how much you're moving (a studio vs a 3-bedroom).",
            "Compare options: rent a moving truck, rent a portable container, or hire full-service movers.",
            "Get 2–3 quotes and check reviews before booking.",
            "Book early for month-end or summer — they fill up.",
            "Get boxes and packing supplies (stores, marketplaces, or free from local groups).",
        ])
    static let internetDetail = StepDetail(
        explanation: "Set up (or stop) electricity, gas, water, and internet. Internet usually needs the most lead time, so start there.",
        miniChecklist: [
            "Find which providers serve your new address (ask the building, neighbors, or your realtor).",
            "Compare a couple of plans on speed and the total monthly price.",
            "Ask about one-time fees: installation, equipment/router rental, deposits.",
            "Schedule installation for on or just after your move-in date.",
            "Start or transfer electricity, gas, and water for the same date.",
            "Save your account number and confirmation after you sign up.",
        ],
        needed: ["New address", "Move-in date", "Photo ID (a deposit may be required)"],
        fields: [SavedField(label: "Internet install date"), SavedField(label: "Account number")])

    private static func newJobDetail(_ text: String, _ state: String) -> StepDetail? {
        if text.hasPrefix("Complete Form I-9") { return i9Detail }
        if text.hasPrefix("Enroll in benefits") { return benefitsDetail }
        return nil
    }
    static let i9Detail = StepDetail(
        explanation: "Form I-9 proves you can work in the U.S. Bring EITHER one document from List A, OR one from List B plus one from List C.",
        miniChecklist: [
            "List A (one): U.S. passport, OR permanent-resident card, OR a work permit.",
            "OR List B (identity): driver's license or state ID …",
            "… PLUS List C (work): Social Security card or birth certificate.",
        ],
        links: [StepLink(label: "Official I-9 acceptable documents (uscis.gov)",
                         url: "https://www.uscis.gov/i-9-central/form-i-9-acceptable-documents")],
        needed: ["Originals — most documents can't be photocopies"])

    private static func licenseDetail(_ text: String, _ state: String) -> StepDetail? {
        if text.contains("Gather proof") { return licenseDocsDetail }
        if text.contains("DMV requirements") || text.contains("renew online")
            || text.contains("Report your new address") || text.contains("Exchange your out-of-state") {
            return StepDetail(
                explanation: "Use your state's official DMV site — not a paid look-alike.",
                links: [StepLink(label: "Open the \(state) DMV", url: dmvURL(state))])
        }
        return nil
    }
    static let licenseDocsDetail = StepDetail(
        explanation: "Requirements vary by state — check your DMV's exact accepted-documents list. Bring ORIGINALS, not copies. You generally prove identity / lawful presence, your SSN (or an alternative), and two proofs of residency.",
        miniChecklist: [
            "Identity / lawful presence: passport, green card, EAD, or I-94 — per your DMV's list.",
            "SSN proof if you have one (SS card, W-2, or pay stub) — or your DMV's alternative.",
            "Two proofs of residency: lease, utility bill, bank statement, or government mail.",
            "Name changed? Bring a marriage certificate or court order.",
        ],
        needed: ["Originals of each document", "Payment for the fee"])

    static let benefitsDetail = StepDetail(
        explanation: "Benefits enrollment is usually a one-time window (~30 days) when you start. Miss it and you may have to wait until the next year.",
        miniChecklist: [
            "Review the health plans — premium, deductible, and whether your doctors are in-network.",
            "Add dental and vision if they're offered.",
            "Set your 401(k) contribution — at least enough to get any employer match.",
            "Add dependents and beneficiaries if needed.",
            "Submit before the deadline and save the confirmation.",
        ],
        needed: ["Dependents' info (if adding)", "Beneficiary / bank details"])

    // MARK: Moving
    static let moving = Guide(
        id: "moving",
        title: "Moving",
        subtitle: "Address change, utilities, license, car",
        category: .housing,
        questions: [
            GuideQuestion(id: "home", prompt: "Where are you living now?",
                          kind: .choice(["Renting", "Own my home", "Family / roommates"])),
            GuideQuestion(id: "scope", prompt: "Moving within the same state or to another state?",
                          kind: .choice(["Same state", "Another state"])),
            GuideQuestion(id: "newState", prompt: "Which state are you moving to?", kind: .state),
            GuideQuestion(id: "knowAddress", prompt: "Do you know your new address yet?",
                          kind: .choice(["Yes", "Not yet"])),
            GuideQuestion(id: "car", prompt: "Do you have a car to update?",
                          kind: .choice(["Yes", "No"])),
            GuideQuestion(id: "moveDate", prompt: "When's your move date? (optional)", kind: .date),
        ],
        build: { a in
            let home = val(a, "home", default: "Renting")
            let another = a["scope"] == "Another state"
            let newState = val(a, "newState", default: "your new state")
            let knowsAddress = a["knowAddress"] != "Not yet"
            let hasCar = a["car"] == "Yes"
            let moveDate = GuideDate.decode(a["moveDate"])

            var steps: [String] = []
            if home == "Renting" {
                steps.append("Give your landlord written notice (check your lease — often 30–60 days).")
            }
            if knowsAddress {
                steps.append("Set up USPS mail forwarding at usps.com/move (~2 weeks ahead; small fee). Use the official site.")
            } else {
                steps.append("Once you have your new address, set up USPS mail forwarding at usps.com/move.")
            }
            steps.append("Arrange the move — truck, container, or movers — and get boxes.")
            steps.append("Update your address with your bank, credit cards, and insurance.")
            steps.append("Start or stop utilities and internet at both the old and new home.")
            steps.append("Update your address with your employer and for tax mail.")

            switch home {
            case "Own my home":
                steps.append("Notify your mortgage lender, homeowners insurance, and HOA (if any).")
                steps.append("Update the mailing address for your property taxes.")
            case "Family / roommates":
                steps.append("Confirm the mailing setup with whoever you're living with.")
            default: // Renting
                steps.append("Schedule the move-out inspection and photograph the unit's condition.")
                steps.append("Update or cancel your renters insurance.")
            }

            if another {
                steps.append("Update your license/ID in \(newState) (often within 10–30 days — check the DMV).")
                if hasCar {
                    steps.append("Register your car and get new \(newState) plates, and update your car insurance.")
                }
            } else {
                if hasCar {
                    steps.append("Update your license/ID and car registration address at the DMV.")
                } else {
                    steps.append("Update your license/ID address at the DMV.")
                }
            }

            var notes = ["USPS forwarding only moves your mail — update your bank, DMV, and employer separately."]
            notes.append(referenceNote)
            return ExtractionResult(
                title: "Moving checklist",
                documentType: "Moving guide",
                dueDate: moveDate,
                category: .housing,
                summary: "A step-by-step checklist for changing your address and moving\(another ? " to \(newState)" : "").",
                steps: steps,
                detailedSteps: detailed(steps, state: newState, movingDetail),
                notes: notes,
                confidence: 1)
        })

    // MARK: New job
    static let newJob = Guide(
        id: "new_job",
        title: "Starting a new job",
        subtitle: "Tax forms, pay, benefits — W-2 or 1099",
        category: .work,
        questions: [
            GuideQuestion(id: "type", prompt: "What kind of role is this?",
                          kind: .choice(["W-2 employee", "Contractor / 1099", "Internship", "Not sure"])),
            GuideQuestion(id: "employer", prompt: "What's the company's name?", kind: .text("Employer")),
            GuideQuestion(id: "work", prompt: "Where will you work?",
                          kind: .choice(["In-person", "Remote", "Hybrid"])),
        ],
        build: { a in
            let type = val(a, "type", default: "W-2 employee")
            let employer = val(a, "employer", default: "your employer")
            let work = a["work"] ?? ""
            let isContractor = type == "Contractor / 1099"

            var steps = ["Save your offer letter and confirm your start date and first-day details."]
            if isContractor {
                steps.append("Send \(employer) a W-9 (not I-9/W-4) with your payment and invoice details.")
                steps.append("Set aside money for taxes — contractors usually pay quarterly.")
                steps.append("Decide how you'll invoice and track payments.")
            } else {
                steps.append("Complete Form I-9 (work authorization) and Form W-4 (tax withholding) for \(employer).")
                steps.append("Complete your state tax form, if any.")
                steps.append("Set up direct deposit (voided check or bank details).")
                steps.append("Finish emergency-contact info and any background check / onboarding.")
                steps.append("Enroll in benefits (health, dental, retirement) before the deadline.")
                if work == "Remote" || work == "Hybrid" {
                    steps.append("Arrange your work equipment.")
                }
                steps.append("Check your first paycheck — pay rate, taxes, and direct deposit.")
            }

            var notes = ["I-9 verifies you can work in the U.S.; W-4 sets your tax withholding.",
                         "Benefits enrollment usually closes ~30 days after you start.",
                         "Submit your SSN, bank, and ID only through the official HR portal — never by email or text."]
            if type == "Not sure" {
                notes.insert("Ask HR whether you're a W-2 employee or a 1099 contractor — it changes which tax forms you file.", at: 0)
            }
            if type == "Internship" {
                notes.insert("Paid internships usually get a W-2; unpaid ones have no tax forms. Confirm which yours is with HR.", at: 0)
            }
            notes.append(referenceNote)

            return ExtractionResult(
                title: "New job checklist",
                documentType: "New-job guide",
                category: .work,
                summary: "What to set up when starting at \(employer)\(isContractor ? " as a contractor" : "") — paperwork, pay, and benefits.",
                steps: steps,
                detailedSteps: detailed(steps, state: "", newJobDetail),
                notes: notes,
                confidence: 1)
        })

    // MARK: Driver's license
    static let driversLicense = Guide(
        id: "drivers_license",
        title: "Driver's license",
        subtitle: "First-time, renewal, transfer, and more",
        category: .government,
        questions: [
            GuideQuestion(id: "task", prompt: "What do you need to do?",
                          kind: .choice(["First-time", "Renewal", "Address change",
                                         "Replacement (lost/stolen)", "Out-of-state transfer"])),
            GuideQuestion(id: "state", prompt: "Which state are you in now?", kind: .state),
            GuideQuestion(id: "car", prompt: "Do you also have a car registration to update?",
                          kind: .choice(["Yes", "No"])),
        ],
        build: { a in
            let task = val(a, "task", default: "First-time")
            let state = val(a, "state", default: "your state")
            let hasCar = a["car"] == "Yes"

            var steps: [String]
            switch task {
            case "Renewal":
                steps = [
                    "Check whether \(state) lets you renew online, by mail, or in person.",
                    "Gather your current license and proof of residency.",
                    "Take a new photo if required and pay the renewal fee.",
                    "Renew before your license expires so you're not driving on an expired one.",
                ]
            case "Address change":
                steps = [
                    "Report your new address to the \(state) DMV — many states require this within ~10 days.",
                    "Update the address on your license/ID (a new card may be issued).",
                ]
                if hasCar { steps.append("Update the address on your car registration too.") }
            case "Replacement (lost/stolen)":
                steps = [
                    "Request a replacement license online or at the \(state) DMV.",
                    "Verify your identity and pay the replacement fee.",
                    "If it was stolen, file a police report for your records.",
                ]
            case "Out-of-state transfer":
                steps = [
                    "Exchange your out-of-state license for a \(state) license — often within ~30 days of becoming a resident.",
                    "Bring proof of identity, residency, and your current license; pass any vision test and pay the fee.",
                ]
                if hasCar {
                    steps.append("Register your out-of-state vehicle in \(state) (often within ~30 days) and update your car insurance.")
                }
            default: // First-time
                steps = [
                    "Check \(state) DMV requirements and book an appointment online.",
                    "Gather proof of identity, lawful presence, residency, and your SSN (or your state's accepted alternative).",
                    "Study for and pass the written knowledge test.",
                    "Pass the road test, then pay the license fee.",
                ]
                if hasCar { steps.append("Register your car and get plates with the \(state) DMV.") }
            }

            return ExtractionResult(
                title: task == "First-time" ? "Get your driver's license" : "Driver's license — \(task)",
                documentType: "Driver's license guide",
                category: .government,
                summary: "Steps for a \(task.lowercased()) driver's license in \(state).",
                steps: steps,
                detailedSteps: detailed(steps, state: state, licenseDetail),
                notes: ["DMV deadlines are state-specific — new residents often must transfer a license/registration within ~30 days.",
                        referenceNote],
                confidence: 1)
        })

    // MARK: Open a bank account
    static let bankAccount = Guide(
        id: "bank_account",
        title: "Open a bank account",
        subtitle: "What to bring — with or without an SSN",
        category: .finance,
        questions: [
            GuideQuestion(id: "ssn", prompt: "Do you have a Social Security number (SSN)?",
                          kind: .choice(["Yes", "No — I'll use an ITIN", "Not sure"])),
            GuideQuestion(id: "type", prompt: "Which account do you want?",
                          kind: .choice(["Checking", "Savings", "Both"])),
        ],
        build: { a in
            let ssn = a["ssn"] ?? ""
            var steps = ["Gather your documents: a government photo ID, proof of address, and your SSN or ITIN."]
            if ssn == "No — I'll use an ITIN" {
                steps.append("No SSN? Apply for an ITIN (IRS Form W-7, ~7 weeks; 9–11 in tax season) — or ask banks first; some take a foreign passport.")
            } else if ssn == "Not sure" {
                steps.append("Not sure? Check old tax forms or call the IRS — you may not need an SSN.")
            }
            steps.append("Compare banks/credit unions on fees, minimum balance, and ATMs — look for a no-fee, no-overdraft account.")
            steps.append("Open the account and make the opening deposit.")
            steps.append("Set up online banking, direct deposit, and alerts; order your debit card.")

            var notes = ["Many banks accept an ITIN or foreign passport instead of an SSN — call ahead to confirm.",
                         "No proof of address? Ask what alternatives the bank accepts (an employer, school, or shelter letter often works).",
                         "Turned down before? Ask about a 'second-chance' account and check your ChexSystems report for errors.",
                         referenceNote]
            return ExtractionResult(
                title: "Open a bank account",
                documentType: "Banking guide",
                category: .finance,
                summary: "How to open a U.S. \((a["type"] ?? "bank").lowercased()) account — including without an SSN.",
                steps: steps,
                detailedSteps: detailed(steps, state: "", bankDetail),
                notes: notes,
                confidence: 1)
        })

    private static func bankDetail(_ text: String, _ s: String) -> StepDetail? {
        if text.hasPrefix("Gather your documents") {
            return StepDetail(
                explanation: "Banks must verify your identity — bring originals.",
                miniChecklist: ["Government photo ID (passport, driver's license, or state ID).",
                                "A second ID if the bank asks for two.",
                                "Proof of address: a lease, utility bill, or bank statement.",
                                "Your SSN, or an ITIN if you don't have an SSN.",
                                "Money for the opening deposit (often $25–$100)."],
                needed: ["Originals, not photocopies"])
        }
        if text.contains("Form W-7") {
            return StepDetail(
                explanation: "An ITIN is a federal tax ID for people who can't get an SSN. It's for tax purposes — it isn't a general photo ID. Apply with IRS Form W-7.",
                links: [StepLink(label: "IRS — ITIN / Form W-7",
                                 url: "https://www.irs.gov/individuals/individual-taxpayer-identification-number")])
        }
        if text.hasPrefix("Compare banks") {
            return StepDetail(
                explanation: "Look for low or no monthly fees and a branch/ATM network near you.",
                miniChecklist: ["Monthly maintenance fee (and how to waive it).",
                                "Minimum opening deposit and balance.",
                                "ATM network and out-of-network fees.",
                                "Overdraft policy."],
                links: [StepLink(label: "CFPB — choosing a bank account",
                                 url: "https://www.consumerfinance.gov/consumer-tools/bank-accounts/")])
        }
        return nil
    }

    // MARK: USCIS paperwork
    static let immigration = Guide(
        id: "immigration",
        title: "USCIS paperwork",
        subtitle: "Green card, citizenship, work permit, case status",
        category: .government,
        questions: [
            GuideQuestion(id: "task", prompt: "What do you need to do?",
                          kind: .choice(["Renew or replace green card", "Apply for citizenship",
                                         "Renew work permit (EAD)", "Check my case status"])),
        ],
        build: { a in
            let task = val(a, "task", default: "Renew or replace green card")
            let steps: [String]
            switch task {
            case "Apply for citizenship":
                steps = ["Confirm you're eligible — usually 5 years as a permanent resident (3 if married to a U.S. citizen).",
                         "Create or sign in to your free USCIS online account.",
                         "File Form N-400, Application for Naturalization.",
                         "Pay the fee; go to a biometrics appointment if one is scheduled.",
                         "Attend the interview and pass the English and civics tests.",
                         "Take the Oath of Allegiance at your ceremony."]
            case "Renew work permit (EAD)":
                steps = ["Create or sign in to your free USCIS online account.",
                         "File Form I-765, Application for Employment Authorization.",
                         "Pay any fee (some categories are fee-exempt) and do biometrics if scheduled.",
                         "Track your case and watch for your EAD card in the mail."]
            case "Check my case status":
                steps = ["Find your receipt number (3 letters then numbers, e.g. IOE…).",
                         "Sign in to your USCIS online account, or use the case-status tool.",
                         "Turn on case alerts so you're notified of updates."]
            default:
                steps = ["Create or sign in to your free USCIS online account.",
                         "File Form I-90 to renew or replace your green card.",
                         "Pay the filing fee and submit.",
                         "Go to your biometrics appointment if USCIS schedules one.",
                         "Track your case online until the new card arrives."]
            }
            return ExtractionResult(
                title: "USCIS paperwork — \(task.lowercased())",
                documentType: "Immigration guide",
                category: .government,
                summary: "Steps to \(task.lowercased()) with USCIS.",
                steps: steps,
                detailedSteps: detailed(steps, state: "", immigrationDetail),
                notes: ["Covers common USCIS filings only — it doesn't cover every visa type or situation.",
                        "Immigration rules are complex — for anything unclear, use authorized legal help (a DOJ-recognized organization or accredited representative).",
                        "USCIS may extend your green card on the I-90 receipt notice — check the I-90 page.",
                        referenceNote],
                confidence: 1)
        })

    private static func immigrationDetail(_ text: String, _ s: String) -> StepDetail? {
        if text.contains("USCIS online account") && text.hasPrefix("Create") {
            return StepDetail(
                explanation: "A free USCIS online account lets you file, pay, upload documents, and track your case.",
                links: [StepLink(label: "USCIS — file online", url: "https://www.uscis.gov/file-online")])
        }
        if text.contains("Form I-90") {
            return StepDetail(links: [StepLink(label: "USCIS — Form I-90 (renew/replace green card)", url: "https://www.uscis.gov/i-90")])
        }
        if text.contains("Form N-400") {
            return StepDetail(links: [StepLink(label: "USCIS — Form N-400 (citizenship)", url: "https://www.uscis.gov/n-400")])
        }
        if text.contains("Form I-765") {
            return StepDetail(links: [StepLink(label: "USCIS — Form I-765 (work permit)", url: "https://www.uscis.gov/i-765")])
        }
        if text.contains("case-status tool") || text.hasPrefix("Track your case") || text.contains("receipt number") {
            return StepDetail(
                explanation: "Your receipt number (3 letters then numbers, e.g. IOE…) is on your I-797 receipt notice — save it here so it's easy to find.",
                links: [StepLink(label: "USCIS — check case status", url: "https://egov.uscis.gov/casestatus/landing.do")],
                fields: [SavedField(label: "Receipt number")])
        }
        return nil
    }

    // MARK: Car accident
    static let carAccident = Guide(
        id: "car_accident",
        title: "Car accident",
        subtitle: "At the scene, police report, insurance claim",
        category: .finance,
        questions: [
            GuideQuestion(id: "when", prompt: "When did it happen?",
                          kind: .choice(["At the scene now", "Earlier — I've left"])),
            GuideQuestion(id: "injuries", prompt: "Was anyone hurt?", kind: .choice(["No", "Yes", "Not sure"])),
            GuideQuestion(id: "other", prompt: "Was another driver involved?",
                          kind: .choice(["Yes", "Hit-and-run (they left)", "No other car"])),
            GuideQuestion(id: "drivable", prompt: "Is your car drivable?",
                          kind: .choice(["Yes", "No — needs a tow"])),
            GuideQuestion(id: "fault", prompt: "Who was at fault?",
                          kind: .choice(["The other driver", "Me", "Not sure / shared"])),
        ],
        build: { a in
            let atScene = a["when"] != "Earlier — I've left"
            let other = val(a, "other", default: "Yes")
            let hitRun = other == "Hit-and-run (they left)"
            let noOther = other == "No other car"
            let drivable = a["drivable"] != "No — needs a tow"
            let fault = val(a, "fault", default: "Not sure / shared")

            var steps: [String] = []
            // (911 lives on the first-page emergency banner, not in the steps.)
            if a["injuries"] == "Yes" {
                steps.append("Get medical care even if injuries seem minor — some show up later.")
            } else if a["injuries"] == "Not sure" {
                steps.append("Check everyone for injuries before moving on.")
            }

            // At the scene vs. after the fact
            if atScene {
                steps.append("Move to safety if you can, and turn on your hazard lights.")
                if hitRun {
                    steps.append("Call the police and file a report now — you'll need it for a hit-and-run claim. Note the report number.")
                    steps.append("Write down all you can about the other car: make, color, plate, and direction it went; ask any witnesses.")
                } else {
                    steps.append("Call the police if anyone's hurt, damage is major, or your state requires it — note the report number.")
                    if noOther {
                        steps.append("Photograph the damage and scene, and note what happened.")
                    } else {
                        steps.append("Exchange info and photograph everything: the other driver's license, plate, insurance, both cars, and the scene.")
                    }
                }
                if !drivable {
                    steps.append("Car not drivable? Arrange a tow to a safe place or a repair shop.")
                }
            } else {
                steps.append("Write down what you remember and photograph the damage now.")
                steps.append(hitRun
                    ? "File a police report as soon as you can — it's required for a hit-and-run claim."
                    : "File a police report if you haven't — especially with any injury or major damage.")
                if !drivable {
                    steps.append("If the car isn't drivable, arrange a tow to a repair shop.")
                }
            }

            // The claim — depends on who was involved / at fault
            if hitRun {
                steps.append("File a claim with your own insurer under uninsured-motorist or collision coverage.")
            } else if noOther {
                steps.append("File a claim with your own insurer (collision or comprehensive).")
            } else {
                switch fault {
                case "The other driver":
                    steps.append("File with the at-fault driver's insurer (third-party claim) — or file with your own and let them recover the cost.")
                case "Me":
                    steps.append("File a claim with your own insurer (collision coverage).")
                default:
                    steps.append("Report it to your own insurer; they'll investigate fault.")
                }
            }

            // Repair → done
            steps.append("Get a repair estimate — the insurer may inspect the car.")
            steps.append("Choose a repair shop — you can usually pick your own.")
            steps.append("Ask about a rental car if your policy covers it.")
            steps.append("Pay your deductible if any, then pick up and check the car.")
            steps.append("Keep records: claim number, report number, estimates, medical bills.")

            var notes: [String] = []
            if !noOther && !hitRun {
                notes.append("If the other driver is uninsured, your uninsured-motorist (UM) coverage can step in.")
            }
            notes.append("In a no-fault state, medical costs go through your own insurer (PIP), no matter who was at fault.")
            notes.append("Report it to your insurer promptly — even a minor accident.")
            notes.append(referenceNote)

            return ExtractionResult(
                title: "After a car accident",
                documentType: "Car-accident guide",
                category: .finance,
                summary: "What to do after an accident, from the scene to a repaired car.",
                steps: steps,
                detailedSteps: detailed(steps, state: "", accidentDetail),
                notes: notes,
                confidence: 1)
        })

    private static func accidentDetail(_ text: String, _ s: String) -> StepDetail? {
        if text.hasPrefix("Exchange info") || text.hasPrefix("Photograph the damage")
            || text.hasPrefix("Write down") {
            return StepDetail(
                explanation: "Gather everything you can — it's hard to get later.",
                miniChecklist: ["Other driver's name, phone, license, and license plate (or all you saw).",
                                "Their insurance company and policy number.",
                                "Photos of all vehicles, the damage, and the wider scene.",
                                "Location, date/time, and weather.",
                                "Names and phone numbers of any witnesses."])
        }
        if (text.hasPrefix("File") || text.hasPrefix("Report")) && text.contains("insurer") {
            return StepDetail(
                explanation: "Calling the insurer (yours or the at-fault driver's), have your details ready.",
                miniChecklist: ["Your policy number — or the at-fault driver's insurer and policy number.",
                                "Date, location, and what happened.",
                                "The police report number, if you have one.",
                                "Your photos and the other driver's info.",
                                "Ask about your deductible, a rental car, and the timeline."],
                fields: [SavedField(label: "Claim number"),
                         SavedField(label: "Adjuster name & phone"),
                         SavedField(label: "Police report number")])
        }
        return nil
    }

    // MARK: Doctor's appointment
    static let doctorAppointment = Guide(
        id: "doctor_appointment",
        title: "Book a doctor's appointment",
        subtitle: "Find an in-network doctor and what to bring",
        category: .medical,
        questions: [
            GuideQuestion(id: "insurance", prompt: "Do you have health insurance?", kind: .choice(["Yes", "No"])),
            GuideQuestion(id: "insurer", prompt: "Which insurance plan? (optional)", kind: .text("e.g. Aetna, Blue Cross, Kaiser")),
            GuideQuestion(id: "new", prompt: "New patient or a return visit?", kind: .choice(["New patient", "Return visit"])),
            GuideQuestion(id: "kind", prompt: "What kind of doctor?", kind: .text("e.g. primary care, dentist")),
        ],
        build: { a in
            let kind = val(a, "kind", default: "doctor")
            let insured = a["insurance"] != "No"
            let insurer = a["insurer"] ?? ""

            // (Emergency / urgent-care guidance lives on the first-page banner.)
            var steps: [String] = []
            if insured {
                let on = insurer.isEmpty ? "" : " on \(insurer)"
                steps.append("Find an in-network \(kind) in your plan's provider directory\(on) (or call the number on your card).")
            } else {
                steps.append("Find a community health center or sliding-scale clinic near you.")
            }
            steps.append(a["new"] == "New patient"
                ? "Call or use the patient portal to book — new-patient slots can take weeks."
                : "Call or use the patient portal to book your visit.")
            steps.append(insured ? "Confirm they take your insurance and ask what to bring."
                                 : "Ask what it will cost up front and what to bring.")
            steps.append("Before the visit, note your symptoms, medicines, allergies, and questions.")
            steps.append(insured ? "Bring your insurance card and a photo ID."
                                 : "Bring a photo ID and any medical records.")
            return ExtractionResult(
                title: "Book a \(kind) appointment",
                documentType: "Appointment guide",
                category: .medical,
                summary: insured ? "Find an in-network \(kind) and get ready for the visit."
                                 : "Find an affordable \(kind) and get ready for the visit.",
                steps: steps,
                detailedSteps: detailed(steps, state: insurer, doctorDetail),
                notes: insured ? ["In-network providers usually cost much less.", referenceNote]
                               : ["Community health centers charge on a sliding scale — you can be seen without insurance.", referenceNote],
                confidence: 1)
        })

    private static func doctorDetail(_ text: String, _ s: String) -> StepDetail? {
        if text.hasPrefix("Find an in-network") {
            // We don't link to a specific insurer's site (not official) — the user
            // checks their own card/website. Only the official HealthCare.gov how-to.
            return StepDetail(
                explanation: "Your plan's provider directory lists doctors who are in-network (lower cost). Find it on the back of your insurance card or your insurer's website.",
                miniChecklist: ["Check the doctor is in-network for YOUR plan.",
                                "Check they're accepting new patients.",
                                "Pick a convenient location and hours.",
                                "If unsure, call the number on your insurance card."],
                links: [StepLink(label: "HealthCare.gov — how to find a doctor", url: "https://www.healthcare.gov/blog/how-to-find-a-doctor")])
        }
        if text.hasPrefix("Find a community health center") {
            return StepDetail(
                explanation: "Community health centers (FQHCs) see patients regardless of insurance and charge on a sliding scale based on income.",
                miniChecklist: ["Search for a federally funded health center near you.",
                                "Call and ask if they're taking new patients.",
                                "Ask what to bring to qualify for sliding-scale fees (often proof of income)."],
                links: [StepLink(label: "HRSA — find a health center", url: "https://findahealthcenter.hrsa.gov")])
        }
        if text.hasPrefix("Call or use the patient portal to book") {
            return StepDetail(
                explanation: "Once it's booked, save the details so you don't lose them.",
                fields: [SavedField(label: "Appointment date & time"),
                         SavedField(label: "Provider name"),
                         SavedField(label: "Office phone")])
        }
        if text.hasPrefix("Before the visit") {
            return StepDetail(
                explanation: "A little prep makes the visit go smoothly.",
                miniChecklist: ["Your symptoms and when they started.",
                                "All medicines and doses (or bring the bottles).",
                                "Allergies and your medical / family history.",
                                "Your top questions, written down."],
                links: [StepLink(label: "MedlinePlus — make the most of your visit", url: "https://medlineplus.gov/ency/patientinstructions/000860.htm")])
        }
        return nil
    }
}
