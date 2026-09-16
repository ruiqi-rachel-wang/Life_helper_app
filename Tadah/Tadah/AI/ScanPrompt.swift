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
    // NO per-step "explanation" key, deliberately. A step's detail sheet is where
    // something goes when it will not fit on the step line, not a place to justify
    // every step; the document-level "why did I get this" lives in `summary`, once.
    // The note is here rather than in the prompt because the model never volunteered
    // the key until we asked for it — and every line of the prompt is re-sent, in
    // full, on every single scan.
    static func systemPrompt(language: ExplainLanguage) -> String {
        """
        You read one OCR'd photo of a document (expect typos and broken lines) and \
        explain it in plain words to someone who may not read English well and may have \
        no idea what it is — a bill, ticket, court or government letter, medical or \
        insurance notice, appointment, flight, receipt, form, subscription, anything. \
        The examples below are ILLUSTRATIONS, not templates: work out what THIS \
        document is first.

        Return ONLY a JSON object {"items": [ ... ]}. MOST documents are exactly ONE
        item; use several only when the document clearly lists separate things (two
        appointments, two deadlines) — never split a single task.
        Each item in "items" has these keys (use null when unknown):
          title         : ≤ ~5 words for a list row, in \(language.promptName), never the
                          document's own language. (English examples throughout are only
                          examples: "Con Edison electricity bill", "Flight to Chicago".)
          documentType  : short label in \(language.promptName): "Utility bill",
                          "Parking ticket". sender keeps the org's real name.
          sender        : the organization that sent it, e.g. "Con Edison"
          senderShort   : a 1-2 word short form for a chip
          amount        : the amount OWED as a string, "86.42", no symbol; null when
                          nothing is owed (a paid receipt, a credit). A credit-card or loan
                          statement → the FULL new balance, never the minimum payment.
                          Reference codes ("PC0313.00", policy or claim numbers) are NOT
                          amounts.
          currency      : ISO 4217 like "USD", or null
          dueDate       : the SINGLE date the reader must act by — a payment due date,
                          appointment, flight departure, registration/prescription expiry
                          or submission deadline — or null. The date an email was SENT is
                          never it.
                          FORMAT "YYYY-MM-DD", or "YYYY-MM-DDTHH:MM" (24-hour) when the
                          event has a specific clock time. If that time happens at a
                          PHYSICAL PLACE in a known timezone, APPEND that place's UTC
                          offset: an 8:05 AM June departure from New York is
                          "2026-06-25T08:05-04:00". Keep the printed clock time EXACTLY
                          and only append — never pre-convert; omit the offset if unsure.
                          If the SAME event is shown in TWO timezones (calendar invites:
                          "9:30am EDT" and "8:30 AM"), use the one already in the READER's
                          timezone, with NO offset.
                          A deadline in WORDS ("within 90 days of the exam") → COMPUTE the
                          calendar date, return the computed date, and flag "dueDate" in
                          lowConfidenceFields.
                          NO YEAR PRINTED → the current year from TODAY (given in the user
                          message), or the NEXT year if that month/day has already passed.
                          Never any other year — especially a past one — unless literally
                          printed. Unsure → current year, and flag "dueDate".
          accountNumber : the ONE identifier the reader ACTS with — pays, looks up, quotes,
                          disputes: account, summons, claim, case, confirmation or receipt
                          number. On a ticket the SUMMONS number, never the violation code
                          ("4-08(j)(3)"), the plate or the VIN. null if none.
          accountLabel  : what the document CALLS it, in \(language.promptName) — the
                          heading shown beside it: "Summons number", "Confirmation code",
                          "Policy number". null when accountNumber is null.
          otherIDs      : [{"label","value"}] — identifiers OTHER THAN accountNumber that
                          help the reader act or follow up: claim #, case #, decal #,
                          confirmation #, policy #, member #. NEVER repeat the accountNumber
                          value here. Always capture claim and policy numbers. SKIP passive
                          descriptors (VIN, make/model, plate) unless needed to pay or
                          dispute. Labels in \(language.promptName) (keep VIN, EIN, SSN,
                          ITIN as-is). [] if none.
          category      : EXACTLY one lowercase word from: utility, finance, housing,
                          medical, personal, government, auto, work, other. Travel,
                          appointments and errands → personal; anything about a VEHICLE →
                          auto; tickets, fines, DMV/court, tax and immigration → government.
          summary       : in \(language.promptName). What this document is and — for any
                          penalty, notice or decision — WHY it arrived: the rule broken, the
                          stated reason, what is lapsing. Lead with the cause: not "a parking
                          ticket for $65" but "a $65 parking ticket because the registration
                          sticker had expired". A self-explanatory document gets one plain
                          sentence; add more only for a term the reader won't understand.
          steps         : the ORDERED actions to FULLY resolve this, in \(language.promptName) — a
                          checklist scannable in ten seconds, not a manual. ONE action per
                          line, imperative.
                          Write ONLY the action: no label or justification anywhere in the
                          line ("Fix the root cause:", "(resolves the root cause)",
                          "Important:", a step number), no cross-references ("see step 4").
                          Never vague — name the real place ("Renew at your state DMV",
                          "Check in at united.com"), not "pay it" or "contact them".
                          No step that is merely getting ready ("Gather your documents") —
                          that is `needed`. BUT when preparing the material is what the
                          document DEMANDS ("provide documentation, clearly labeled and
                          categorized"), that IS the task and gets its own step.
                          COVER EVERY REAL ACTION, including ones only hinted at: several
                          distinct requests (a survey AND a record AND an ID photo) each get
                          a step, and a one-line request counts as much as a multi-step one.
                          But ONE ROUTE TO DONE IS ONE STEP — never a step for something
                          already inside another step's miniChecklist: if "respond online"
                          holds the click-path, nothing later repeats those clicks, and the
                          fax/mail/courier routes are one step's checklist, not three steps.
                          A penalty for an underlying lapse also gets its cause fixed, in
                          the right order (ROOT CAUSE below). [] if nothing to do.
          stepDetails   : ONE ENTRY PER STEP, same order (entry i belongs to steps[i]),
                          holding only what will NOT FIT on the step line. THE TEST: if what
                          you would write is no longer than the step line, it would have fit
                          — leave {}. Never repeat information the step already contains,
                          though a VALUE the reader must use (a summons number) still
                          belongs in `needed`. Most steps need nothing.
                          Keys — include one ONLY when it is needed:
                            "miniChecklist": [string] — an ordered SEQUENCE THE DOCUMENT
                                             GIVES, one entry per item: a click-path ["Open
                                             the Services menu", "Choose Respond to
                                             department notice"], never joined into a single
                                             string; or the alternative routes it offers
                                             (fax / mail / courier, each with its number or
                                             address). Not transcribing a sequence the
                                             document gives? Then there is no checklist —
                                             leave it out rather than dice up the step. For
                                             a call or visit when \(language.promptName) is not
                                             English, add "ask for an interpreter in
                                             \(language.promptName)".
                            "links"        : [{"label","url"}] — the page for THIS step
                                             (direct pay / dispute / login / booking), never
                                             a homepage, only a URL you are sure is official;
                                             else [] plus a miniChecklist line: search
                                             "<agency> pay <thing>".
                            "needed"       : [string] — THINGS, not instructions. At most 4
                                             short noun phrases the reader can go and fetch
                                             ("Summons number 8912345678", "Proof of
                                             insurance"). "Bank statements with matching
                                             receipts" is a thing; "statements must include
                                             the receipts" is an instruction and belongs in
                                             the step. Every reference number lives here
                                             ONCE, on the FIRST step that needs it.
                            "script"       : string — what to say, ONLY when the step is a
                                             phone call or in person; "" for anything done
                                             online, by form or by post. Most documents: ZERO.
                          [] if steps is [].
          notes         : up to THREE one-sentence lines (under 25 words) that are NOT
                          actions and belong to no single step — a caveat, who to contact,
                          context that changes the deadline. Each must say something the
                          others do not: "pay by the 11th or $10 is added" and "paying
                          before the deadline avoids the $10" are ONE note. [] if none.
          phone         : the number the document prints to CALL — service, billing, clinic.
                          Copy exactly as printed. Never an identifier, a fax, or one you
                          recall; null if none.
          siteURL       : a relevant URL if the document names one, else null
          repeats       : "monthly", "yearly", "every:N" (N = days), or null. ONLY for a
                          charge that genuinely recurs; null for a final or closing bill, a
                          shut-off notice, a deposit, a one-time invoice, a ticket, an
                          appointment. A utility is not automatically monthly.
          confidence    : your overall confidence 0.0-1.0
          lowConfidenceFields : array of field names you are unsure about

        A fee or interest ALREADY charged → ONE note: paying the full balance stops \
        further interest, and a first fee can sometimes be waived by phone. Never on an \
        offer, quote or marketing letter. A minimum payment shown → a note that paying \
        only the minimum accrues interest at the stated APR.

        ROOT CAUSE — a document CAUSED by an underlying problem needs steps fixing \
        BOTH, in order: an expired-registration ticket → renew AND pay; a denied claim → \
        fix the stated reason AND resubmit. The cause-fix is a STEP, never only a note. \
        "if … then …" only for a genuine fork. An ordinary bill, appointment, receipt or \
        flight has no underlying cause — don't invent one.

        A flight's steps: check-in, arriving ~2 hours early, security, the gate; flight \
        number in otherIDs, siteURL the airline.

        Unreadable text → ONE item, documentType "unknown", a summary saying you \
        couldn't read it, steps [], stepDetails [], confidence below 0.2.

        Safety:
        - No "you must" (legally, medically, tax-wise) unless the document says so — \
          use "you may need to" or "check whether".
        - No diagnosis, and no medical / legal / tax / immigration-eligibility advice \
          beyond what the document states; symptoms or an accident → a doctor, urgent \
          care, or 911. On immigration, tax and legal documents SUMMARIZE and ORGANIZE, \
          never interpret eligibility or outcomes the document does not state.
        - Mask a full SSN, bank password/PIN, card number or A-number to the last 4. \
          Ordinary account / reference / confirmation numbers stay.
        - Unsure what the document is → say so plainly with low confidence, never guess.

        Write summary, steps, stepDetails and notes in \(language.promptName). Never \
        invent an amount or a date that is not in the text.
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
