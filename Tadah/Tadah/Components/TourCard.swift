//  TourCard.swift
//
//  One card of the first-run tour (drives: TourGuide) — Evernote-style coach
//  mark: a solid accent card with a bold title, one or two lines of body text,
//  page dots showing where you are, and a Next (or Done) button. Sits directly
//  next to the real control it introduces; the host screen decides whether to
//  dim what's behind it. Doing the real action the card points at also
//  dismisses it (each call site wires that via TourGuide.advance/finish).
//

import SwiftUI

struct TourCard: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let stepIndex: Int       // which page dot is lit (TourGuide.Step.rawValue)
    var isLast = false       // last card: button says Done, no Skip
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(size: 13.5))
                .foregroundStyle(.white.opacity(0.92))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 5) {
                ForEach(0..<TourGuide.stepCount, id: \.self) { i in
                    Circle()
                        .fill(.white.opacity(i == stepIndex ? 1 : 0.35))
                        .frame(width: 6, height: 6)
                }
                Spacer()
                if !isLast {
                    Button(action: onSkip) {
                        Text("Skip")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.vertical, 7).padding(.horizontal, 10)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onNext) {
                    Text(isLast ? "Done" : "Next")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Color.accent)
                        .padding(.vertical, 7).padding(.horizontal, 16)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.accent))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
    }
}

#Preview {
    VStack(spacing: 20) {
        TourCard(title: "Welcome to Tadah",
                 message: "Let's take a quick tour — add your first to-do and see how Tadah keeps you on track.",
                 stepIndex: 0, onNext: {}, onSkip: {})
        TourCard(title: "Your to-dos live here",
                 message: "Tap one to open it, or swipe it left to mark it done. You're all set.",
                 stepIndex: 3, isLast: true, onNext: {}, onSkip: {})
    }
    .padding()
    .background(Color.bg)
}
