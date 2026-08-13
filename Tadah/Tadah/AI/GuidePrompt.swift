//  GuidePrompt.swift
//
//  The GUIDE prompt — kept separate from the scan prompt (ScanPrompt.swift).
//
//  A guide's CHECKLIST never goes to the AI any more. It used to: one call
//  reworded every step (and, with a ZIP, looked up utility companies in the same
//  response). That single call was both the reason guides took ten to forty
//  seconds and the ONLY thing translating the steps — so whenever it was slow,
//  rejected (step count changed) or failed, the user got a guide whose title and
//  step details were in 中文 and whose steps were in English. Steps are now
//  translated on-device from the String Catalog, instantly and identically every
//  time (see ExtractionResult.localized).
//
//  What's left needs the model and can't be precomputed: which real utility
//  companies serve a given ZIP code. Only housing guides ask for a ZIP, and only
//  when one is given does a guide touch the network at all.
//

import Foundation

nonisolated enum GuidePrompt {
    // System prompt for the ZIP → local utility companies lookup.
    static func utilitiesSystem(language: ExplainLanguage) -> String {
        """
        You help someone who may not read English well. \
        LIST THE LOCAL UTILITY COMPANIES for the ZIP code in the message, so the person \
        knows who to contact. Electricity, natural gas, and water & sewer are usually ONE \
        regulated provider per area, and trash is the city or one hauler — name each. \
        Internet / WiFi is competitive — name the 1–3 most common providers for that area. \
        For each company include ONLY contact methods you are confident are correct and \
        current: a website link, a customer-service phone, and/or an \
        in-person office address. It is BETTER to give only the company name than a WRONG \
        phone, website, or address — set any field you are unsure about to null; NEVER \
        invent one. Each provider is {"kind","name","website","phone","inPerson"}, where \
        "kind" is one of Electricity, Gas, Water & sewer, Trash & recycling, Internet \
        (written in \(language.promptName)). If you don't recognize the ZIP or aren't sure \
        who serves it, use an empty list.

        Return ONLY a JSON object {"providers":[...]} in \(language.promptName).
        """
    }

    static func utilitiesUser(context: String, zip: String) -> String {
        "Situation: \(context)\n\nZIP code for local utilities: \(zip)"
    }
}
