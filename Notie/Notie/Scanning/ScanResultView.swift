//  ScanResultView.swift
//
//  Shown right after a photo is captured or picked. Runs Apple Vision OCR,
//  then sends the text through the AI pipeline (RuleBasedParser + OpenAIClient
//  via ExtractionService) and shows the structured result.
//
//  This is a Week-5/6 bridge: it proves the live pipeline end-to-end inside the
//  app (real OCR → real AI → fields). The polished, EDITABLE Review screen with
//  "Add to inbox" + reminders is Week 6; this screen just displays the result
//  read-only so the pipeline is testable on a real device/simulator today.
//

import SwiftUI

struct ScanResultView: View {
    let image: UIImage

    // Lets us swap in a mock in previews; defaults to the real OpenAI pipeline.
    var service: ExtractionService = ExtractionService(extractor: OpenAIClient())

    @State private var text: String?           // nil = OCR still running
    @State private var phase: Phase = .reading

    enum Phase: Equatable {
        case reading          // OCR running
        case thinking         // AI running
        case done(ExtractionResult)
        case noText           // OCR found nothing
        case failed(String)   // AI error
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("SCANNED")
                        .font(.eyebrow).tracking(1.4).foregroundStyle(Color.faded)
                        .padding(.horizontal, 24)

                    Image(uiImage: image)
                        .resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
                        .padding(.horizontal, 14)
                        .padding(.top, 12)

                    aiCard
                        .padding(.horizontal, 14)
                        .padding(.top, 14)

                    extractedTextCard
                        .padding(.horizontal, 14)
                        .padding(.top, 14)

                    Spacer(minLength: 40)
                }
                .padding(.top, 48)
            }
        }
        .navigationBarHidden(true)
        .task { await run() }
    }

    // MARK: pipeline

    private func run() async {
        let ocr = await VisionOCR.recognizeText(in: image)
        text = ocr
        guard !ocr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .noText
            return
        }
        phase = .thinking
        do {
            let result = try await service.extract(from: ocr)
            phase = .done(result)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: AI result card

    @ViewBuilder
    private var aiCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI SUMMARY")
                .font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)

            switch phase {
            case .reading:
                loadingRow("Reading the photo…")
            case .thinking:
                loadingRow("Understanding the document…")
            case .noText:
                Text("Couldn't read any text. Try a clearer, well-lit photo.")
                    .font(.body14).foregroundStyle(Color.bad)
            case .failed(let msg):
                VStack(alignment: .leading, spacing: 4) {
                    Text("Couldn't analyze this document.")
                        .font(.body14).foregroundStyle(Color.bad)
                    Text(msg).font(.subline).foregroundStyle(Color.faded)
                }
            case .done(let result):
                resultBody(result)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }

    private func loadingRow(_ label: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(label).font(.body14).foregroundStyle(Color.faded)
        }
        .padding(.vertical, 4)
    }

    // A document is "unreadable" if the model was very unsure or labelled it
    // unknown. (Week 6 turns this into a proper "retake the photo" screen; the
    // banner here just stops gibberish from looking like a confident result.)
    private func isUnreadable(_ r: ExtractionResult) -> Bool {
        r.confidence < 0.2 || (r.documentType?.lowercased() == "unknown")
    }

    @ViewBuilder
    private func resultBody(_ r: ExtractionResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if isUnreadable(r) {
                Text("⚠︎ Couldn't read this clearly — the details below may be wrong. Try retaking the photo in better light.")
                    .font(.subline).foregroundStyle(Color.bad)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.bad.opacity(0.08)))
            }

            // Type · Sender eyebrow
            if r.documentType != nil || r.sender != nil {
                Text([r.documentType, r.sender].compactMap { $0 }.joined(separator: " · ").uppercased())
                    .font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
            }

            // Plain-language summary
            if let summary = r.summary {
                Text(summary)
                    .font(.serifModal).foregroundStyle(Color.ink).lineSpacing(2)
            }

            // Amount + due chips
            HStack(spacing: 8) {
                if let amount = r.amount {
                    chip("AMOUNT", amountString(amount, currency: r.currency), tone: Color.ink)
                }
                if let due = r.dueDate {
                    let formatted = r.dueHasTime
                        ? due.formatted(.dateTime.month(.abbreviated).day().year().hour().minute())
                        : due.formatted(.dateTime.month(.abbreviated).day().year())
                    chip("DUE", formatted, tone: Color.warn)
                }
            }

            // Steps
            if !r.steps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ACTION STEPS")
                        .font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                    ForEach(Array(r.steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text(String(format: "%02d", i + 1))
                                .font(.eyebrow).foregroundStyle(Color.faded)
                                .frame(width: 22, alignment: .leading)
                            Text(linked(step)).font(.body14).foregroundStyle(Color.ink)
                                .tint(Color.accent)
                        }
                    }
                }
                .padding(.top, 2)
            } else {
                Text("Nothing to do — this is just for your information.")
                    .font(.subline).foregroundStyle(Color.faded)
            }

            // Notes — helpful side info (contacts, caveats), not actions.
            if !r.notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("NOTES")
                        .font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                    ForEach(Array(r.notes.enumerated()), id: \.offset) { _, note in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•").font(.body14).foregroundStyle(Color.faded)
                            Text(linked(note)).font(.body14).foregroundStyle(Color.faded)
                                .tint(Color.accent)
                        }
                    }
                }
                .padding(.top, 2)
            }

            // Identifiers the reader may need later (claim/policy/account…).
            detailsSection(r)

            // Low-confidence hint
            if !r.lowConfidenceFields.isEmpty {
                Text("Double-check: \(r.lowConfidenceFields.sorted().joined(separator: ", "))")
                    .font(.subline).foregroundStyle(Color.accent)
            }

            Text("WEEK 6 · this becomes an editable Review + “Add to inbox”")
                .font(.eyebrow).tracking(0.4).foregroundStyle(Color.faint)
                .padding(.top, 2)
        }
    }

    // DETAILS = the primary accountNumber + all otherIDs, deduped by value, so
    // claim/policy/confirmation numbers always show (and never twice).
    @ViewBuilder
    private func detailsSection(_ r: ExtractionResult) -> some View {
        let ids = combinedIDs(r)
        if !ids.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("DETAILS").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                ForEach(Array(ids.enumerated()), id: \.offset) { _, id in
                    Text("\(id.label): \(id.value)")
                        .font(.subline).foregroundStyle(Color.faded)
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 2)
        }
    }

    private func combinedIDs(_ r: ExtractionResult) -> [DocID] {
        var list = r.otherIDs
        if let acct = r.accountNumber, !acct.isEmpty,
           !list.contains(where: { $0.value == acct }) {
            list.insert(DocID(label: "Reference", value: acct), at: 0)
        }
        return list
    }

    private func chip(_ label: String, _ value: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
            Text(value).font(.serifStat).tracking(-0.5).foregroundStyle(tone)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.bg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func amountString(_ amount: Decimal, currency: String?) -> String {
        let symbol = (currency ?? "USD") == "USD" ? "$" : ((currency ?? "") + " ")
        return symbol + (amount as NSDecimalNumber).stringValue
    }

    // Turns plain text into an AttributedString where URLs and phone numbers are
    // tappable links (phones become tel: links). SwiftUI Text renders these as
    // links, so "libertymutual.com" or "972-808-4154" become clickable.
    private func linked(_ string: String) -> AttributedString {
        var attr = AttributedString(string)
        let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return attr }
        let ns = string as NSString
        for m in detector.matches(in: string, range: NSRange(location: 0, length: ns.length)) {
            guard let sr = Range(m.range, in: string),
                  let lower = AttributedString.Index(sr.lowerBound, within: attr),
                  let upper = AttributedString.Index(sr.upperBound, within: attr) else { continue }
            let url: URL?
            if m.resultType == .phoneNumber, let phone = m.phoneNumber {
                url = URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" })
            } else {
                url = m.url
            }
            if let url {
                attr[lower..<upper].link = url
                attr[lower..<upper].underlineStyle = .single
            }
        }
        return attr
    }

    // MARK: raw OCR text (kept for debugging — collapsible feel)

    @ViewBuilder
    private var extractedTextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EXTRACTED TEXT (RAW OCR)")
                .font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)

            switch text {
            case nil:
                loadingRow("Reading…")
            case let value? where value.isEmpty:
                Text("No text recognized.").font(.body14).foregroundStyle(Color.bad)
            case let value?:
                Text(value)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color.faded)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }
}
