//  ReviewView.swift
//
//  Review & Action — the hero screen, shown immediately after a scan
//  or upload. The AI has silently pre-filled every field; the user
//  glances, optionally edits, and taps "Add to inbox."
//
//  This is the screen the product wins or loses on. Treat it like a
//  product detail page, not a results screen.
//
//  Currently mock data (the Con Edison utility bill). Week 6 wires it
//  to a real ExtractionResult from the OCR + LLM pipeline.
//

import SwiftUI

struct ReviewView: View {
    // Lets the × close button pop this screen off the stack.
    @Environment(\.dismiss) private var dismiss

    // The recurring toggle is the one interactive bit for now.
    @State private var repeatsMonthly = true

    private let steps = [
        "Open Con Edison and sign in.",
        "Pay $86.42 before June 15.",
        "Save the confirmation number.",
        "Mark this done in Notie.",
    ]

    var body: some View {
        ZStack(alignment: .top) {
            Color.paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    modalHeader
                    documentHead
                        .padding(.horizontal, 24)
                        .padding(.top, 8)

                    statCards
                        .padding(.horizontal, 14)
                        .padding(.top, 18)

                    actionStepsCard
                        .padding(.horizontal, 14)
                        .padding(.top, 18)

                    remindersCard
                        .padding(.horizontal, 14)
                        .padding(.top, 14)

                    confirmButton
                        .padding(.horizontal, 14)
                        .padding(.top, 18)

                    Spacer(minLength: 40)
                }
                .padding(.top, 48)
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: header

    // × close · "REVIEW · 3.2s" (extraction time as a quiet trust
    // signal) · Edit link.
    private var modalHeader: some View {
        HStack {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.faint)
                .onTapGesture { dismiss() }
            Spacer()
            Text("REVIEW · 3.2s")
                .font(.eyebrow).tracking(1.4).foregroundStyle(Color.faded)
            Spacer()
            Text("Edit")
                .font(.eyebrow).tracking(0.4).foregroundStyle(Color.accent)
        }
        .padding(.horizontal, 22)
    }

    // MARK: document head — the AI explanation

    private var documentHead: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("UTILITY BILL · CON EDISON")
                .font(.eyebrow).tracking(1.4).foregroundStyle(Color.faded)

            Text("An electricity bill for your apartment.")
                .font(.serifModal)
                .tracking(-0.4)
                .foregroundStyle(Color.ink)
                .lineSpacing(2)

            // One-line summary with inline bold amount + date.
            // Markdown ** ** renders bold; iOS 26 prefers this over Text +.
            Text("Pay **$86.42** by **June 15** to avoid a late fee.")
                .font(.subline)
                .foregroundStyle(Color.faded)
                .lineSpacing(2)

            Text("EN")
                .font(.eyebrow).tracking(0.6).foregroundStyle(Color.faint)
                .padding(.top, 4)
        }
    }

    // MARK: stat cards

    private var statCards: some View {
        HStack(spacing: 8) {
            statCard(label: "AMOUNT", value: "$86.42", sub: "electricity", tone: Color.ink)
            statCard(label: "DUE", value: "Jun 15", sub: "in 4 days", tone: Color.warn)
        }
    }

    private func statCard(label: String, value: String, sub: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
            Text(value).font(.serifStat).tracking(-1.0).foregroundStyle(tone)
            Text(sub).font(.subline).foregroundStyle(Color.faded)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }

    // MARK: action steps

    private var actionStepsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ACTION STEPS")
                .font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                .padding(.bottom, 10)

            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    Text(String(format: "%02d", index + 1))
                        .font(.eyebrow)
                        .foregroundStyle(Color.faded)
                        .frame(width: 22, alignment: .leading)
                    Text(step)
                        .font(.body14)
                        .foregroundStyle(Color.ink)
                    Spacer()
                }
                .padding(.vertical, 8)
                .overlay(alignment: .top) {
                    if index != 0 {
                        Rectangle().fill(Color.hairD).frame(height: 1)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }

    // MARK: reminders + recurring

    private var remindersCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("REMIND ME")
                .font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                .padding(.bottom, 10)

            HStack(spacing: 6) {
                ForEach(["3 days before", "1 day before", "Due day"], id: \.self) { chip in
                    Text(chip)
                        .font(.eyebrow).tracking(0.3)
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.bg))
                }
            }

            Rectangle().fill(Color.hairD).frame(height: 1)
                .padding(.vertical, 12)

            HStack {
                Text("Repeats monthly")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.ink)
                Spacer()
                Toggle("", isOn: $repeatsMonthly)
                    .labelsHidden()
                    .tint(Color.ink)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }

    // MARK: confirm

    private var confirmButton: some View {
        VStack(spacing: 10) {
            Text("Add to inbox")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.paper)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.ink))
            Text("ORIGINAL SCAN · KEEP / DELETE")
                .font(.eyebrow).tracking(0.5).foregroundStyle(Color.faint)
        }
    }
}

#Preview {
    ReviewView()
}
