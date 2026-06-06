//  ScanResultView.swift
//
//  Shown right after a photo is captured or picked. Runs Apple Vision OCR
//  on the image and shows the raw recognized text — the Week 4 deliverable
//  ("scan a letter → see the text").
//
//  Week 4 endpoint: the raw text IS the deliverable. There is intentionally
//  no "Continue" hand-off yet — turning this text into a plain-English summary
//  (what it is · amount · due · steps) is the Week 5–6 AI extraction. Until
//  that's real we don't open the mock Review, so a scan can never save fake data.
//

import SwiftUI

struct ScanResultView: View {
    let image: UIImage

    @State private var text: String?   // nil = still reading

    var body: some View {
        ZStack(alignment: .top) {
            Color.paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("SCANNED")
                        .font(.eyebrow).tracking(1.4).foregroundStyle(Color.faded)
                        .padding(.horizontal, 24)

                    // The captured photo.
                    Image(uiImage: image)
                        .resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
                        .padding(.horizontal, 14)
                        .padding(.top, 12)

                    extractedTextCard
                        .padding(.horizontal, 14)
                        .padding(.top, 14)

                    if text?.isEmpty == false {
                        // No "Continue" hand-off yet. Week 4 ends at the raw
                        // text above; the next step is turning it into a plain-
                        // English summary (Week 5–6 AI extraction). We don't open
                        // the mock Review, so a scan can't save fake data.
                        nextStepNote
                            .padding(.horizontal, 14)
                            .padding(.top, 18)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.top, 48)
            }
        }
        .navigationBarHidden(true)
        .task {
            text = await VisionOCR.recognizeText(in: image)
        }
    }

    @ViewBuilder
    private var extractedTextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EXTRACTED TEXT")
                .font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)

            switch text {
            case nil:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Reading…").font(.body14).foregroundStyle(Color.faded)
                }
                .padding(.vertical, 6)
            case let value? where value.isEmpty:
                Text("Couldn't read any text. Try a clearer, well-lit photo.")
                    .font(.body14).foregroundStyle(Color.bad)
            case let value?:
                Text(value)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color.ink)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }

    // A forward-looking note — NOT real output. Explains that the raw text
    // above will become a short plain-English summary once Week 5–6 AI
    // extraction lands. Replaces the old "Continue to review" button, which
    // jumped to a mock pre-filled Review and could save fake data.
    private var nextStepNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WHAT'S NEXT")
                .font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
            Text("Soon Notie will read this text and write a short summary — what the letter is, how much, by when, and the steps to handle it. For now, the text above is the result.")
                .font(.body14).foregroundStyle(Color.faded).lineSpacing(2)
            Text("AI SUMMARY · WEEK 5–6")
                .font(.eyebrow).tracking(0.4).foregroundStyle(Color.faint)
                .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }
}
