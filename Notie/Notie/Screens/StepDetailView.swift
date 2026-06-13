//  StepDetailView.swift
//
//  The Step Detail sheet (Week 7) — opened when a milestone step with detail is
//  tapped. Keeps the main checklist as milestones; the instructions live here:
//  explanation, a one-level mini-checklist, what you'll need, what to say, and
//  links. Read-only for now (editable "fields to save" are a later follow-up).
//

import SwiftUI

struct StepDetailView: View {
    let step: ChecklistStep
    @Environment(\.dismiss) private var dismiss

    private var detail: StepDetail { step.detail ?? StepDetail() }

    var body: some View {
        ZStack(alignment: .top) {
            Color.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    if !detail.explanation.isEmpty {
                        Text(detail.explanation)
                            .font(.body14).foregroundStyle(Color.ink).lineSpacing(2)
                            .padding(.horizontal, 4)
                    }
                    if !detail.miniChecklist.isEmpty {
                        section("STEPS") {
                            ForEach(Array(detail.miniChecklist.enumerated()), id: \.offset) { i, line in
                                HStack(alignment: .top, spacing: 10) {
                                    Text(String(format: "%02d", i + 1))
                                        .font(.eyebrow).foregroundStyle(Color.faded)
                                        .frame(width: 22, alignment: .leading)
                                    Text(linkified(line)).font(.body14).foregroundStyle(Color.ink).tint(Color.accent)
                                    Spacer()
                                }
                            }
                        }
                    }
                    if !detail.needed.isEmpty {
                        section("WHAT YOU'LL NEED") {
                            ForEach(Array(detail.needed.enumerated()), id: \.offset) { _, line in
                                bullet(line)
                            }
                        }
                    }
                    if !detail.script.isEmpty {
                        section("WHAT TO SAY") {
                            Text(linkified(detail.script)).font(.body14).foregroundStyle(Color.ink).tint(Color.accent)
                        }
                    }
                    if !detail.links.isEmpty {
                        section("LINKS") {
                            ForEach(Array(detail.links.enumerated()), id: \.offset) { _, link in
                                if let url = URL(string: link.url) {
                                    Link(destination: url) {
                                        Label(link.label.isEmpty ? (url.host() ?? link.url) : link.label,
                                              systemImage: "safari")
                                            .font(.body14).foregroundStyle(Color.accent)
                                    }
                                }
                            }
                        }
                    }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 14).padding(.top, 20)
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("STEP").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                Text(step.text).font(.serifModal).foregroundStyle(Color.ink).lineSpacing(2)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .medium)).foregroundStyle(Color.faint)
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 4)
    }

    private func bullet(_ line: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").font(.body14).foregroundStyle(Color.faded)
            Text(linkified(line)).font(.body14).foregroundStyle(Color.ink).tint(Color.accent)
            Spacer()
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ inner: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
            inner()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }
}
