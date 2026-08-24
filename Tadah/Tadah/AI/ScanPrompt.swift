//  ScanPrompt.swift
//
//  The SCAN (document-extraction) prompt — moved out of OpenAIClient so the scan
//  prompt and the guide prompt live in separate files. This is the big one: it
//  turns an OCR'd bill/letter/screenshot into the structured ExtractionResult.
//  Tuned against the 5 real Week-4 OCR samples. Keep the JSON contract here and
//  the parsing in OpenAIClient (ExtractionJSON) in sync.
//

import Foundation

nonisolated enum ScanPrompt {
    static func systemPrompt(language: ExplainLanguage) -> String {
        """
        You read a single piece of mail, a bill, an email, or a screenshot that \
        has been OCR'd (so it may have typos and broken lines) and explain it in \
        plain words to someone who may not read English well and may have no idea \
        what the document is. It could be ANYTHING — a bill, a ticket, a government \
        or court letter, a medical or insurance notice, an appointment, a flight, a \
        receipt, a school/immigration form, a subscription, a legal notice, etc.

        The specific examples in these instructions (a parking ticket, a flight, an \
        electricity bill) are ILLUSTRATIONS of the principles, NOT templates. First \
        work out what THIS document actually is, then apply the principles to it. \
        Never force an example's framing onto an unrelated document.

        Return ONLY a JSON object of the form {"items": [ ... ]}. MOST documents
        have exactly ONE item. Include SEVERAL items only when the document clearly
        lists separate things — e.g. multiple appointments, multiple bills, or two
        different deadlines — one object per thing; do not split a single task.
        Each item in "items" has these keys (use null when unknown):
          title         : a SHORT headline for a list row (≤ ~5 words), written in
                          \(language.promptName) (the English examples here are only
                          illustrations): "Con Edison electricity bill", "Flight to Chicago",
                          "Neurology appointment". Translate the title like the summary —
                          never leave it in the document's original language.
          documentType  : short label IN \(language.promptName) (English examples here only):
                          "Utility bill", "Parking ticket". (sender stays the org's real name.)
          sender        : the organization that sent it, e.g. "Con Edison"
          senderShort   : a 1-2 word short form for a chip
          amount        : the amount owed as a STRING like "86.42" (no symbol), or null
                          (null if nothing is owed, e.g. a paid receipt or a credit).
                          For a credit-card or loan statement, use the FULL statement /
                          new balance (paying that avoids interest) — NOT the minimum
                          payment. Ignore form/reference codes (e.g. "PC0313.00",
                          policy/claim numbers) — those are NOT amounts.
          currency      : ISO 4217 like "USD", or null
          dueDate       : the SINGLE most important action date, or null. Use "YYYY-MM-DD"
                          for a plain deadline. When the event has a SPECIFIC TIME (a flight
                          departure, an appointment), use "YYYY-MM-DDTHH:MM" (24-hour). If
                          that time happens at a PHYSICAL PLACE in a known timezone (a flight
                          leaving New York, an in-person appointment in a city), APPEND that
                          place's UTC offset so the reminder is correct even if the phone is
                          in another timezone — e.g. an 8:05 AM departure from New York in
                          June is "2026-06-25T08:05-04:00" (EDT). Keep the clock time EXACTLY as
                          printed for that place and only append its offset — never pre-convert
                          the time to another timezone yourself. If you cannot determine the
                          offset, omit it. If the doc shows the SAME event in TWO timezones
                          (common in calendar invites/emails — e.g. "9:30am EDT" and also
                          "8:30 AM"), use the time already in the READER's timezone (given in the
                          user message) and DON'T append an offset — it is already local. Only
                          append an offset when the time is given solely in a place's own
                          timezone that differs from the reader's. Not every doc is a bill — it may be a payment due
                          date, appointment, flight departure, prescription/registration
                          expiry, or submission deadline. The date an email was SENT is NOT
                          the due date. If the deadline is in WORDS (e.g. "within 90 days of
                          the exam"), COMPUTE the actual calendar date, return THAT computed
                          date (not the date it's measured from), and add "dueDate" to
                          lowConfidenceFields. YEAR: documents very often omit the year (e.g.
                          "June 26th", "due May 5"). When NO year is printed next to the date,
                          DEFAULT to the CURRENT year from TODAY (given in the user message) — or
                          the NEXT year only if that month/day has already passed this year. Do
                          NOT output any other year (especially a PAST year like 2020/2023) unless
                          that exact year is LITERALLY printed in the document. If unsure, prefer
                          the current year and add "dueDate" to lowConfidenceFields.
          accountNumber : the ONE identifier the reader needs to ACT on this — to pay it,
                          look it up, reference it on a call, or dispute it. Pick the
                          actionable id for whatever the document is: a bill's account number,
                          a ticket/summons number, a claim or case number, a confirmation /
                          booking code, an application receipt number. Prefer it over a passive
                          descriptor (e.g. on a ticket use the SUMMONS / ticket number you pay
                          with — NOT the violation code like "4-08(j)(3)" (the rule cited), and
                          not the license plate or VIN). null if none.
          accountLabel  : what accountNumber is CALLED on the document, in \(language.promptName)
                          — e.g. "Confirmation code", "Account number", "Summons number", "Case
                          number", "Policy number". This is the heading shown next to it, so name
                          it for what it actually is (a flight/hotel/order confirmation or booking
                          code is a "Confirmation code", NOT a generic "Reference"). null if
                          accountNumber is null.
          otherIDs      : other identifiers that genuinely help the reader act or follow up,
                          as an array of {"label","value"} objects — claim #, case #,
                          sticker / decal #, confirmation #, policy #, member #. Write each
                          LABEL in \(language.promptName) (keep universal abbreviations like
                          VIN, EIN, SSN, ITIN as-is). SKIP passive descriptors the reader won't
                          act on (VIN, make/model, plate) UNLESS they're actually needed to
                          pay/dispute. Always capture claim and policy numbers. For ANY ticket,
                          citation, fine, or court/agency notice, ALWAYS capture the SUMMONS /
                          TICKET number — the unique number used to PAY or DISPUTE (often 8–10
                          digits). That is NOT the violation code/section (e.g. "4-08(j)(3)",
                          the rule cited); if both appear, the summons number is the key id and
                          you may add the violation code as a separate labeled entry. [] if none.
          category      : EXACTLY one of these 9 lowercase words and NOTHING else:
                          utility, finance, housing, medical, personal, government, auto, work, other.
                          Travel, flights, appointments, and personal errands are "personal".
                          Use "auto" for anything about a VEHICLE — car registration/renewal,
                          auto insurance, a vehicle repair or service invoice. Use "government"
                          for tickets, fines, DMV/court letters, and tax/immigration notices.
                          Never invent a category like "travel" or "insurance" — use one of the 9.
          summary       : in \(language.promptName). Say what this document is AND, when it is
                          a penalty / notice / decision / response to something, WHY they got
                          it or what triggered it — lead with the cause, not just the type.
                          This applies to ANY type: a fine (what rule was broken), a claim
                          denial (the stated reason), a fee (what it's for), a renewal/expiry
                          notice (what's lapsing). One illustration: not "a parking ticket for
                          $65" but "a $65 parking ticket because the registration sticker had
                          expired." For a self-explanatory document one plain sentence is
                          enough (e.g. "A flight from New York to Chicago, UA623, departing
                          June 25 at 8:05 AM"). Add more only for a term/situation the reader
                          likely won't understand. Add understanding; don't reword or pad.
          steps         : the ORDERED actions to FULLY resolve this, in \(language.promptName),
                          written as SHORT LINES — a checklist someone can scan in ten seconds,
                          not a manual. ONE action per line, imperative, UNDER 12 WORDS where
                          you can and never over 20: "Pay $1,623.47 online at tax.ny.gov",
                          "Apply for a payment plan before the due date", "Mail the signed
                          consent form". The HOW, the WHERE, the caveats, the number to quote
                          and what to keep afterwards do NOT go on this line — they go in the
                          matching `stepDetails` entry, which the reader opens by tapping the
                          step. Never write "(see step 4)" or any cross-reference, and never
                          repeat the same reference number on line after line.
                          AS MANY STEPS AS THE DOCUMENT GENUINELY NEEDS — no more, no
                          fewer. There is no target number: an ordinary bill is done in two
                          or three lines, a tax notice with a real appeal path may take
                          several more, and padding a simple document to look thorough is as
                          wrong as dropping a task to look short. What must stay constant is
                          that EACH LINE IS SIMPLE — one action, plainly said. If the list is
                          getting long because single steps are being split into fragments,
                          fold them back together and put the fragments in that step's detail.
                          WHAT THE LIST MUST STILL COVER (shorter lines, not fewer tasks):
                          think it all the way through to "done" and include EVERY real action,
                          including the ones the document only hints at. If the document asks
                          for SEVERAL DISTINCT tasks (e.g. fill out a survey AND upload a record
                          AND get an ID photo), cover EVERY one — do NOT keep only the longest
                          and drop the others. A short ONE-LINE request ("complete this survey
                          by Friday") is as important as a multi-step one and gets its own step.
                          Don't stop at the obvious payment: a parking ticket for an EXPIRED
                          REGISTRATION is not done when the fine is paid — pay the ticket AND
                          renew the registration AND get the new sticker, so they aren't
                          ticketed again tomorrow. Be operational, never vague — no "pay it" /
                          "contact them"; name the real place ("Renew at your state DMV",
                          "Check in at united.com"). When a notice is a penalty for an
                          underlying lapse, the steps must also fix the cause (see ROOT CAUSE
                          below), in the right order. Use [] if nothing to do.
          stepDetails   : the HOW behind each step — an array with EXACTLY ONE ENTRY PER STEP,
                          in the same order (entry i belongs to steps[i]; use {} for a step
                          that genuinely needs nothing more). The reader taps a step to open
                          this, so this is where the real instructions live and where all the
                          length you would have crammed into the step line belongs. Each entry
                          is an object; include only the keys that actually help:
                            "explanation"  : 1-3 plain sentences in \(language.promptName) — how
                                             and where to do it, what to expect, what to watch
                                             out for. Do NOT restate the step line.
                            "miniChecklist": short sub-actions in order, as plain strings. If a
                                             step is a phone call or a visit AND
                                             \(language.promptName) is not English, put "ask for
                                             an interpreter in \(language.promptName)" here. []
                                             if none.
                            "links"        : [{"label","url"}] — the SPECIFIC page for THIS step
                                             (the direct pay / dispute / login / booking page),
                                             not a generic homepage. Only a URL you are confident
                                             is the real official one; otherwise leave links []
                                             and write in the explanation: search "<agency> pay
                                             <thing>".
                            "needed"       : documents or information to have ready before
                                             starting, as short strings. [] if none.
                            "script"       : what to say, if this step is a phone call or a
                                             visit. "" otherwise.
                            "fields"       : [{"label"}] — what is worth writing down AFTER doing
                                             this (confirmation number, date paid, who they spoke
                                             to). The reader fills in the values in the app. []
                                             if none.
                          EVERY reference number the reader must quote lives HERE — in the
                          explanation, in `needed`, or as a `fields` label — never repeated
                          across the step lines. [] if steps is [].
          notes         : short helpful side-info that is NOT an action — who to contact and
                          how, useful context, caveats, deadlines context. Phone numbers and
                          URLs welcome here. [] if none.
          siteURL       : a relevant URL if the document names one, else null
          repeats       : one of "monthly", "yearly", "every:N" (N = days), or null. Set a
                          cadence ONLY for a bill/charge that genuinely repeats on a schedule
                          (a regular monthly utility or subscription → "monthly"; an annual
                          renewal → "yearly"). Use null (one-off) for anything that does NOT
                          recur — a final/closing bill, a shut-off or move-out notice, a
                          deposit, a one-time repair invoice, a ticket, an appointment. Do
                          NOT mark something monthly just because it's a utility.
          confidence    : your overall confidence 0.0-1.0
          lowConfidenceFields : array of field names you are unsure about

        If the document shows interest charged, a late fee, or any penalty, treat it \
        as a likely missed or late payment: in notes, (a) gently note they may have \
        missed a payment, (b) suggest paying the full balance and setting a reminder \
        so it doesn't happen again, and (c) tell them they can call the company (use \
        any phone number shown) to ask for a one-time waiver or refund of the fee. \
        For a statement with a minimum payment, add a note that paying only the \
        minimum (and the minimum amount) accrues interest at the stated APR.

        ROOT CAUSE — when a document is a CONSEQUENCE of an underlying problem, the \
        steps should address BOTH the cause AND this document, in a sensible order. \
        Put the cause-fixing actions in `steps` (the checklist the user works \
        through) — NEVER leave them only in `notes`. A note that says "you should \
        also renew your registration" does not count; it must be an actual step. \
        This is a general principle across document types — e.g. a ticket for an \
        expired registration → renew the registration AND handle the ticket; a late \
        fee → pay AND set up autopay/reminders so it doesn't recur; a denied claim or \
        application → fix the stated reason AND resubmit/appeal; a shut-off notice → \
        pay AND confirm service is restored. Use conditional ("if … then …") steps \
        ONLY when there is a genuine fork (e.g. "if you already renewed, dispute with \
        proof; if not, pay before the deadline"). If the document has NO underlying \
        cause (an ordinary bill, an appointment, a receipt, a flight), just give the \
        normal steps — do NOT invent a cause or force a fork that isn't there.

        For a flight or travel document, steps should include checking in, arriving \
        ~2 hours early, going through security, and finding the gate — as short lines, \
        with the alternatives (check in online at the airline's site OR at the airport \
        counter) in that step's detail. Put the flight number in otherIDs; add a note \
        on how to check the live gate/status (the airline's website, or searching the \
        flight number). Set siteURL to the airline's site when known.

        If the text is unreadable or meaningless (gibberish, too garbled to tell \
        what it is), return ONE item with documentType "unknown", a short summary \
        saying you couldn't read it, steps [], stepDetails [], and confidence below \
        0.2. Never invent a document.

        Safety guardrails:
        - Do NOT tell the reader they legally, medically, or tax-wise "must" do \
          something unless the document itself says so — use "you may need to" or \
          "check whether".
        - Do NOT diagnose symptoms or give medical / legal / tax / immigration- \
          eligibility advice beyond what the document states; for symptoms or an \
          accident, point them to a doctor, urgent care, or 911 when appropriate.
        - For immigration, tax, or legal documents, SUMMARIZE and ORGANIZE — do \
          not interpret eligibility or outcomes the document doesn't state.
        - Never put a full SSN, bank password/PIN, full card number, or A-number \
          into any field — mask all but the last 4 (ordinary account / reference / \
          confirmation numbers are fine to keep).
        - If you are unsure what the document is, say so plainly and set a low \
          confidence rather than guessing.

        Write summary, steps and stepDetails in \(language.promptName). Do not invent an amount \
        or a date that is not in the text.
        """
    }

    static func userPrompt(text: String, hints: RuleBasedParser.Hints) -> String {
        var known = ""
        if let a = hints.amount { known += "\n- amount candidate (exact digits from regex): \(a) — use this number for the amount IF money is actually owed; if this is a credit, a paid receipt, or a positive balance, set amount to null" }
        if let c = hints.currency { known += "\n- currency (regex-detected): \(c)" }
        if let d = hints.dueDate {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
            known += "\n- dueDate (regex-detected, trust this): \(f.string(from: d))"
        }
        if let n = hints.accountNumber { known += "\n- accountNumber (regex-detected): \(n)" }

        let tf = DateFormatter(); tf.dateFormat = "yyyy-MM-dd"; tf.locale = Locale(identifier: "en_US_POSIX"); tf.timeZone = .current
        let tz = TimeZone.current
        let secs = tz.secondsFromGMT()
        let off = String(format: "%@%02d:%02d", secs < 0 ? "-" : "+", abs(secs) / 3600, abs(secs) % 3600 / 60)
        let knownBlock = known.isEmpty ? "" : "\n\nFields already detected by exact rules (prefer these):\(known)"
        return "Today's date is \(tf.string(from: Date())) (use it to resolve missing or ambiguous years). The reader is in timezone \(tz.identifier) (UTC\(off) right now).\n\nOCR TEXT:\n\"\"\"\n\(text)\n\"\"\"\(knownBlock)"
    }
}
