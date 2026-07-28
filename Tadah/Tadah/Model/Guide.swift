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
nonisolated struct GuideQuestion: Identifiable {
    enum Kind: Equatable { case choice([String]); case text(String); case state; case date }
    let id: String
    let prompt: String
    let kind: Kind
    // Show this question only when the answers so far make it relevant — so we
    // never ask what doesn't matter (e.g. "car registration?" on a renewal).
    // nil = always shown.
    var showIf: (([String: String]) -> Bool)? = nil
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

// Whether a guide's facts come from one US-wide authority or vary by state.
nonisolated enum Jurisdiction { case federal, perState }

// An auditable citation for a guide's facts: which official body, the domain we
// show the user, a link to open, federal-vs-per-state, and when a human last
// checked it. Replaces the old free-text `officialSource` label so "accurate"
// is verifiable, not just asserted.
nonisolated struct GuideSource {
    var authority: String          // "IRS", "USCIS", "USPS", "Your state's DMV"
    var domain: String             // "irs.gov" — the short form shown to the user
    var url: String                // full official URL to open (root domains: stable)
    var jurisdiction: Jurisdiction
    var lastReviewed: Date

    // "IRS · irs.gov" (federal) / "Your state's DMV · varies by state" (per-state).
    var label: String {
        jurisdiction == .perState ? "\(authority) · varies by state" : "\(authority) · \(domain)"
    }
    var reviewedLabel: String {
        "Reviewed " + lastReviewed.formatted(.dateTime.month(.abbreviated).year())
    }

    // No date literals in Swift — build the review date from year/month.
    static func reviewed(_ year: Int, _ month: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) ?? .now
    }
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

    // The questions worth showing given the answers so far (hides irrelevant ones).
    func visibleQuestions(_ answers: [String: String]) -> [GuideQuestion] {
        questions.filter { $0.showIf?(answers) ?? true }
    }

    // Provenance / safety metadata (review-team requested). `source` is the
    // auditable official citation; `risk` stays on the Guide because it also
    // drives the AI-skip and applies even to guides without one fixed source.
    var source: GuideSource? = nil
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
    private func meta(source: GuideSource? = nil, risk: GuideRisk = .general,
                      emergency: String? = nil) -> Guide {
        var g = self
        g.source = source
        g.risk = risk
        g.emergencyNote = emergency
        return g
    }

    // Reviewed June 2026 (when the guide content was authored). Root-domain URLs
    // are used deliberately — they're stable. NOTE: deep USCIS links (i-90, n-400,
    // i-765, case-status) could NOT be reliably fetched by the browser tool, so
    // they must be opened + confirmed in a real browser before TestFlight; until
    // then we cite the stable uscis.gov root. (See build plan, Week 8 item 6.)
    private static let reviewed = GuideSource.reviewed(2026, 6)
    private static func fed(_ authority: String, _ domain: String, _ url: String) -> GuideSource {
        GuideSource(authority: authority, domain: domain, url: url, jurisdiction: .federal, lastReviewed: reviewed)
    }
    private static func perState(_ authority: String, _ url: String) -> GuideSource {
        GuideSource(authority: authority, domain: "usa.gov", url: url, jurisdiction: .perState, lastReviewed: reviewed)
    }

    static let all: [Guide] = [
        moving.meta(source: fed("USPS", "usps.com", "https://www.usps.com/move")),
        rentingNewPlace.meta(source: fed("Consumer Financial Protection Bureau", "consumerfinance.gov", "https://www.consumerfinance.gov/renting/")),
        buyingHome.meta(source: fed("Consumer Financial Protection Bureau", "consumerfinance.gov", "https://www.consumerfinance.gov/owning-a-home/")),
        bankAccount.meta(source: fed("Consumer Financial Protection Bureau", "consumerfinance.gov", "https://www.consumerfinance.gov"), risk: .sensitive),
        taxes.meta(source: fed("IRS", "irs.gov", "https://www.irs.gov"), risk: .sensitive),
        newJob.meta(source: fed("USCIS (Form I-9)", "uscis.gov", "https://www.uscis.gov/i-9"), risk: .sensitive),
        startBusiness.meta(source: fed("U.S. Small Business Administration", "sba.gov", "https://www.sba.gov/business-guide"), risk: .sensitive),
        ssnItin.meta(source: fed("Social Security Administration", "ssa.gov", "https://www.ssa.gov"), risk: .sensitive),
        driversLicense.meta(source: perState("Your state's DMV", "https://www.usa.gov/motor-vehicle-services")),
        immigration.meta(source: fed("USCIS", "uscis.gov", "https://www.uscis.gov"), risk: .sensitive),
        schoolEnrollment.meta(source: fed("U.S. Dept. of Education", "ed.gov", "https://www.ed.gov"), risk: .sensitive),
        healthInsurance.meta(source: fed("HealthCare.gov", "healthcare.gov", "https://www.healthcare.gov"), risk: .sensitive),
        doctorAppointment.meta(source: fed("HealthCare.gov", "healthcare.gov", "https://www.healthcare.gov"), risk: .sensitive,
                               emergency: "If this is a medical emergency, call 911 or go to the ER. For urgent problems that can't wait, a walk-in urgent care may be faster than an appointment."),
        carAccident.meta(source: perState("Your state's DMV & your insurer", "https://www.usa.gov"), risk: .sensitive,
                         emergency: "If anyone is hurt or in danger, call 911 now."),
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
        if text.contains("utilities and internet") { return utilitiesDetail }
        if text.contains("driver's license") || text.contains("license/ID") {
            return StepDetail(
                explanation: "Update your license/ID address at the DMV — many states require this within ~10–30 days.",
                links: [StepLink(label: "Open your state's DMV", url: dmvURL(state))])
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
    // Every utility a home needs, broken out one by one (internet, electricity,
    // gas, water/sewer, trash) so none is forgotten. Shared by the moving, renting,
    // and home-buying guides. Internet needs the most lead time, so it's first.
    static let utilitiesDetail = StepDetail(
        explanation: "Set up — or transfer or stop — every utility your home uses; each has its own provider. Internet usually needs the most lead time, so start there. Aim to have them all on for your move-in date.",
        miniChecklist: [
            "Internet / WiFi — compare providers on speed and total monthly price, then book installation (often 1–2 weeks out).",
            "Electricity — start service with your local electric company.",
            "Gas — start natural-gas service if your home uses gas for heat, the stove, or hot water.",
            "Water & sewer — set up with the city or your local water utility.",
            "Trash & recycling — city pickup or a private hauler, depending on the area.",
            "If you rent, first confirm which of these your landlord already includes.",
            "Find which providers serve your address (ask the building, neighbors, or your realtor).",
            "Ask about one-time fees: deposits, installation, and equipment/router rental.",
            "Save each account number and confirmation after you sign up.",
        ],
        needed: ["New address", "Move-in date", "Photo ID (a deposit may be required)"])

    // The utilities step, tailored to a ZIP: the AI looked up which companies
    // actually serve that area, so we name each one with whatever contact methods
    // it offers (website, phone, in-person). The contact text stays inline so
    // `linkified` makes the URL and phone tappable. Returns nil when the lookup
    // found nothing, so the caller keeps the generic `utilitiesDetail`.
    //
    // Hand-translated per language (NOT the String Catalog): this text is built
    // fresh each time with per-ZIP/per-provider data spliced in, so it can never
    // be a stable catalog lookup key the way `.localized()` handles static guide
    // text elsewhere. It's inserted into the result AFTER `.localized()` already
    // ran, so if it stayed in English here it would silently stay English forever
    // regardless of the picked language — that was the actual bug.
    static func utilitiesDetail(forZip zip: String, providers: [LocalUtility],
                                language: ExplainLanguage = .english) -> StepDetail? {
        guard !providers.isEmpty else { return nil }

        let warning, callWord, inPersonWord, askFees, saveConfirmation, explanationTemplate: String
        let needed: [String]
        switch language {
        case .english:
            warning = "⚠️ These companies are matched to ZIP \(zip) by AI — confirm each one is right before you pay or share personal info."
            callWord = "call"; inPersonWord = "in person"
            askFees = "Ask each about deposits, installation, and any equipment/router fees."
            saveConfirmation = "Save every account number and confirmation after you sign up."
            explanationTemplate = "Utility companies serving ZIP \(zip). Electricity, gas, water, and trash are usually one company per area; internet often has a few options."
            needed = ["New address", "Move-in date", "Photo ID (a deposit may be required)"]
        case .spanish:
            warning = "⚠️ Estas empresas se emparejaron con el código postal \(zip) mediante IA — confirma que cada una sea correcta antes de pagar o compartir información personal."
            callWord = "llamar al"; inPersonWord = "en persona"
            askFees = "Pregunta a cada una sobre depósitos, instalación y cualquier cargo por equipo/router."
            saveConfirmation = "Guarda cada número de cuenta y confirmación después de inscribirte."
            explanationTemplate = "Empresas de servicios públicos que atienden el código postal \(zip). La electricidad, el gas, el agua y la basura suelen tener una sola empresa por zona; el internet suele tener varias opciones."
            needed = ["Dirección nueva", "Fecha de mudanza", "Identificación con foto (puede requerirse un depósito)"]
        case .chinese:
            warning = "⚠️ 这些公司是 AI 根据邮编 \(zip) 匹配的——付款或提供个人信息前请先核实每一家是否正确。"
            callWord = "致电"; inPersonWord = "现场地址"
            askFees = "向每家询问押金、安装费以及设备/路由器等相关费用。"
            saveConfirmation = "注册后请保存每个账号和确认信息。"
            explanationTemplate = "为邮编 \(zip) 提供服务的公用事业公司。电力、燃气、自来水和垃圾清运通常每个地区只有一家公司；网络通常有多个选择。"
            needed = ["新地址", "搬入日期", "带照片的身份证件（可能需要押金）"]
        }

        var lines = [warning]
        lines += providers.map { p in
            // "Electricity — Austin Energy. austinenergy.com · call 512-494-9400 · in person: 4815 Mueller Blvd"
            var contacts: [String] = []
            if let w = p.website, !w.isEmpty { contacts.append(w) }
            if let ph = p.phone, !ph.isEmpty { contacts.append("\(callWord) \(ph)") }
            if let v = p.inPerson, !v.isEmpty { contacts.append("\(inPersonWord): \(v)") }
            let tail = contacts.isEmpty ? "" : ". " + contacts.joined(separator: " · ")
            return "\(p.kind) — \(p.name)\(tail)"
        }
        lines.append(askFees)
        lines.append(saveConfirmation)
        return StepDetail(explanation: explanationTemplate, miniChecklist: lines, needed: needed)
    }

    private static func newJobDetail(_ text: String, _ state: String) -> StepDetail? {
        if text.hasPrefix("Complete Form I-9") { return i9Detail }
        if text.hasPrefix("Enroll in benefits") { return benefitsDetail }
        if text.hasPrefix("Set up direct deposit") {
            return StepDetail(
                explanation: "Direct deposit sends your pay straight to your bank account. You'll need your routing number and account number — both are on a check or in your banking app. Double-check them; a typo can delay your first pay.",
                miniChecklist: ["Have a voided check ready, if HR asks for one."])
        }
        if text.hasPrefix("Check your first paycheck") {
            return StepDetail(
                explanation: "Gross pay is before deductions; net (take-home) pay is after. Check your first stub closely — pay mistakes are easiest to fix early.",
                miniChecklist: ["Your pay rate and hours match your offer.",
                                "Taxes withheld — federal, state, Social Security, and Medicare.",
                                "Any benefit or retirement deductions you signed up for.",
                                "The money landed in the right bank account."])
        }
        if text.hasPrefix("Set aside money for taxes") {
            return StepDetail(
                explanation: "As a 1099 contractor, no taxes are taken out of your pay — you handle them yourself. Set aside roughly 25–30% of each payment, and expect to pay the IRS four times a year.",
                miniChecklist: ["Move about 25–30% of each payment into a separate savings 'tax' bucket.",
                                "Track your income and business expenses — expenses lower what you owe.",
                                "Pay quarterly estimated taxes (federal, and state if it has income tax)."],
                links: [StepLink(label: "IRS — self-employed tax center", url: "https://www.irs.gov/businesses/small-businesses-self-employed/self-employed-individuals-tax-center")])
        }
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
                links: [StepLink(label: "Open your state's DMV", url: dmvURL(state))])
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

    // MARK: Moving out (leaving your old place + change of address)
    static let moving = Guide(
        id: "moving",
        title: "Moving out",
        subtitle: "Notice, deposit, mail, change of address",
        category: .housing,
        questions: [
            GuideQuestion(id: "home", prompt: "Where are you living now?",
                          kind: .choice(["Renting", "Own my home", "Family / roommates"])),
            GuideQuestion(id: "scope", prompt: "Moving within the same state or to another state?",
                          kind: .choice(["Same state", "Another state"])),
            GuideQuestion(id: "newState", prompt: "Which state are you moving to?", kind: .state,
                          showIf: { $0["scope"] == "Another state" }),
            GuideQuestion(id: "knowAddress", prompt: "Do you know your new address yet?",
                          kind: .choice(["Yes", "Not yet"])),
            GuideQuestion(id: "car", prompt: "Do you have a car to update?",
                          kind: .choice(["Yes", "No"])),
            GuideQuestion(id: "zip", prompt: "Your new home's ZIP code? (optional — to find your local utility companies)",
                          kind: .text("e.g. 78701"), showIf: { $0["knowAddress"] != "Not yet" }),
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
                otherIDs: [DocID(label: "Utility account #", value: ""),
                           DocID(label: "Internet install date", value: "")],
                category: .housing,
                summary: "A step-by-step checklist for changing your address and moving.",
                steps: steps,
                detailedSteps: detailed(steps, state: newState, movingDetail),
                notes: notes,
                confidence: 1)
        })

    // MARK: Renting a new place (settling into the new home)
    private static func rentingDetail(_ text: String, _ state: String) -> StepDetail? {
        if text.contains("electricity, gas, water, and internet") { return utilitiesDetail }
        if text.hasPrefix("Tour the unit and read the lease") {
            return StepDetail(
                explanation: "The lease is a binding contract — once you sign, its terms hold. Read every line and ask about anything unclear before you sign. If a promise isn't written in the lease, it doesn't count.",
                miniChecklist: ["Rent, the due date, late fees, and lease length.",
                                "The deposit amount — and exactly what you must do to get it back.",
                                "Which utilities you pay vs. the landlord, plus rules on pets and early-termination fees.",
                                "No U.S. credit history? A landlord may ask for a bigger deposit, a co-signer, or a few months up front — ask what proof they'll accept instead (pay stubs, a bank letter, or an offer letter)."],
                links: [StepLink(label: "CFPB — renting a home", url: "https://www.consumerfinance.gov/renting/")])
        }
        if text.hasPrefix("Pay the security deposit and first month's rent") {
            return StepDetail(
                explanation: "Pay by a traceable method — a check or bank transfer, not cash without a receipt — and get a dated receipt. It's your proof when it's time to get the deposit back.")
        }
        if text.hasPrefix("Photograph the unit's condition") {
            return StepDetail(
                explanation: "Photos of any pre-existing damage are how you get your full deposit back — the landlord can't charge you for what was already there. Take them the day you get the keys, before you move anything in.",
                miniChecklist: ["Note any existing damage in writing and give the landlord a copy."])
        }
        if text.hasPrefix("Get renters insurance") {
            return StepDetail(
                explanation: "Renters insurance covers your belongings (theft, fire, water damage) and your liability — usually $10–20 a month. Your landlord's insurance does not cover your things.",
                miniChecklist: ["Send proof to your landlord if the lease requires it."])
        }
        if text.hasPrefix("Set up how you'll pay rent") {
            return StepDetail(
                explanation: "Set up autopay or the tenant portal so you're never late — late rent means fees, and can hurt the references you'll need for your next place. Keep proof of each payment.")
        }
        return nil
    }
    static let rentingNewPlace = Guide(
        id: "renting",
        title: "Renting a new place",
        subtitle: "Lease, deposit, utilities, insurance",
        category: .housing,
        questions: [
            GuideQuestion(id: "signed", prompt: "Have you signed the lease yet?",
                          kind: .choice(["Yes", "Not yet"])),
            GuideQuestion(id: "zip", prompt: "The new place's ZIP code? (optional — to find your local utility companies)",
                          kind: .text("e.g. 78701")),
            GuideQuestion(id: "moveDate", prompt: "When's your move-in date? (optional)", kind: .date),
        ],
        build: { a in
            let signed = a["signed"] == "Yes"
            let moveDate = GuideDate.decode(a["moveDate"])

            var steps: [String] = []
            if !signed {
                steps.append("Tour the unit and read the lease before signing — note the rent, lease length, deposit, who pays which utilities, and any pet or early-termination fees.")
            }
            steps.append("Pay the security deposit and first month's rent, and keep the receipts.")
            steps.append("Photograph the unit's condition on move-in day — it protects your deposit when you leave.")
            steps.append("Set up electricity, gas, water, and internet at the new place for your move-in date.")
            steps.append("Get renters insurance — many leases require it, and it's inexpensive.")
            steps.append("Set up how you'll pay rent (autopay or the tenant portal) and save the account details.")
            steps.append("Get your keys, mailbox key, and building access, and learn the trash, parking, and laundry rules.")

            var notes = ["A security deposit is usually about one month's rent; you should get it back (minus any damage) after you move out."]
            notes.append(referenceNote)
            return ExtractionResult(
                title: "Renting checklist",
                documentType: "Renting guide",
                dueDate: moveDate,
                otherIDs: [DocID(label: "Utility account #", value: ""),
                           DocID(label: "Internet install date", value: "")],
                category: .housing,
                summary: "A step-by-step checklist for renting and moving into a new place.",
                steps: steps,
                detailedSteps: detailed(steps, state: "", rentingDetail),
                notes: notes,
                confidence: 1)
        })

    // MARK: Buying a home (pre-offer only — inspection through closing is its
    // own follow-up guide, started fresh once an offer is actually accepted;
    // see the last note below).
    static let buyingHome = Guide(
        id: "buying",
        title: "Buying a home",
        subtitle: "Credit, pre-approval, agent, offer",
        category: .housing,
        questions: [],
        build: { _ in
            let steps = [
                "Check your credit and set a budget, including the down payment and the monthly cost (loan, taxes, insurance).",
                "Get pre-approved for a mortgage — compare rates and fees from a few lenders.",
                "Find a real estate agent and start touring homes in your price range.",
                "Make an offer; once it's accepted, sign the purchase agreement and pay the earnest-money deposit.",
            ]

            var notes = [
                "Closing costs are usually about 2–5% of the price, on top of your down payment — budget for that too.",
                "Once your offer is accepted, come back to Guides and start a new checklist — inspection, appraisal, insurance, and closing all happen after this point.",
            ]
            notes.append(referenceNote)
            return ExtractionResult(
                title: "Home-buying checklist",
                documentType: "Home-buying guide",
                otherIDs: [DocID(label: "Lender / loan #", value: "")],
                category: .housing,
                summary: "A step-by-step checklist to get from credit check to an accepted offer.",
                steps: steps,
                detailedSteps: detailed(steps, state: "", buyingDetail),
                notes: notes,
                confidence: 1)
        })

    private static func buyingDetail(_ text: String, _ s: String) -> StepDetail? {
        if text.hasPrefix("Get pre-approved") {
            return StepDetail(
                explanation: "Pre-approval shows sellers you're serious and sets your real budget. Compare a few lenders in the same short window — rate-shopping that way barely affects your credit.",
                miniChecklist: ["Gather pay stubs, W-2s or 1099s, and 2 years of tax returns.",
                                "Get recent bank and asset statements.",
                                "Ask each lender for a Loan Estimate and compare the APR and fees, not just the rate.",
                                "Get the pre-approval letter in writing."],
                links: [StepLink(label: "CFPB — owning a home", url: "https://www.consumerfinance.gov/owning-a-home/")])
        }
        if text.hasPrefix("Check your credit and set a budget") {
            return StepDetail(
                explanation: "Lenders decide your rate from your credit and your debt-to-income — check your reports early so there's time to fix errors.",
                miniChecklist: ["Get your free credit reports at AnnualCreditReport.com — the official, federally authorized site.",
                                "Dispute any errors before you apply — they can cost you a better rate.",
                                "Budget the full monthly cost: loan payment, property taxes, insurance, and any HOA fee.",
                                "Plan the cash you'll need: the down payment (some loans start around 3%) plus 2–5% closing costs."],
                links: [StepLink(label: "CFPB — credit reports and scores", url: "https://www.consumerfinance.gov/consumer-tools/credit-reports-and-scores/")])
        }
        if text.hasPrefix("Find a real estate agent") {
            return StepDetail(
                explanation: "A buyer's agent represents you, not the seller. You may be asked to sign a buyer agreement — read what it says about services and fees before signing.",
                miniChecklist: ["Interview 2–3 agents and ask how well they know your target neighborhoods.",
                                "Ask what their fee is and who pays it — get it in writing.",
                                "Check their license on your state's real-estate board site."])
        }
        if text.hasPrefix("Make an offer") {
            return StepDetail(
                explanation: "Your agent drafts the offer using recent sales of similar homes. The earnest-money deposit (often 1–3%) shows you're serious and counts toward your purchase at closing.",
                miniChecklist: ["Keep the inspection, financing, and appraisal contingencies — they let you back out safely if something goes wrong.",
                                "Earnest money goes to an escrow or title company — never wire money based on emailed instructions without calling to verify; wire fraud is common in home sales.",
                                "If the offer is accepted, save the signed purchase agreement."])
        }
        return nil
    }

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
                          kind: .choice(["In-person", "Remote", "Hybrid", "Not sure"]),
                          showIf: { $0["type"] != "Contractor / 1099" }),
            GuideQuestion(id: "startDate", prompt: "Start date? (optional)", kind: .date),
        ],
        build: { a in
            let type = val(a, "type", default: "W-2 employee")
            let employer = val(a, "employer", default: "your employer")
            let work = a["work"] ?? ""
            let isContractor = type == "Contractor / 1099"
            let startDate = GuideDate.decode(a["startDate"])

            var steps = ["Save your offer letter and confirm your start date and first-day details."]
            if isContractor {
                steps.append("Confirm the contract scope, rate, payment schedule, and how to invoice.")
                steps.append("Send \(employer) a W-9 (not I-9/W-4) with your payment details.")
                steps.append("Set aside money for taxes — contractors usually pay quarterly.")
                steps.append("Save the signed contract, and track your invoices and payment dates.")
            } else {
                steps.append("Complete Form I-9 (work authorization) and Form W-4 (tax withholding) for \(employer).")
                steps.append("Complete your state tax form, if any.")
                steps.append("Set up direct deposit (voided check or bank details).")
                steps.append("Get access to the HR, payroll, and benefits portals, and a work email.")
                steps.append("Finish any background check or drug screen if required.")
                steps.append("Enroll in benefits (health, dental, retirement) before the deadline.")
                if work == "Remote" || work == "Hybrid" {
                    steps.append("Arrange your laptop/equipment shipment and remote access (VPN, accounts).")
                } else {
                    steps.append("Confirm your first-day schedule, work location, badge, and parking.")
                }
                steps.append("Check your first paycheck — pay rate, taxes, and direct deposit.")
            }

            var notes = ["I-9 verifies you can work in the U.S.; W-4 sets your tax withholding.",
                         "Benefits enrollment usually closes ~30 days after you start — add a reminder.",
                         "Submit your SSN, bank, and ID only through the official HR portal — never by email or text."]
            if type == "Not sure" {
                notes.insert("Ask HR whether you're a W-2 employee or a 1099 contractor — it changes which tax forms you file.", at: 0)
            }
            if type == "Internship" {
                notes.insert("Paid internships usually get a W-2; unpaid ones have no tax forms. Confirm which yours is with HR.", at: 0)
            }
            if isContractor { notes.append("Contractors usually don't get employee benefits (health, paid leave).") }
            notes.append(referenceNote)

            return ExtractionResult(
                title: "New job checklist",
                documentType: "New-job guide",
                dueDate: startDate,
                category: .work,
                summary: "What to set up when starting a new job — paperwork, pay, and benefits.",
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
                          kind: .choice(["Yes", "No"]),
                          showIf: { ["First-time", "Address change", "Out-of-state transfer"].contains($0["task"] ?? "") }),
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
                title: task == "First-time" ? "Get your driver's license" : "Driver's license",
                documentType: "Driver's license guide",
                category: .government,
                summary: "Steps for your driver's license.",
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
        ],
        build: { a in
            let ssn = a["ssn"] ?? ""
            let hasSSN = ssn == "Yes"
            let useITIN = ssn == "No — I'll use an ITIN"
            // First step reflects the answer — don't mention ITIN when they have an SSN.
            let firstStep = hasSSN
                ? "Gather your documents: a government photo ID, proof of address, and your Social Security number (SSN)."
                : useITIN
                ? "Gather your documents: a government photo ID, proof of address, and your ITIN (apply for one first if you don't have it yet)."
                : "Gather your documents: a government photo ID, proof of address, and your SSN or ITIN."
            var steps = [firstStep]
            if useITIN {
                steps.append("No SSN? Call a few banks first and ask what they accept — an ITIN, foreign passport, or consular ID. Apply for an ITIN only if you actually need one.")
            } else if ssn == "Not sure" {
                steps.append("Not sure? Check old tax forms or call the IRS — you may not need an SSN.")
            }
            steps.append("Compare banks/credit unions on fees, minimum balance, and ATMs — look for a no-fee, no-overdraft account.")
            steps.append("Open the account and make the opening deposit.")
            steps.append("Set up online banking, direct deposit, and alerts; order your debit card — and decline overdraft coverage unless you understand the fees.")

            var notes: [String] = []
            if !hasSSN {
                notes.append("Many banks accept an ITIN or foreign passport instead of an SSN — call ahead to confirm.")
            }
            notes.append("No proof of address? Ask what alternatives the bank accepts (an employer, school, or shelter letter often works).")
            notes.append("Turned down before? Ask about a 'second-chance' account and check your ChexSystems report for errors.")
            notes.append(referenceNote)
            return ExtractionResult(
                title: "Open a bank account",
                documentType: "Banking guide",
                category: .finance,
                summary: "How to open a U.S. bank account — including without an SSN.",
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
                                "An identification number the bank accepts — an SSN, ITIN, passport number, alien ID number, or another government-issued ID number.",
                                "Money for the opening deposit (often $25–$100)."],
                needed: ["Originals, not photocopies"])
        }
        if text.contains("Apply for an ITIN") {
            return StepDetail(
                explanation: "An ITIN is a federal tax ID for people who can't get an SSN. It's for tax purposes — it isn't a general photo ID, and banks vary on accepting it. Apply with IRS Form W-7 only if you need one.",
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
            GuideQuestion(id: "deadline", prompt: "Do you have a notice or deadline? (optional)", kind: .date),
        ],
        build: { a in
            let task = val(a, "task", default: "Renew or replace green card")
            let deadline = GuideDate.decode(a["deadline"])
            var steps: [String]
            switch task {
            case "Apply for citizenship":
                steps = ["Check the official USCIS N-400 eligibility page — many apply after 5 years as a permanent resident (3 in some marriage-based cases), but exceptions exist.",
                         "Create or sign in to your free USCIS online account.",
                         "File Form N-400, Application for Naturalization.",
                         "Pay the fee; go to a biometrics appointment if one is scheduled.",
                         "Attend the interview and pass the English and civics tests.",
                         "Take the Oath of Allegiance at your ceremony."]
            case "Renew work permit (EAD)":
                steps = ["Check your EAD category (the (c)(#) code on your notice or prior card) — it determines the filing method, fee, fee waiver, and any automatic-extension rules.",
                         "Create or sign in to your free USCIS online account.",
                         "File Form I-765, Application for Employment Authorization.",
                         "Pay any fee your category requires (some are fee-exempt) and do biometrics if scheduled.",
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
            // Common to every USCIS task
            steps.append("Save copies or photos of every form, notice, and receipt you send or receive.")
            steps.append("Add reminders for any biometrics, interview, RFE, or card-expiration dates.")
            steps.append("If you get an RFE, NOID, or court notice, contact authorized legal help — don't rely on social media.")
            return ExtractionResult(
                title: "USCIS paperwork",
                documentType: "Immigration guide",
                dueDate: deadline,
                otherIDs: [DocID(label: "Receipt number", value: "")],
                category: .government,
                summary: "Steps for your USCIS filing.",
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
                explanation: "Your receipt number (3 letters then numbers, e.g. IOE…) is on your I-797 receipt notice — keep it in Details so it's easy to find.",
                links: [StepLink(label: "USCIS — check case status", url: "https://egov.uscis.gov/casestatus/landing.do")])
        }
        return nil
    }

    // MARK: Car accident
    static let carAccident = Guide(
        id: "car_accident",
        title: "Car accident",
        subtitle: "At the scene, police report, insurance claim",
        category: .auto,
        questions: [
            GuideQuestion(id: "when", prompt: "When did it happen?",
                          kind: .choice(["At the scene now", "Earlier — I've left"])),
            GuideQuestion(id: "injuries", prompt: "Do you feel any pain or injury?",
                          kind: .choice(["No", "Yes", "Not sure"])),
            GuideQuestion(id: "what", prompt: "What best describes what happened?",
                          kind: .choice(["The other driver hit me", "I may have hit someone/something",
                                         "Single-car accident", "Hit-and-run (they left)", "Not sure"])),
            GuideQuestion(id: "drivable", prompt: "Is your car drivable?",
                          kind: .choice(["Yes", "No — needs a tow"])),
        ],
        build: { a in
            let atScene = a["when"] != "Earlier — I've left"
            let what = val(a, "what", default: "Not sure")
            let hitRun = what == "Hit-and-run (they left)"
            let singleCar = what == "Single-car accident"
            let otherInvolved = !hitRun && !singleCar
            let drivable = a["drivable"] != "No — needs a tow"

            var steps: [String] = []
            // (911 lives on the first-page emergency banner, not in the steps.)
            if a["injuries"] == "Yes" {
                steps.append("Get medical care even if it seems minor — some injuries show up later.")
            } else if a["injuries"] == "Not sure" {
                steps.append("Check everyone for injuries before moving on.")
            }

            // At the scene vs. after the fact
            if atScene {
                steps.append("Move to safety if you can, and turn on your hazard lights.")
                steps.append("Don't argue about fault at the scene — collect the facts and let the police and insurers sort it out.")
                if hitRun {
                    steps.append("Call the police and file a report now — you'll need it for a hit-and-run claim. Note the report number.")
                    steps.append("Write down all you can about the other car: make, color, plate, and direction it went; ask any witnesses.")
                } else {
                    steps.append("Call the police if anyone's hurt, damage is major, or your state requires it — note the report number.")
                    if otherInvolved {
                        steps.append("Exchange info and photograph everything: the other driver's license, plate, insurance, both cars, and the scene.")
                    } else {
                        steps.append("Photograph the damage and scene, and note what happened.")
                    }
                }
            } else {
                steps.append("Write down what you remember and photograph the damage now.")
                steps.append(hitRun
                    ? "File a police report as soon as you can — it's required for a hit-and-run claim."
                    : "File a police report if you haven't — especially with any injury or major damage.")
            }
            if !drivable {
                steps.append("If the car isn't drivable, arrange a tow — and save the tow company, location, and receipt.")
            }

            // The claim — by what happened, in neutral terms
            if hitRun {
                steps.append("Start a claim with your own insurer under uninsured-motorist or collision coverage.")
            } else if singleCar {
                steps.append("Start a claim with your own insurer (collision or comprehensive).")
            } else if what == "The other driver hit me" {
                steps.append("Start a claim with the other driver's insurer, or with your own insurer (which can recover the cost).")
            } else if what == "I may have hit someone/something" {
                steps.append("Report it to your insurer — liability coverage handles the other party, collision your own car.")
            } else {
                steps.append("Report it to your own insurer; the insurers will investigate what happened.")
            }

            // Repair → done
            steps.append("Get a repair estimate — the insurer may inspect the car.")
            steps.append("Choose a repair shop — you can usually pick your own.")
            steps.append("Ask your insurer whether your policy covers a rental car.")
            steps.append("Pay your deductible if any, then pick up and check the car.")
            steps.append("Keep records: claim number, report number, estimates, medical bills.")

            var notes: [String] = []
            if otherInvolved {
                notes.append("If the other driver is uninsured, your uninsured-motorist (UM) coverage can step in.")
            }
            notes.append("In a no-fault state, medical costs go through your own insurer (PIP), no matter who was at fault.")
            notes.append("If pain shows up hours or days later, see a doctor and save the records.")
            notes.append("Driving a rental, leased, rideshare, or company car? Tell that owner or company too.")
            notes.append(referenceNote)

            return ExtractionResult(
                title: "After a car accident",
                documentType: "Car-accident guide",
                otherIDs: [DocID(label: "Claim number", value: ""),
                           DocID(label: "Adjuster name & phone", value: ""),
                           DocID(label: "Police report number", value: "")],
                category: .auto,
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
        if (text.hasPrefix("Start a claim") || text.hasPrefix("File") || text.hasPrefix("Report")) && text.contains("insurer") {
            return StepDetail(
                explanation: "Calling the insurer (yours or the at-fault driver's), have your details ready.",
                miniChecklist: ["Your policy number — or the at-fault driver's insurer and policy number.",
                                "Date, location, and what happened.",
                                "The police report number, if you have one.",
                                "Your photos and the other driver's info.",
                                "Ask about your deductible, a rental car, and the timeline."])
        }
        if text.hasPrefix("Get medical care") {
            return StepDetail(
                explanation: "Adrenaline can hide injuries for hours or days — getting checked soon also ties any treatment to the accident, which the insurance claim will ask about.",
                miniChecklist: ["See a doctor or urgent care within a day or two, even if you feel okay.",
                                "Tell them it was a car accident, so it's in the record.",
                                "Keep every bill, record, and receipt — the claim can reimburse them."])
        }
        if text.hasPrefix("If the car isn't drivable") {
            return StepDetail(
                explanation: "Call your insurer before the tow if you can — many policies include towing, and an approved shop avoids surprise fees. Don't let the car sit in a storage lot; storage fees add up daily.",
                miniChecklist: ["Ask your insurer about roadside/tow coverage and approved shops.",
                                "Tow to a repair shop or your home — not a storage lot.",
                                "Save the tow receipt and write down where the car is."])
        }
        if text.hasPrefix("Get a repair estimate") {
            return StepDetail(
                explanation: "The insurer usually inspects the damage — an adjuster visit or photos you upload — before approving repairs.",
                miniChecklist: ["Get a written estimate from a shop you trust.",
                                "Don't authorize repairs before the claim is approved, unless you're paying yourself.",
                                "Ask whether the shop can bill the insurer directly."])
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
            GuideQuestion(id: "insurer", prompt: "Which insurance plan? (optional)", kind: .text("e.g. Aetna, Blue Cross, Kaiser"),
                          showIf: { $0["insurance"] == "Yes" }),
            GuideQuestion(id: "new", prompt: "New patient or a return visit?", kind: .choice(["New patient", "Return visit"])),
            GuideQuestion(id: "kind", prompt: "What kind of doctor?", kind: .text("e.g. primary care, dentist")),
        ],
        build: { a in
            let insured = a["insurance"] != "No"
            let insurer = a["insurer"] ?? ""
            let kindAnswer = (a["kind"] ?? "").trimmingCharacters(in: .whitespaces)
            let isNew = a["new"] == "New patient"

            // (Emergency / urgent-care guidance lives on the first-page banner.)
            var steps: [String] = []
            // A return visit already has a doctor and is on file — skip finding one
            // and the bring-your-card/forms steps; just book and prep.
            if isNew {
                if insured {
                    steps.append("Find an in-network doctor in your plan's provider directory (or call the number on your card).")
                } else {
                    steps.append("Find a community health center or sliding-scale clinic near you.")
                }
            }
            steps.append(isNew
                ? "Call or use the patient portal to book — new-patient slots can take weeks."
                : "Call or use the patient portal to book your visit.")
            steps.append("If you need an interpreter, ask for one when you book — it's free at most clinics.")
            if isNew {
                steps.append(insured ? "Confirm they take your insurance, and if it's a specialist, whether you need a referral."
                                     : "Ask what it will cost up front and what to bring.")
            } else {
                steps.append("Note why you're going back — new or worse symptoms, a refill, or test results.")
            }
            steps.append("Before the visit, note your symptoms, medicines, allergies, and questions.")
            if isNew {
                steps.append(insured ? "Bring your insurance card and a photo ID, and arrive early for new-patient forms."
                                     : "Bring a photo ID and any medical records, and arrive early for new-patient forms.")
            }
            return ExtractionResult(
                title: kindAnswer.isEmpty ? String(localized: "Book a doctor's appointment")
                                          : String(localized: "Book a \(kindAnswer) appointment"),
                documentType: "Appointment guide",
                otherIDs: [kindAnswer.isEmpty ? nil : DocID(label: "Type of doctor", value: kindAnswer),
                           (insured && !insurer.isEmpty) ? DocID(label: "Insurance plan", value: insurer) : nil,
                           DocID(label: "Provider name", value: ""),
                           DocID(label: "Office phone", value: "")].compactMap { $0 },
                category: .medical,
                summary: isNew
                    ? (insured ? "Find an in-network doctor and get ready for the visit."
                               : "Find an affordable doctor and get ready for the visit.")
                    : "Book your visit and get ready.",
                steps: steps,
                detailedSteps: detailed(steps, state: insurer, doctorDetail),
                notes: insured ? ["In-network providers usually cost much less.",
                                  "Ask whether a telehealth (video) visit is an option — it can be faster.",
                                  referenceNote]
                               : ["Community health centers charge on a sliding scale — you can be seen without insurance.",
                                  "Ask whether a telehealth (video) visit is an option — it can be faster.",
                                  referenceNote],
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
        if text.hasPrefix("Before the visit") {
            return StepDetail(
                explanation: "A little prep makes the visit go smoothly.",
                miniChecklist: ["Your symptoms and when they started.",
                                "All medicines and doses (or bring the bottles).",
                                "Allergies and your medical / family history.",
                                "Your top questions, written down."],
                links: [StepLink(label: "MedlinePlus — make the most of your visit", url: "https://medlineplus.gov/ency/patientinstructions/000860.htm")])
        }
        if text.hasPrefix("Call or use the patient portal") {
            return StepDetail(
                explanation: "Booking goes faster with your details ready — and ask for the soonest opening.",
                miniChecklist: ["Have your insurance info, the doctor's name, and your free times ready.",
                                "Ask for the first available appointment, and the cancellation waitlist.",
                                "Say if it's urgent — they may fit you in sooner.",
                                "Confirm the date, time, address, and what to bring.",
                                "Save the appointment details and any confirmation number."])
        }
        if text.hasPrefix("Bring your insurance card") {
            return StepDetail(
                explanation: "Arrive about 15 minutes early for any new-patient paperwork.",
                miniChecklist: ["Insurance card and a government photo ID.",
                                "A list of your medicines, doses, and allergies.",
                                "A referral, if your plan needs one for a specialist.",
                                "Your copay or a payment method.",
                                "Past records or test results, if relevant."])
        }
        // Uninsured — no insurance card to bring; swap it for what actually helps
        // (records, proof of income for sliding-scale, a way to pay).
        if text.hasPrefix("Bring a photo ID") {
            return StepDetail(
                explanation: "Arrive about 15 minutes early for any new-patient paperwork.",
                miniChecklist: ["A government photo ID.",
                                "A list of your medicines, doses, and allergies.",
                                "Any past medical records or test results you have.",
                                "Proof of income, if asking about a sliding-scale fee.",
                                "A way to pay (cash or card) since you don't have insurance."])
        }
        return nil
    }

    // MARK: Taxes
    static let taxes = Guide(
        id: "taxes",
        title: "Prepare to file taxes",
        subtitle: "Gather documents, free filing, deadline",
        category: .finance,
        questions: [
            GuideQuestion(id: "income", prompt: "What income did you have?",
                          kind: .choice(["A job (W-2)", "Self-employed / 1099", "Both", "Not sure"])),
            GuideQuestion(id: "taxid", prompt: "Do you have an SSN or ITIN?",
                          kind: .choice(["Yes", "No — I need an ITIN", "Not sure"])),
        ],
        build: { a in
            let income = val(a, "income", default: "A job (W-2)")
            let needsITIN = a["taxid"] == "No — I need an ITIN"
            var steps = ["Gather your tax documents: W-2s, 1099s, any 1098-T (student) or 1095-A (Marketplace insurance), interest forms, and last year's return."]
            if needsITIN {
                steps.append("No SSN or ITIN? Apply for an ITIN with IRS Form W-7 — you can file your return at the same time.")
            }
            if income == "Self-employed / 1099" || income == "Both" {
                steps.append("Self-employed? Report your 1099 income and business expenses — you may owe quarterly estimated taxes.")
            }
            steps.append("Check whether you also need a state return — and if you moved or worked in another state, check both.")
            steps.append("File for free if you qualify: IRS Free File online, or a VITA site for free in-person help.")
            steps.append("File by the federal deadline — usually around April 15, though the exact date can shift for weekends, holidays, or disasters. Can't make it? File an extension, but any tax owed is still due by the original deadline.")
            steps.append("After filing, save a copy of your return and confirmation; if you're owed a refund, track it with the IRS 'Where's My Refund?' tool.")
            return ExtractionResult(
                title: "Prepare to file taxes",
                documentType: "Tax guide",
                otherIDs: [DocID(label: "Date filed", value: ""),
                           DocID(label: "Refund amount", value: "")],
                category: .finance,
                summary: "How to get ready to file your U.S. taxes — documents, free options, and the deadline.",
                steps: steps,
                detailedSteps: detailed(steps, state: "", taxDetail),
                notes: ["A refund means money back; owing means you pay — filing on time avoids penalties either way.",
                        referenceNote],
                confidence: 1)
        })

    private static func taxDetail(_ text: String, _ s: String) -> StepDetail? {
        if text.hasPrefix("Gather your tax documents") {
            return StepDetail(
                explanation: "Have your income forms ready before you start.",
                miniChecklist: ["W-2 from each employer.",
                                "1099 forms for contract or gig income.",
                                "Your SSN or ITIN.",
                                "Last year's return, if you have it.",
                                "Bank info for direct deposit of any refund."])
        }
        if text.contains("Form W-7") {
            return StepDetail(
                explanation: "An ITIN is a tax ID for people who can't get an SSN. Apply with IRS Form W-7, usually filed with your return.",
                links: [StepLink(label: "IRS — ITIN / Form W-7", url: "https://www.irs.gov/individuals/individual-taxpayer-identification-number")])
        }
        if text.hasPrefix("File for free") {
            return StepDetail(
                explanation: "Many people can file federally for free; eligibility depends on income and situation.",
                links: [StepLink(label: "IRS Free File", url: "https://www.irs.gov/file-your-taxes-for-free"),
                        StepLink(label: "IRS — free in-person help (VITA)", url: "https://www.irs.gov/individuals/free-tax-return-preparation-for-qualifying-taxpayers")])
        }
        if text.hasPrefix("After filing") {
            return StepDetail(
                explanation: "Refunds usually arrive within a few weeks of e-filing.",
                links: [StepLink(label: "IRS — Where's My Refund?", url: "https://www.irs.gov/refunds")])
        }
        return nil
    }

    // MARK: SSN / ITIN
    static let ssnItin = Guide(
        id: "ssn_itin",
        title: "Get an SSN or ITIN",
        subtitle: "Social Security number or tax ID",
        category: .government,
        questions: [
            GuideQuestion(id: "which", prompt: "Which do you need?",
                          kind: .choice(["SSN (I can work in the U.S.)", "ITIN (I can't get an SSN)", "Not sure"])),
        ],
        build: { a in
            let which = val(a, "which", default: "Not sure")
            var steps: [String] = []
            if which == "Not sure" {
                steps.append("An SSN is for U.S. citizens and certain noncitizens who are work-authorized or have another valid reason; an ITIN is mainly for tax filing when you're not eligible for an SSN.")
            }
            if which != "ITIN (I can't get an SSN)" {
                steps.append("For an SSN: gather proof of identity, age, and work-authorized immigration status.")
                steps.append("Apply for an SSN online, then bring your documents to a Social Security office — it's free.")
            }
            if which != "SSN (I can work in the U.S.)" {
                steps.append("For an ITIN: apply with IRS Form W-7, usually with your tax return. A VITA site can help for free.")
            }
            steps.append("Share your number only when truly required — a job, bank, or taxes — and keep it private.")
            return ExtractionResult(
                title: "Get an SSN or ITIN",
                documentType: "ID guide",
                category: .government,
                summary: "How to get a Social Security number, or an ITIN if you can't get one.",
                steps: steps,
                detailedSteps: detailed(steps, state: "", ssnItinDetail),
                notes: ["Applying is free — never pay for the number itself.",
                        referenceNote],
                confidence: 1)
        })

    private static func ssnItinDetail(_ text: String, _ s: String) -> StepDetail? {
        if text.hasPrefix("For an SSN: gather") {
            return StepDetail(
                explanation: "Bring originals — most documents can't be photocopies.",
                miniChecklist: ["Proof of identity (passport or immigration document).",
                                "Proof of work-authorized immigration status.",
                                "Proof of age (birth certificate or passport)."],
                links: [StepLink(label: "SSA — documents you'll need", url: "https://www.ssa.gov/ssnumber/ss5doc.htm")])
        }
        if text.hasPrefix("Apply for an SSN online") {
            return StepDetail(
                explanation: "SSA mails your card after processing your application; timing can vary.",
                links: [StepLink(label: "SSA — Social Security number & card", url: "https://www.ssa.gov/number-card")])
        }
        if text.hasPrefix("For an ITIN") {
            return StepDetail(
                explanation: "An ITIN is only a tax ID — it isn't work authorization or a photo ID.",
                links: [StepLink(label: "IRS — ITIN / Form W-7", url: "https://www.irs.gov/individuals/individual-taxpayer-identification-number"),
                        StepLink(label: "IRS — free help (VITA)", url: "https://www.irs.gov/individuals/free-tax-return-preparation-for-qualifying-taxpayers")])
        }
        return nil
    }

    // MARK: School enrollment
    static let schoolEnrollment = Guide(
        id: "school_enrollment",
        title: "Enroll your child in school",
        subtitle: "Documents, residency, language help",
        category: .government,
        questions: [
            GuideQuestion(id: "newcomer", prompt: "Is this your first U.S. school?",
                          kind: .choice(["Yes — new to the U.S.", "No — transferring"])),
            GuideQuestion(id: "iep", prompt: "Does your child get special-education services (IEP/504)?",
                          kind: .choice(["No", "Yes", "Not sure"])),
        ],
        build: { a in
            let newcomer = a["newcomer"] != "No — transferring"
            var steps = ["Find your assigned public school by your home address — it's set by where you live.",
                         "Gather what you'll need: proof of your child's age (birth certificate, passport, or another document the school accepts), proof of your address, and immunization records.",
                         "Ask the enrollment office for an interpreter if you need one.",
                         "Fill out the enrollment forms and the Home Language Survey."]
            if newcomer {
                steps.append("New to the U.S.? Ask about English-language (EL) support — schools must provide it.")
            } else {
                steps.append("Transferring? Ask the old school to send records (transcripts, and an IEP/504 plan if any).")
            }
            if a["iep"] == "Yes" {
                steps.append("Bring your child's IEP/504 records and ask how their services will continue at the new school.")
            }
            steps.append("Ask about bus transportation, free/reduced meals, and after-school programs.")
            steps.append("Schedule any required health check or missing vaccines, and ask what to do if records are incomplete or in another language.")
            return ExtractionResult(
                title: "Enroll your child in school",
                documentType: "School guide",
                category: .government,
                summary: "How to enroll your child in a U.S. public school — documents, residency, and language help.",
                steps: steps,
                detailedSteps: detailed(steps, state: "", schoolDetail),
                notes: ["Public schools generally can't deny enrollment based on immigration status. If asked for an SSN, ask whether it's optional or if another ID can be used.",
                        referenceNote],
                confidence: 1)
        })

    private static func schoolDetail(_ text: String, _ s: String) -> StepDetail? {
        if text.hasPrefix("Gather what you'll need") {
            return StepDetail(
                explanation: "Schools accept many documents for proof of address — a lease, a utility bill, or an affidavit.",
                miniChecklist: ["Proof of your child's age: a birth certificate, passport, or another document the school accepts.",
                                "Proof of your address (lease or utility bill).",
                                "Immunization / vaccination records.",
                                "Any past school records.",
                                "Missing one? Ask the enrollment office what alternatives they accept."],
                links: [StepLink(label: "CDC — vaccines for school", url: "https://www.cdc.gov/vaccines/")])
        }
        if text.hasPrefix("New to the U.S.?") {
            return StepDetail(
                explanation: "Public schools must offer English-language help and can't turn your child away.",
                links: [StepLink(label: "U.S. Dept. of Education — English Learner Family Toolkit", url: "https://ncela.ed.gov/family-toolkit")])
        }
        return nil
    }

    // MARK: Health insurance
    static let healthInsurance = Guide(
        id: "health_insurance",
        title: "Get health insurance",
        subtitle: "Marketplace, Medicaid, or a job plan",
        category: .medical,
        questions: [
            GuideQuestion(id: "source", prompt: "How might you get coverage?",
                          kind: .choice(["Through a job", "On my own (Marketplace)", "Low income (Medicaid/CHIP)", "Not sure"])),
            GuideQuestion(id: "lifeEvent", prompt: "A recent change — lost coverage, moved, married, had a baby, or job change?",
                          kind: .choice(["No", "Yes", "Not sure"])),
        ],
        build: { a in
            let source = val(a, "source", default: "Not sure")
            let marketplace = source == "On my own (Marketplace)" || source == "Not sure"
            var steps: [String] = []
            if a["lifeEvent"] == "Yes" {
                steps.append("A recent life change may open a Special Enrollment Period — you can sign up now, outside open enrollment.")
            }
            if source == "Through a job" {
                steps.append("Enroll through your job during your new-hire window or open enrollment.")
            }
            if marketplace {
                steps.append("Apply at HealthCare.gov — it routes you to your state's Marketplace if it runs one. Open enrollment is usually Nov 1–Jan 15.")
            }
            if source == "Low income (Medicaid/CHIP)" || source == "Not sure" {
                steps.append("Low income? Apply for Medicaid or CHIP any time of year — if approved, when coverage starts depends on your state.")
            }
            steps.append("Have your household size and income ready — that decides your options and any savings.")
            steps.append("Compare plans on premium, deductible, copays, out-of-pocket max, your doctors, and your prescriptions.")
            if marketplace {
                steps.append("If you pick a Marketplace plan, pay the first premium — coverage doesn't start until you do.")
            }
            steps.append("After you enroll, save your plan name, member ID, and start date.")
            return ExtractionResult(
                title: "Get health insurance",
                documentType: "Health-insurance guide",
                otherIDs: [DocID(label: "Plan name", value: ""),
                           DocID(label: "Member ID", value: ""),
                           DocID(label: "Coverage start date", value: "")],
                category: .medical,
                summary: "How to get health coverage — through a job, the Marketplace, or Medicaid.",
                steps: steps,
                detailedSteps: detailed(steps, state: "", healthInsuranceDetail),
                notes: ["Marketplace plans often come with savings (subsidies) based on your income.",
                        "Even if your income is low, lawfully present immigrants who don't yet qualify for Medicaid can often still get Marketplace savings.",
                        "No coverage yet? Community health centers see you on a sliding scale.",
                        referenceNote],
                confidence: 1)
        })

    private static func healthInsuranceDetail(_ text: String, _ s: String) -> StepDetail? {
        if text.hasPrefix("Apply at HealthCare.gov") {
            return StepDetail(
                explanation: "HealthCare.gov is the official Marketplace — avoid look-alike sites. Some states run their own; it'll send you there if so.",
                links: [StepLink(label: "HealthCare.gov — get ready to apply", url: "https://www.healthcare.gov/apply-and-enroll/get-ready-to-apply/")])
        }
        if text.hasPrefix("Low income?") {
            return StepDetail(
                explanation: "Medicaid and CHIP are free or low-cost coverage for lower incomes (CHIP covers kids).",
                links: [StepLink(label: "HealthCare.gov — Medicaid & CHIP", url: "https://www.healthcare.gov/medicaid-chip/")])
        }
        if text.hasPrefix("A recent life change") {
            return StepDetail(
                explanation: "A Special Enrollment Period usually gives you 60 days from the life event to enroll — after that you generally wait for open enrollment, so start now.",
                miniChecklist: ["Qualifying changes include losing other coverage, moving, marriage, a new baby or adoption, or certain income or household changes.",
                                "You may need to prove it — a coverage-loss letter, marriage or birth certificate, or a lease.",
                                "Apply at HealthCare.gov and report the life change, or start a new application."],
                links: [StepLink(label: "HealthCare.gov — Special Enrollment Period",
                                 url: "https://www.healthcare.gov/coverage-outside-open-enrollment/special-enrollment-period/")])
        }
        if text.hasPrefix("Enroll through your job") {
            return StepDetail(
                explanation: "Job-based coverage usually has a short sign-up window — about 30 days from your start date. Miss it and you may wait until the company's yearly open enrollment.",
                miniChecklist: ["Ask HR for the benefits guide and your enrollment deadline.",
                                "Compare the plans offered — premium, deductible, and whether your doctors are in-network.",
                                "Add your spouse or children if you're covering them.",
                                "Submit before the deadline and save the confirmation."])
        }
        if text.hasPrefix("Have your household size and income ready") {
            return StepDetail(
                explanation: "Your household size and income decide everything — whether you qualify for Medicaid and how large your Marketplace savings are. Lawfully present immigrants can use the Marketplace and often qualify for these savings; undocumented adults generally can't, though some states cover children and pregnancy regardless of status.",
                miniChecklist: ["Household size and everyone's income — pay stubs or last year's tax return.",
                                "Social Security numbers for anyone applying who has one.",
                                "Immigration document numbers — green card, work permit (EAD), or I-94 — for anyone applying.",
                                "A list of doctors you want to keep and prescriptions you take, to check they're covered.",
                                "An email address to create your account."],
                links: [StepLink(label: "HealthCare.gov — coverage for immigrants",
                                 url: "https://www.healthcare.gov/immigrants/")],
                needed: ["Income for everyone in your household", "Immigration document numbers"])
        }
        if text.hasPrefix("Compare plans") {
            return StepDetail(
                explanation: "Plans are grouped by metal level — Bronze, Silver, Gold, Platinum. Bronze has the lowest monthly premium but you pay more when you get care; Gold and Platinum cost more each month but less at the doctor. If your income qualifies, choose a Silver plan to unlock extra cost-sharing savings.",
                miniChecklist: ["Premium — what you pay every month, even with no visits.",
                                "Deductible — what you pay yourself before the plan starts paying.",
                                "Copay or coinsurance — your share at each visit or prescription.",
                                "Out-of-pocket max — the most you'll pay in a year; after that the plan pays 100%.",
                                "Check your doctors are in-network and your prescriptions are on the plan's drug list (formulary)."],
                links: [StepLink(label: "HealthCare.gov — how to pick a plan",
                                 url: "https://www.healthcare.gov/choose-a-plan/comparing-plans/")])
        }
        if text.hasPrefix("If you pick a Marketplace plan, pay the first premium") {
            return StepDetail(
                explanation: "The insurance company bills you directly for this first payment — not HealthCare.gov — so watch for that first bill (mail, email, or their site) and pay by the due date, or your start date won't stick.")
        }
        if text.hasPrefix("After you enroll, save") {
            return StepDetail(
                explanation: "Keep your plan name, member ID, and the member-services phone number handy — they're all on your insurance card, and you'll need them at every doctor visit and pharmacy.")
        }
        return nil
    }

    // MARK: Start a business
    // Branches on the TYPE of business (the "what kind" question), the legal
    // structure, and whether you'll hire — which together change the registration,
    // tax, license, and payroll steps. Sensitive (tax/legal), so no AI polish.
    static let startBusiness = Guide(
        id: "start_business",
        title: "Start a business",
        subtitle: "Structure, EIN, licenses, taxes",
        category: .work,
        questions: [
            GuideQuestion(id: "kind", prompt: "What kind of business is it?",
                          kind: .choice(["Freelance / solo service", "Online store (e-commerce)",
                                         "Physical shop or restaurant", "Other / not sure"])),
            GuideQuestion(id: "structure", prompt: "How do you want to set it up?",
                          kind: .choice(["Just me (sole proprietor)", "LLC", "Not sure yet"])),
            GuideQuestion(id: "employees", prompt: "Will you hire employees?",
                          kind: .choice(["No", "Yes", "Not yet"])),
            GuideQuestion(id: "state", prompt: "Which state will the business be in?", kind: .state),
        ],
        build: { a in
            let kind = val(a, "kind", default: "Other / not sure")
            let structure = val(a, "structure", default: "Not sure yet")
            let state = val(a, "state", default: "your state")
            let isLLC = structure == "LLC"
            let isSoleProp = structure == "Just me (sole proprietor)"
            let sellsGoods = kind == "Online store (e-commerce)" || kind == "Physical shop or restaurant"
            let physical = kind == "Physical shop or restaurant"
            let hiring = a["employees"] == "Yes" || a["employees"] == "Not yet"

            var steps: [String] = []
            steps.append("Write down your business idea, who your customers are, and how you'll make money — a one-page plan is enough to start.")
            steps.append("Pick a business name and check it's free in your state and as a web domain.")

            if isLLC {
                steps.append("Form your LLC: file articles of organization with your state's Secretary of State and pay the filing fee.")
            } else if isSoleProp {
                steps.append("As a sole proprietor there's usually no state formation filing — but file a DBA (\"doing business as\") if required by your state or local government to use a business name.")
            } else {
                steps.append("Choose your structure — sole proprietor (simplest) or LLC (can help separate personal and business liability, if maintained properly) — then register accordingly.")
            }

            steps.append("Get a free EIN from the IRS — needed to hire or to open a business bank account (most LLCs get one). Sole proprietors can use their SSN, but an EIN keeps it private.")
            steps.append("Check which licenses and permits you need — federal, state, and city/county.")
            if sellsGoods {
                steps.append("Apply for a state sales-tax permit so you can collect and send in sales tax.")
            }
            if physical {
                steps.append("Get local permits for your location — a business license, zoning approval, and a health permit if you serve food.")
            }
            steps.append("Open a business bank account (and consider a business credit card) to keep business and personal money separate.")
            steps.append("Set up bookkeeping from day one — track income and expenses in a spreadsheet or accounting app.")
            steps.append("Understand your taxes — business income is taxed, and self-employed owners usually pay quarterly estimated taxes.")
            if hiring {
                steps.append("Hiring? Register for state payroll taxes, get workers' comp insurance, and set up payroll and a Form I-9 for each employee.")
            }
            steps.append("Get business insurance (general liability is common) — especially if you have customers, a location, or employees.")
            steps.append("Save everything: your formation documents, EIN letter, licenses, and tax registrations.")

            var notes: [String] = []
            if isSoleProp {
                notes.append("You can start earning as a sole proprietor right away, then form an LLC later as you grow.")
            } else {
                notes.append("An LLC can help separate personal and business liability, but only if you maintain it properly; a sole proprietorship is simpler but offers no such protection.")
            }
            notes.append("An EIN is free at IRS.gov — never pay a third-party site for one.")
            notes.append("State rules, fees, and license requirements vary — confirm the specifics with your state's Secretary of State.")
            notes.append(referenceNote)

            return ExtractionResult(
                title: "Start a business",
                documentType: "Business guide",
                otherIDs: [(a["state"]?.isEmpty == false) ? DocID(label: "Business state", value: a["state"]!) : nil,
                           DocID(label: "Business name", value: ""),
                           DocID(label: "EIN", value: ""),
                           DocID(label: "State registration #", value: "")].compactMap { $0 },
                category: .work,
                summary: "A step-by-step checklist to start a business — structure, EIN, licenses, and taxes.",
                steps: steps,
                detailedSteps: detailed(steps, state: state, startBusinessDetail),
                notes: notes,
                confidence: 1)
        })

    private static func startBusinessDetail(_ text: String, _ state: String) -> StepDetail? {
        if text.contains("business idea") {
            return StepDetail(
                explanation: "A first plan can be one page — you can refine it later.",
                miniChecklist: ["What you sell and who buys it.",
                                "What you'll charge and your main costs.",
                                "How customers will find you.",
                                "What you need to launch (money, tools, space)."],
                links: [StepLink(label: "SBA — write your business plan",
                                 url: "https://www.sba.gov/business-guide/plan-your-business/write-your-business-plan")])
        }
        if text.hasPrefix("Pick a business name") {
            return StepDetail(
                explanation: "Check the name isn't already taken before you commit to it.",
                miniChecklist: ["Search your state's business registry.",
                                "Check the federal trademark database.",
                                "Check the web domain and social handles are free."],
                links: [StepLink(label: "SBA — choose your business name",
                                 url: "https://www.sba.gov/business-guide/launch-your-business/choose-your-business-name")])
        }
        if text.hasPrefix("Form your LLC") || text.hasPrefix("Choose your structure")
            || text.contains("As a sole proprietor there's usually no") {
            return StepDetail(
                explanation: "A sole proprietorship is simplest but doesn't separate your personal assets. An LLC costs a state fee and, if maintained properly, can help separate personal and business liability — but it isn't a guarantee against everything.",
                miniChecklist: ["Sole proprietor: no formation filing; you and the business are one.",
                                "LLC: file with the state; can help separate personal and business liability if maintained properly.",
                                "An accountant can help weigh the tax trade-offs."],
                links: [StepLink(label: "SBA — choose a business structure",
                                 url: "https://www.sba.gov/business-guide/launch-your-business/choose-business-structure")])
        }
        if text.hasPrefix("Get a free EIN") {
            return StepDetail(
                explanation: "An EIN is a free federal tax ID for your business. Apply directly on IRS.gov — third-party sites charge for what the IRS gives away free.",
                links: [StepLink(label: "IRS — apply for an EIN (free)",
                                 url: "https://www.irs.gov/businesses/small-businesses-self-employed/apply-for-an-employer-identification-number-ein-online")])
        }
        if text.hasPrefix("Check which licenses") {
            return StepDetail(
                explanation: "Most businesses need at least one license or permit. What you need depends on what you do and where.",
                miniChecklist: ["Federal licenses (only some industries).",
                                "State licenses and your sales-tax permit.",
                                "City/county business license and zoning.",
                                "A health permit if you handle food."],
                links: [StepLink(label: "SBA — apply for licenses & permits",
                                 url: "https://www.sba.gov/business-guide/launch-your-business/apply-licenses-permits")])
        }
        if text.hasPrefix("Open a business bank account") {
            return StepDetail(
                explanation: "A separate business account keeps your bookkeeping clean and protects an LLC's liability shield. Bring your EIN and formation documents.",
                links: [StepLink(label: "SBA — open a business bank account",
                                 url: "https://www.sba.gov/business-guide/launch-your-business/open-business-bank-account")])
        }
        if text.hasPrefix("Understand your taxes") {
            return StepDetail(
                explanation: "Self-employed owners usually pay estimated taxes four times a year and cover self-employment (Social Security + Medicare) tax.",
                links: [StepLink(label: "IRS — self-employed tax center",
                                 url: "https://www.irs.gov/businesses/small-businesses-self-employed/self-employed-individuals-tax-center")])
        }
        if text.hasPrefix("Hiring?") {
            return StepDetail(
                explanation: "Hiring adds payroll-tax registration, workers' comp, and verifying each worker's eligibility (Form I-9).",
                links: [StepLink(label: "SBA — hire and manage employees",
                                 url: "https://www.sba.gov/business-guide/manage-your-business/hire-manage-employees")])
        }
        return nil
    }
}
