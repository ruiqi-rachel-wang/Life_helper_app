//  GuidePrompt.swift
//
//  The GUIDE prompt — kept separate from the scan prompt (ScanPrompt.swift).
//  A guide makes EXACTLY ONE AI call (OpenAIClient.buildGuide): it rewrites the
//  deterministic checklist to read naturally and, only when the person gave a ZIP,
//  also looks up their local utility companies — both in a single JSON response,
//  so we never make two calls for one guide.
//

import Foundation

nonisolated enum GuidePrompt {
    // System prompt for the one guide call. `includeUtilities` adds the second job
    // (and only then) so non-housing guides keep a lean prompt.
    static func system(includeUtilities: Bool, language: ExplainLanguage) -> String {
        let rewrite = """
        REWRITE THE CHECKLIST: make each step simple to read at a glance, in \
        plain \(language.promptName). ONE short sentence per step, about the same length as the original.\
        Clarify wording only. Keep the SAME checklist: the same NUMBER \
        of steps, in the same order, each still about its original action. Do NOT add, \
        remove, reorder, or invent facts. \
        Keep any URLs exactly as given. Put the rewritten steps in "steps".
        """
        let utilities = """


        ALSO LIST LOCAL UTILITY COMPANIES for the ZIP code in the message, so the person \
        knows who to contact. Electricity, natural gas, and water & sewer are usually ONE \
        regulated provider per area, and trash is the city or one hauler — name each. \
        Internet / WiFi is competitive — name the 1–3 most common providers for that area. \
        For each company include ONLY contact methods you are confident are correct and \
        current: a website link , a customer-service phone, and/or an \
        in-person office address. It is BETTER to give only the company name than a WRONG \
        phone, website, or address — set any field you are unsure about to null; NEVER \
        invent one. Each provider is {"kind","name","website","phone","inPerson"}, where \
        "kind" is one of Electricity, Gas, Water & sewer, Trash & recycling, Internet \
        (written in \(language.promptName)). If you don't recognize the ZIP or aren't sure \
        who serves it, use an empty list. Put the companies in "providers".
        """
        let shape = includeUtilities
            ? "Return ONLY a JSON object {\"steps\":[...],\"providers\":[...]} in \(language.promptName)."
            : "Return ONLY a JSON object {\"steps\":[...],\"providers\":[]} in \(language.promptName)."
        return "You help someone who may not read English well. "
            + rewrite + (includeUtilities ? utilities : "") + "\n\n" + shape
    }

    static func user(context: String, steps: [String], zip: String?) -> String {
        var u = "Situation: \(context)\nSteps:\n"
            + steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        if let zip, !zip.isEmpty { u += "\n\nZIP code for local utilities: \(zip)" }
        return u
    }
}
