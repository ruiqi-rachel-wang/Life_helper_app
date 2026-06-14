//  Guide.swift
//
//  Adaptive life guides (Week 7). Each guide is HARDCODED and deterministic:
//  a few questions whose answers pick/fill a base checklist. The structure is
//  never decided by AI — only the optional polish pass (GuidePolisher) rewords
//  the result. `build(answers:)` is pure → easy to unit-test.
//
//  UI-free: a guide carries an `ItemCategory` (the view derives color/symbol via
//  ItemStyle), and `build` returns the shared `ExtractionResult`, so guides feed
//  the same Review screen scans use.
//

import Foundation

// One hardcoded question. `choice` = pick one option; `text` = free input;
// `state` = pick a US state from a list (states are too many for pills).
nonisolated struct GuideQuestion: Identifiable, Equatable {
    enum Kind: Equatable { case choice([String]); case text(String); case state }
    let id: String
    let prompt: String
    let kind: Kind
}

nonisolated struct Guide: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let category: ItemCategory
    let questions: [GuideQuestion]
    // Deterministic: answers (questionID → chosen option / typed text / state) →
    // a tailored ExtractionResult (the AI polish is a separate pass).
    let build: ([String: String]) -> ExtractionResult
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
    static let all: [Guide] = [moving, newJob, driversLicense]

    private static func val(_ a: [String: String], _ key: String, default def: String) -> String {
        let v = a[key] ?? ""
        return v.isEmpty ? def : v
    }

    // MARK: Step detail (authored — AI may reword, must not invent live facts)

    // A safe link for an online action: a web search (never a possibly-wrong
    // official URL we'd be guessing). Used when we don't have an official site.
    static func searchURL(_ query: String) -> String {
        "https://www.google.com/search?q=" + (query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)
    }

    // Official (government) DMV/licensing site per state — these are agencies,
    // not businesses, so they're safe to link directly. Unknown → a web search.
    // Best-effort; agencies occasionally rename pages.
    static func dmvURL(_ state: String) -> String {
        let map: [String: String] = [
            "California": "https://www.dmv.ca.gov",
            "New York": "https://dmv.ny.gov",
            "Texas": "https://www.dps.texas.gov/section/driver-license",
            "Florida": "https://www.flhsmv.gov",
            "Illinois": "https://www.ilsos.gov",
            "Pennsylvania": "https://www.dmv.pa.gov",
            "Ohio": "https://www.bmv.ohio.gov",
            "Georgia": "https://dds.georgia.gov",
            "North Carolina": "https://www.ncdot.gov/dmv",
            "Michigan": "https://www.michigan.gov/sos",
            "New Jersey": "https://www.nj.gov/mvc/",
            "Virginia": "https://www.dmv.virginia.gov",
            "Washington": "https://www.dol.wa.gov",
            "Arizona": "https://azdot.gov/mvd",
            "Massachusetts": "https://www.mass.gov/rmv",
            "Tennessee": "https://www.tn.gov/safety/driver-services.html",
            "Indiana": "https://www.in.gov/bmv/",
            "Maryland": "https://mva.maryland.gov",
            "Colorado": "https://dmv.colorado.gov",
            "Minnesota": "https://dps.mn.gov/divisions/dvs",
            "Wisconsin": "https://wisconsindot.gov",
            "Nevada": "https://dmv.nv.gov",
            "Oregon": "https://www.oregon.gov/odot/dmv/",
            "Connecticut": "https://portal.ct.gov/dmv",
            "District of Columbia": "https://dmv.dc.gov",
        ]
        return map[state] ?? searchURL("\(state) DMV official site")
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
        ],
        links: [StepLink(label: "Compare moving truck vs container vs movers",
                         url: searchURL("compare moving truck rental vs portable container vs full service movers"))])
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
        needed: ["New address", "Move-in date", "Photo ID (a deposit may be required)"])

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
        explanation: "Bring ORIGINALS (not copies). You usually need to prove your identity, your Social Security number, and your residency.",
        miniChecklist: [
            "Identity: U.S. passport, OR birth certificate + a photo ID.",
            "Social Security: SS card, a W-2, or a pay stub showing your SSN.",
            "Residency (often TWO): lease, utility bill, bank statement, or government mail.",
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
        ],
        build: { a in
            let home = val(a, "home", default: "Renting")
            let another = a["scope"] == "Another state"
            let newState = val(a, "newState", default: "your new state")
            let knowsAddress = a["knowAddress"] != "Not yet"
            let hasCar = a["car"] == "Yes"

            var steps: [String] = []
            if home == "Renting" {
                steps.append("Give your landlord written notice and confirm your move-out date.")
            }
            if knowsAddress {
                steps.append("Submit a USPS change-of-address at usps.com/move (~2 weeks ahead) — use the official USPS site, not a paid look-alike.")
            } else {
                steps.append("Set up temporary mail forwarding or use a trusted mailing address until you have your new address.")
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
                steps.append("Update your driver's license or state ID in \(newState) — many states require this within ~10–30 days, so check the DMV.")
                if hasCar {
                    steps.append("Register your car and get new plates in \(newState), and update your car insurance to the new garaging address.")
                }
                steps.append("Register to vote in \(newState).")
            } else {
                if hasCar {
                    steps.append("Update the address on your license/ID and car registration with the DMV (often within ~10 days — check your state).")
                } else {
                    steps.append("Update the address on your driver's license or state ID with the DMV.")
                }
                steps.append("Update your voter registration with your new address.")
            }

            return ExtractionResult(
                title: "Moving checklist",
                documentType: "Moving guide",
                category: .housing,
                summary: "A step-by-step checklist for changing your address and moving\(another ? " to \(newState)" : "").",
                steps: steps,
                detailedSteps: detailed(steps, state: newState, movingDetail),
                notes: ["Use the official USPS change-of-address — avoid paid sites that charge for the free service.",
                        "DMV address deadlines are state-specific (often 10–30 days) — don't wait."],
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

            var steps = ["Save your offer letter or contract and confirm your start date, location, and first-day instructions."]
            if isContractor {
                steps.append("Send \(employer) a W-9 (not I-9/W-4) along with your payment details and invoice schedule.")
                steps.append("Set aside money for taxes — contractors usually pay quarterly estimated taxes.")
                steps.append("Decide how you'll invoice and track payments.")
            } else {
                steps.append("Complete Form I-9 (identity + work authorization) and Form W-4 (federal tax withholding) for \(employer).")
                steps.append("Complete your state tax-withholding form, if your state has one.")
                steps.append("Set up direct deposit with a voided check or your bank details.")
                steps.append("Fill out emergency-contact info and finish any background check / onboarding portal.")
                steps.append("Enroll in benefits (health, dental, retirement) before the deadline.")
                if work == "Remote" || work == "Hybrid" {
                    steps.append("Arrange pickup or shipping of your work equipment.")
                }
            }

            var notes = ["I-9 verifies you can work in the U.S.; W-4 sets your tax withholding.",
                         "Benefits enrollment usually closes ~30 days after your start date — don't miss it."]
            if type == "Not sure" {
                notes.insert("Ask HR whether you're a W-2 employee or a 1099 contractor — it changes which tax forms you file.", at: 0)
            }

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
                    "Gather proof of identity, residency, and your Social Security number.",
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
                notes: ["DMV deadlines are state-specific — new residents often must transfer a license/registration within ~30 days."],
                confidence: 1)
        })
}
