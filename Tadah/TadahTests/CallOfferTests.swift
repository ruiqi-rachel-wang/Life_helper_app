//  CallOfferTests.swift
//
//  Whether Tadah offers to make a call at all. The offer is assembled from data
//  the scan ALREADY produces — a step's `script` ("what to say") and the phone
//  number inside it — so these tests are really asking: does a realistic scan
//  result light the card up, and does an unrelated one correctly stay quiet?
//
//  A false negative here means the feature silently never appears. A false
//  positive means offering to phone something that isn't a phone number.

import Testing
import Foundation
@testable import Tadah

@Suite("Call offer")
struct CallOfferTests {

    @Test func extensionsDoNotHideAValidCallOffer() {
        for phone in ["(212) 555-0100 ext. 4", "212-555-0100 x229", "212-555-0100 extension 42"] {
            var r = ExtractionResult.empty
            r.phone = phone
            #expect(CallOffer.from(r)?.phone == phone)
            #expect(CallOffer.isValidNANP(CallOffer.phoneDigits(phone)))
            #expect(CallOffer.accept(phone, excluding: ["2125550100"]) == nil)
        }
    }

    @Test func phoneValidationRejectsNonASCIIDigits() {
        #expect(!CallOffer.isValidNANP("２１２５５５０１００"))
    }

    /// A scan result shaped the way OpenAIClient builds one: `steps` plus a
    /// parallel `detailedSteps` carrying the per-step detail.
    private func result(steps: [String],
                        details: [StepDetail?],
                        sender: String? = "Con Edison",
                        account: String? = nil,
                        accountLabel: String? = nil) -> ExtractionResult {
        var r = ExtractionResult.empty
        r.steps = steps
        r.sender = sender
        r.accountNumber = account
        r.accountLabel = accountLabel
        r.detailedSteps = zip(steps, details).map { text, detail in
            var s = ChecklistStep(text: text)
            s.detail = detail
            return s
        }
        return r
    }

    @MainActor @Test func savedOfferSurvivesSyncWithoutNumberInSteps() throws {
        var scan = result(steps: ["Ask about the bill"], details: [nil], account: "4829105512")
        scan.phone = "(212) 555-0100"
        let item = ActionItem(from: scan)
        let expected = try #require(CallOffer.from(scan))
        #expect(CallOffer.from(item) == expected)
        let data = try JSONEncoder().encode(TaskDTO(item))
        let restored = try JSONDecoder().decode(TaskDTO.self, from: data).makeItem()
        #expect(CallOffer.from(restored) == expected)
        #expect(!expected.goal.contains("4829105512"))
    }

    @Test func pairsModelNumberWithItsOwnOfficeQuestion() {
        var scan = result(steps: ["Call clinic at (212) 555-0100", "Call insurer at (800) 555-0200"],
            details: [StepDetail(explanation: "", script: "Book my appointment"),
                      StepDetail(explanation: "", script: "Ask about coverage")])
        scan.phone = "(800) 555-0200"
        #expect(CallOffer.from(scan)?.goal == "Ask about coverage")
        scan.phone = "(718) 555-0300"
        #expect(CallOffer.from(scan)?.goal.contains("appointment") == false)
        #expect(CallOffer.from(scan)?.goal.contains("coverage") == false)
    }

    @Test func multipleNumbersInOneStepDoNotBorrowItsScript() {
        var scan = result(steps: ["Call (212) 555-0100 or (800) 555-0200"],
                          details: [StepDetail(explanation: "", script: "Book a visit at the clinic")])
        scan.phone = "(800) 555-0200"
        #expect(CallOffer.from(scan)?.goal.contains("Book a visit") == false)
    }

    @MainActor @Test func unknownCreationErrorsAreNotPresentedAsSafeRetries() {
        #expect(!CallCenter.isDefiniteRefusal(URLError(.timedOut)))
        #expect(!CallCenter.isDefiniteRefusal(ActionsService.ActionError.decode))
        #expect(!CallCenter.isDefiniteRefusal(ActionsService.ActionError.server(502)))
        #expect(CallCenter.isDefiniteRefusal(ActionsService.ActionError.needsDetail("Which office?")))
    }

    // ── The number ──────────────────────────────────────────────────────────

    @Test func findsTheNumberInsideAScript() {
        let r = result(
            steps: ["Call Con Edison about the increase", "Pay $214.60 by Sept 28"],
            details: [StepDetail(explanation: "", script: "Call (800) 752-6633 and ask why the bill went up."), nil])
        let offer = CallOffer.from(r)
        #expect(offer != nil)
        #expect(offer?.phone.contains("752-6633") == true)
        #expect(offer?.business == "Con Edison")
    }

    @Test func fallsBackToTheStepTextWhenThereIsNoScript() {
        let r = result(steps: ["Call 1-800-772-1213 to book an appointment"], details: [nil])
        let offer = CallOffer.from(r)
        #expect(offer != nil)
        // With no script, the step itself becomes the goal.
        #expect(offer?.goal == "Call 1-800-772-1213 to book an appointment")
    }

    @Test func takesTheFirstCallableStepNotTheFirstStep() {
        let r = result(
            steps: ["Gather your last two bills", "Call the billing office"],
            details: [StepDetail(explanation: "Find them in your email.", script: ""),
                      StepDetail(explanation: "", script: "Call (212) 555-0100 and ask for a payment plan.")])
        let offer = CallOffer.from(r)
        #expect(offer?.phone.contains("555-0100") == true)
        #expect(offer?.goal.contains("payment plan") == true)
    }

    @Test func prefersTheScriptOverTheStepTextAsTheGoal() {
        // The script is what the app already tells the user to SAY, so it is a
        // far better opening request than the step's headline.
        let r = result(
            steps: ["Call the clinic"],
            details: [StepDetail(explanation: "", script: "Ask whether they accept Fidelis Essential at (212) 555-0100.")])
        #expect(CallOffer.from(r)?.goal.hasPrefix("Ask whether they accept") == true)
    }

    // ── Staying quiet ───────────────────────────────────────────────────────

    @Test func noOfferWhenNothingHasAPhoneNumber() {
        let r = result(
            steps: ["Pay $214.60 online by Sept 28", "Keep the receipt"],
            details: [StepDetail(explanation: "Use the payment portal.", script: ""), nil])
        #expect(CallOffer.from(r) == nil)
    }

    @Test func noOfferWhenThereAreNoStepsAtAll() {
        #expect(CallOffer.from(ExtractionResult.empty) == nil)
    }

    @Test func anAmountOrADateIsNotAPhoneNumber() {
        // The detector is Apple's, but a bill is full of digit runs and a false
        // positive here would offer to dial an invoice total.
        let r = result(steps: ["Pay 214.60 by 09/28/2026 for invoice 4829105512"], details: [nil])
        #expect(CallOffer.from(r) == nil)
    }

    // ── The model picks the number; this code only validates it ─────────────

    @Test func usesThePhoneTheModelExtracted() {
        // The model reads the whole page and knows which number is a phone line.
        // No formatting or nearby-word guessing is needed once it has answered.
        var r = result(steps: ["Call about the charge"], details: [nil],
                       account: "4160250001", accountLabel: "Account")
        r.phone = "(516) 466-4416"
        #expect(CallOffer.from(r)?.phone == "(516) 466-4416")
    }

    @Test func theModelsPhoneBeatsAnyNumberBuriedInTheSteps() {
        var r = result(
            steps: ["Call about the bill"],
            details: [StepDetail(explanation: "", script: "Call (212) 555-0100 for general enquiries.")])
        r.phone = "(516) 466-4416"      // the billing line the document actually prints
        #expect(CallOffer.from(r)?.phone == "(516) 466-4416")
    }

    @Test func aBarePhoneFromTheModelIsAcceptedWithoutFormatting() {
        // The fallback demands formatting or a nearby "call" because it is
        // GUESSING. Once the model has answered, that requirement is nonsense.
        var r = result(steps: ["Ask about the charge"], details: [nil])
        r.phone = "5164664416"
        #expect(CallOffer.from(r)?.phone == "5164664416")
    }

    @Test func aModelPhoneThatCannotBeDialledIsStillRefused() {
        // The model can mis-transcribe. Exchange "025" is impossible in the NANP,
        // so this is dropped no matter who supplied it.
        var r = result(steps: ["Call about the charge"], details: [nil])
        r.phone = "416-025-0001"
        #expect(CallOffer.from(r) == nil)
    }

    @Test func aModelPhoneThatIsReallyTheAccountNumberIsRefused() {
        var r = result(steps: ["Call about the charge"], details: [nil],
                       account: "5165550100", accountLabel: "Account")
        r.phone = "5165550100"
        #expect(CallOffer.from(r) == nil)
    }

    @Test func theGoalStillComesFromTheStepScript() {
        var r = result(
            steps: ["Call the billing office"],
            details: [StepDetail(explanation: "", script: "Ask why the bill went up this quarter.")])
        r.phone = "(516) 466-4416"
        #expect(CallOffer.from(r)?.goal == "Ask why the bill went up this quarter.")
    }

    @Test func aPrintedNumberWithNoCallStepStillGetsAnHonestDefaultGoal() {
        // The document prints a service line but no step says to ring it. The
        // user may still want to, so give them something editable.
        var r = result(steps: ["Pay online by Sept 28"], details: [nil], sender: "Con Edison")
        r.phone = "(516) 466-4416"
        let offer = CallOffer.from(r)
        #expect(offer != nil)
        #expect(offer?.goal.contains("Con Edison") == true)
    }

    // ── The bug from the real water bill ────────────────────────────────────

    @Test func doesNotDialTheAccountNumberOffAWaterBill() {
        // The real failure, 2026-09-09: NSDataDetector matched the account number
        // 4160250001 as a phone number, and the confirm page offered to ring it.
        // Two independent things must now stop it — it is not a valid NANP
        // number (exchange "025"), AND it is the document's own identifier.
        let r = result(
            steps: ["Pay the water bill or call about the charge"],
            details: [StepDetail(explanation: "", script: "账户 4160250001 的账单询问或安排付款。")],
            sender: "Manhasset-Lakeville Water District",
            account: "4160250001", accountLabel: "账户号码")
        #expect(CallOffer.from(r) == nil)
    }

    @Test func anExchangeStartingWithZeroOrOneIsNotAPhoneNumber() {
        #expect(CallOffer.isValidNANP("4160250001") == false)   // NXX 025
        #expect(CallOffer.isValidNANP("4161250001") == false)   // NXX 125
        #expect(CallOffer.isValidNANP("0165550001") == false)   // NPA 016
        #expect(CallOffer.isValidNANP("9115550100") == false)   // N11 area code
        #expect(CallOffer.isValidNANP("9005550100") == false)   // premium
        #expect(CallOffer.isValidNANP("5165550100") == true)
        #expect(CallOffer.isValidNANP("15165550100") == true)   // with country code
    }

    @Test func theAccountNumberIsRejectedEvenWhenItLooksDialable() {
        // 5165550100 is a perfectly valid number — but here it IS the account
        // number, so it must never be offered.
        let r = result(
            steps: ["Call about the bill"],
            details: [StepDetail(explanation: "", script: "Account 5165550100 — ask about the charge.")],
            account: "5165550100", accountLabel: "Account")
        #expect(CallOffer.from(r) == nil)
    }

    @Test func aBareTenDigitRunWithNoPhoneWordIsNotEnough() {
        // Structurally valid, unformatted, nothing nearby saying to ring it.
        // That is an identifier, not a number to dial.
        let r = result(steps: ["Reference 5165550100 appears on page 2"], details: [nil])
        #expect(CallOffer.from(r) == nil)
    }

    @Test func aFormattedNumberIsTakenOverABareOne() {
        let r = result(
            steps: ["Call about the bill"],
            details: [StepDetail(explanation: "", script: "Account 5165550100. Call (516) 555-0199 for billing.")])
        #expect(CallOffer.from(r)?.phone.contains("555-0199") == true)
    }

    @Test func aBareNumberCountsWhenAPhoneWordIsRightBeforeIt() {
        // Chinese and Spanish steps must work too — the scan writes in the
        // user's language, so an English-only word list would score them zero.
        for text in ["Call 5165550199 for billing", "请拨打 5165550199 查询账单", "Llame al 5165550199"] {
            let r = result(steps: [text], details: [nil])
            #expect(CallOffer.from(r)?.phone.contains("5165550199") == true, "failed on: \(text)")
        }
    }

    @Test func findsTheServiceNumberInTheNotesWhenAStepSaysToCall() {
        // The real water-bill shape: the step says to call, but the only number
        // inside it is the account number. The customer-service number is
        // printed elsewhere on the document.
        var r = result(
            steps: ["Call about the charge on account 4160250001"],
            details: [nil],
            sender: "Manhasset-Lakeville Water District",
            account: "4160250001", accountLabel: "Account")
        r.notes = ["Customer service: (516) 466-4416, Monday to Friday."]
        let offer = CallOffer.from(r)
        #expect(offer?.phone.contains("466-4416") == true)
    }

    @Test func doesNotFallBackWhenNoStepAsksYouToCall() {
        // A number in the footer must not turn a pay-online bill into a call.
        var r = result(steps: ["Pay online by Sept 28"], details: [nil])
        r.notes = ["Customer service: (516) 466-4416."]
        #expect(CallOffer.from(r) == nil)
    }

    // ── What Tadah may agree to, per document ───────────────────────────────

    @Test func permissionsFollowTheKindOfDocument() {
        var r = result(steps: ["Call (516) 555-0199"], details: [nil])
        r.category = .medical
        #expect(CallOffer.from(r)?.permissions.contains(.appointment) == true)

        r.category = .utility
        let utility = CallOffer.from(r)?.permissions ?? []
        #expect(utility.contains(.paymentPlan))
        // A water bill has no appointment to book.
        #expect(!utility.contains(.appointment))
    }

    @Test func permissionsAlwaysStartAtNothingAndEndAtCustom() {
        var r = result(steps: ["Call (516) 555-0199"], details: [nil])
        r.category = .government
        let p = CallOffer.from(r)?.permissions ?? []
        #expect(p.first == .nothing)
        #expect(p.last == .custom)
    }

    @Test func moneyOnTheDocumentAlwaysAllowsAPaymentArrangement() {
        var r = result(steps: ["Call (516) 555-0199"], details: [nil])
        r.category = .personal        // classifier said nothing useful
        r.amount = 214.60
        #expect(CallOffer.from(r)?.permissions.contains(.paymentPlan) == true)
    }

    // ── The account number ──────────────────────────────────────────────────

    @Test func carriesTheAccountNumberForTheOptInCheckbox() {
        let r = result(
            steps: ["Call about the bill"],
            details: [StepDetail(explanation: "", script: "Call (800) 752-6633.")],
            account: "8290 1055 12", accountLabel: "Account")
        let offer = CallOffer.from(r)
        #expect(offer?.accountNumber == "8290 1055 12")
        #expect(offer?.accountLabel == "Account")
        // Shown as "···5512" on the confirm page — never the whole number.
        #expect(offer?.accountTail == "5512")
    }

    @Test func accountTailIsSafeForShortOrMissingNumbers() {
        var r = result(steps: ["Call (800) 752-6633"], details: [nil], account: "12")
        #expect(CallOffer.from(r)?.accountTail == "12")
        r = result(steps: ["Call (800) 752-6633"], details: [nil], account: nil)
        #expect(CallOffer.from(r)?.accountTail == nil)
    }

    // ⚠️ SERIALIZED ON PURPOSE. These share one UserDefaults dictionary, and
    // both stores read-modify-write it whole. Swift Testing runs tests in
    // parallel by default, so two of them racing lose each other's writes and
    // fail at random — which says nothing about the code under test. The app
    // only ever touches these from the main actor, so the race is the test
    // harness's, not the product's.
    @Suite("Calls remembered across a relaunch", .serialized)
    struct Remembering {
// ── Remembering across a relaunch ───────────────────────────────────────

@Test func pendingCallSurvivesAsAPointerAndCanBeCleared() {
    let item = UUID()
    PendingCall.forget(item)
    #expect(PendingCall.inFlight(for: item) == nil)
    PendingCall.remember("action-123", business: "Con Edison", for: item)
    #expect(PendingCall.inFlight(for: item)?.actionID == "action-123")
    PendingCall.forget(item)
    #expect(PendingCall.inFlight(for: item) == nil)
}

// The watcher writes the record, and it runs long after the Review screen
// (and its CallOffer) are gone — so the name has to travel in the pointer or
// the answer lands on the to-do with nothing saying who was rung.
@Test func pendingCallCarriesWhoIsBeingRung() {
    let item = UUID()
    PendingCall.forget(item)
    PendingCall.remember("action-456", business: "Manhasset-Lakeville Water District", for: item)
    #expect(PendingCall.inFlight(for: item)?.business == "Manhasset-Lakeville Water District")
    PendingCall.forget(item)
}

// A document with no business name still has to be resumable — `business` is
// optional everywhere and must not silently drop the whole breadcrumb.
@Test func pendingCallWorksWithoutABusinessName() {
    let item = UUID()
    PendingCall.forget(item)
    PendingCall.remember("action-789", business: nil, for: item)
    #expect(PendingCall.inFlight(for: item)?.actionID == "action-789")
    #expect(PendingCall.inFlight(for: item)?.business == nil)
    PendingCall.forget(item)
}

// What CallCenter.resumeAll() reads. Nothing enumerated the breadcrumbs
// before, which is exactly why a call outliving its screen was never
// picked up again.
@Test func everyUnfinishedCallCanBeEnumerated() {
    let a = UUID(), b = UUID()
    PendingCall.forget(a); PendingCall.forget(b)
    PendingCall.remember("action-a", business: "A", for: a)
    PendingCall.remember("action-b", business: nil, for: b)
    let all = PendingCall.all
    #expect(all[a]?.actionID == "action-a")
    #expect(all[b]?.actionID == "action-b")
    // Forgetting one leaves the other alone — a finished call must not take
    // a still-running one down with it.
    PendingCall.forget(a)
    #expect(PendingCall.all[a] == nil)
    #expect(PendingCall.all[b]?.actionID == "action-b")
    PendingCall.forget(b)
}

// The to-do page's timer and the watcher's polling pace both run from this,
// so it has to survive a relaunch — and a build 7 breadcrumb without it must
// still load rather than vanish.
@Test func pendingCallRemembersWhenTheCallStarted() throws {
    let item = UUID()
    PendingCall.forget(item)
    let started = Date(timeIntervalSince1970: 1_789_000_000)
    PendingCall.remember(PendingCall.InFlight(actionID: "action-t", business: nil, startedAt: started), for: item)
    #expect(PendingCall.inFlight(for: item)?.startedAt == started)
    PendingCall.forget(item)

    let old = try JSONDecoder().decode(PendingCall.InFlight.self,
                                       from: Data(#"{"actionID":"action-old","business":"A"}"#.utf8))
    #expect(old.actionID == "action-old")
    #expect(old.startedAt == nil)
}

// ── The answer, kept beside the to-do ───────────────────────────────────

@Test func aFinishedCallIsKeptAndReadBack() {
    let item = UUID()
    CallHistory.forget(item)
    #expect(CallHistory.record(for: item) == nil)
    let record = CallRecord(business: "Con Edison", endedAt: .now, didFail: false,
                            detail: "They will extend the due date to the 30th.",
                            summary: nil, agreed: "Due date moved to the 30th",
                            nextStep: nil, needsUserAction: false)
    CallHistory.save(record, for: item)
    #expect(CallHistory.record(for: item)?.agreed == "Due date moved to the 30th")
    #expect(CallHistory.record(for: item)?.didFail == false)
    CallHistory.forget(item)
    #expect(CallHistory.record(for: item) == nil)
}

// The answer belongs to ONE to-do. Two calls must not read each other's.
@Test func eachToDoKeepsItsOwnAnswer() {
    let a = UUID(), b = UUID()
    CallHistory.forget(a); CallHistory.forget(b)
    CallHistory.save(CallRecord(business: "A", endedAt: .now, didFail: false, detail: "first",
                                summary: nil, agreed: nil, nextStep: nil,
                                needsUserAction: false), for: a)
    CallHistory.save(CallRecord(business: "B", endedAt: .now, didFail: true, detail: "second",
                                summary: nil, agreed: nil, nextStep: nil,
                                needsUserAction: false), for: b)
    #expect(CallHistory.record(for: a)?.detail == "first")
    #expect(CallHistory.record(for: b)?.detail == "second")
    #expect(CallHistory.record(for: b)?.didFail == true)
    CallHistory.forget(a); CallHistory.forget(b)
}
    }
}

// ── The call, owned by the app ──────────────────────────────────────────────

@MainActor
@Suite("Call center")
struct CallCenterTests {

    private let offer = CallOffer(phone: "(516) 466-4416", business: "Manhasset-Lakeville Water District",
                                  goal: "Ask why the bill went up.",
                                  accountNumber: "4160250001", accountLabel: "Account")

    // Asks often while an answer is likely, less often after, and stops before
    // it can become a phone that polls all day.
    @Test func pollingSlowsDownAndThenStops() {
        #expect(CallCenter.pollDelay(sinceStart: 0) == 5)
        #expect(CallCenter.pollDelay(sinceStart: 9 * 60) == 5)
        #expect(CallCenter.pollDelay(sinceStart: 11 * 60) == 30)
        #expect(CallCenter.pollDelay(sinceStart: 119 * 60) == 30)
        #expect(CallCenter.pollDelay(sinceStart: 121 * 60) == nil)
    }

    // The account number is the user's data going to a third party: it goes
    // only when they switched it on.
    @Test func theAccountNumberIsSentOnlyWhenSwitchedOn() {
        let item = UUID()
        let without = CallCenter.request(offer: offer, phone: offer.phone, goal: "Ask why.", mayAgreeTo: "",
                                         shareAccount: false, name: "Rachel", language: "en", itemID: item)
        #expect(!without.goal.contains("4160250001"))
        let with = CallCenter.request(offer: offer, phone: offer.phone, goal: "Ask why.", mayAgreeTo: "",
                                      shareAccount: true, name: "Rachel", language: "en", itemID: item)
        #expect(with.goal.contains("4160250001"))
        #expect(with.itemID == item.uuidString)
    }

    // What the user edited on the confirm page is what goes, with whom they
    // are calling put first for the agent.
    @Test func theRequestCarriesTheEditsAndWhoIsBeingCalled() {
        let r = CallCenter.request(offer: offer, phone: "212-555-0100", goal: "Ask about the late fee.",
                                   mayAgreeTo: "A later due date", shareAccount: false,
                                   name: "Rachel", language: "es", itemID: UUID())
        #expect(r.phone == "212-555-0100")
        #expect(r.goal.hasPrefix("You are calling Manhasset-Lakeville Water District."))
        #expect(r.goal.hasSuffix("Ask about the late fee."))
        #expect(r.mayAgreeTo == "A later due date")
        #expect(r.language == "es")
    }

    // A call picked up the morning after is dated when it ENDED, from the
    // Worker's millisecond timestamp, not when the phone noticed.
    @Test func aFinishedCallIsDatedByTheWorker() throws {
        let json = #"{"actionId":"a1","status":"completed","result":null,"transcript":null,"failureCode":null,"endedAt":"2026-09-16T20:12:39.123Z"}"#
        let status = try JSONDecoder().decode(ActionsService.ActionStatus.self, from: Data(json.utf8))
        let record = CallRecord(status, business: "A")
        #expect(abs(record.endedAt.timeIntervalSince1970 - 1_789_589_559.123) < 0.01)
        #expect(record.didFail == false)
    }

    @Test func aCallWithNoEndTimeStillMakesARecord() throws {
        let json = #"{"actionId":"a2","status":"failed","result":null,"transcript":null,"failureCode":"no_answer","endedAt":null}"#
        let status = try JSONDecoder().decode(ActionsService.ActionStatus.self, from: Data(json.utf8))
        #expect(status.endedDate == nil)
        #expect(CallRecord(status, business: nil).didFail)
    }
}

// ── What a refused call tells the user ──────────────────────────────────────

@MainActor
@Suite("Call refusals")
struct CallRefusalTests {

    // CALL-E asks before it dials rather than guessing. Folding that into
    // "couldn't place the call" hid the one answerable thing (2026-09-16).
    @Test func aClarifyingQuestionReachesTheUser() {
        let data = Data(#"{"error":"call_not_ready","questions":["Should the call be in Chinese?"]}"#.utf8)
        let error = ActionsService.error(from: data, status: 400)
        #expect(error == .needsDetail("Should the call be in Chinese?"))
        #expect(error.errorDescription?.contains("Should the call be in Chinese?") == true)
    }

    @Test func aLostRefusalReplyKeepsTheClarifyingQuestion() throws {
        let json = #"{"actionId":"a","status":"rejected","result":{"questions":["Which office?"],"evidence":[]}}"#
        let status = try JSONDecoder().decode(ActionsService.ActionStatus.self, from: Data(json.utf8))
        #expect(CallRecord(status, business: "Clinic").detail?.contains("Which office?") == true)
    }

    @Test func aQuestionlessClarificationStillSaysWhatToDo() {
        let error = ActionsService.error(from: Data(#"{"error":"call_not_ready"}"#.utf8), status: 400)
        #expect(error == .needsDetail(""))
        #expect(error.errorDescription?.contains("more detail") == true)
    }

    // A definite rejection is over; nothing should keep watching it. But it was
    // never dialled, so it must not be kept as a call record either.
    @Test func aRejectedCallIsFinished() {
        let status = ActionsService.ActionStatus(actionID: "a", status: "rejected", result: nil,
                                                 transcript: nil, failureCode: "call_not_ready")
        #expect(status.isFinished)
    }
}

// ── The account number goes only when it's shared ───────────────────────────

@MainActor
@Suite("Reference number consent")
struct ReferenceConsentTests {

    private func scan(script: String) -> ExtractionResult {
        var r = ExtractionResult.empty
        r.sender = "Con Edison"
        r.accountNumber = "829105512347"
        r.accountLabel = "Account"
        r.phone = "(800) 752-6633"
        r.steps = ["Call Con Edison"]
        var step = ChecklistStep(text: "Call Con Edison")
        step.detail = StepDetail(explanation: "", script: script)
        r.detailedSteps = [step]
        return r
    }

    @Test func theSuggestedQuestionLeavesTheAccountNumberOut() {
        let offer = CallOffer.from(scan(script: "Ask why account 829105512347 went up."))
        #expect(offer?.goal == "Ask why account went up.")
    }

    @Test func spacedDashedAndTranslatedSpellingsAreRemovedToo() {
        for script in ["Ask about account 8291 0551 2347.", "Ask about account 829-105-512-347.",
                       "询问账号829105512347的账单。", "Ask about account #829105512347."] {
            let goal = CallOffer.from(scan(script: script))?.goal ?? ""
            #expect(!goal.filter(\.isNumber).contains("829105512347"), "\(script) → \(goal)")
        }
    }

    @Test func switchOffSendsNoReferenceEvenIfTyped() throws {
        let offer = try #require(CallOffer.from(scan(script: "Ask why the bill went up.")))
        let off = CallCenter.request(offer: offer, phone: offer.phone, goal: "Account 829105512347: why?",
                                     mayAgreeTo: "", shareAccount: false, name: "", language: "en", itemID: UUID())
        #expect(!off.goal.contains("829105512347"))
    }

    @Test func switchOnSendsItExactlyOnce() throws {
        let offer = try #require(CallOffer.from(scan(script: "Ask why account 829105512347 went up.")))
        let on = CallCenter.request(offer: offer, phone: offer.phone, goal: offer.goal,
                                    mayAgreeTo: "", shareAccount: true, name: "", language: "en", itemID: UUID())
        #expect(on.goal.components(separatedBy: "829105512347").count == 2)
    }

    @Test func otherNumbersInTheQuestionStay() {
        let goal = CallOffer.removingReference("829105512347", from: "Ask about the $214.60 charge on 09/28.")
        #expect(goal == "Ask about the $214.60 charge on 09/28.")
    }

    @Test func aScriptThatWasOnlyTheNumberStillHasAQuestion() {
        let goal = CallOffer.questionWithoutReference("829105512347", reference: "829105512347", who: "Con Edison")
        #expect(!goal.isEmpty)
    }
}

// ── A pending call belongs to the account that placed it ────────────────────

@Test func aPendingCallIsOnlyWatchedByItsOwnAccount() {
    let mine = PendingCall.InFlight(actionID: "a", business: nil, startedAt: .now, owner: "user-a")
    #expect(mine.belongs(to: "user-a"))
    #expect(!mine.belongs(to: "user-b"))
    #expect(!mine.belongs(to: nil))
    // Written before owners were recorded: any signed-in account may pick it up.
    #expect(PendingCall.InFlight(actionID: "b", business: nil).belongs(to: "user-b"))
}
