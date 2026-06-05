//  ScanResultView.swift
//
//  Shown right after a photo is captured or picked. Runs Apple Vision OCR
//  on the image and shows the raw recognized text — the Week 4 deliverable
//  ("scan a letter → see the text").
//
//  TEMP (Week 5–6): "Continue to review" goes to the still-mock Review.
//  Week 5 adds rule parsing + AI extraction that fills Review from THIS
//  text; for now the text is real but Review's pre-fill is not.
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
                        NavigationLink {
                            ReviewView()
                        } label: {
                            Text("Continue to review")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.paper)
                                .frame(maxWidth: .infinity).padding(.vertical, 15)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.ink))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.top, 18)

                        Text("NEXT: AI WILL FILL IN AMOUNT / DUE / STEPS (WEEK 6)")
                            .font(.eyebrow).tracking(0.4).foregroundStyle(Color.faint)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 10)
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
}
