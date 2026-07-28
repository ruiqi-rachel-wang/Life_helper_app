//  StepDetailView.swift
//
//  The Step Detail sheet (Week 7) — opened when a milestone step is tapped.
//  Shows the instructions behind a milestone (explanation · one-level mini-
//  checklist · what you'll need · what to say · links) and lets the user EDIT
//  all of it. Binding-backed, so edits write straight back into the item (Detail)
//  or the draft (Review). One level only — the mini-checklist never nests.
//

import SwiftUI

struct StepDetailView: View {
    @Binding var step: ChecklistStep
    var startInEditMode: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false

    // A non-optional view of the detail for editing; clears back to nil if emptied.
    private var detail: Binding<StepDetail> {
        Binding(get: { step.detail ?? StepDetail() },
                set: { step.detail = $0.isEmpty ? nil : $0 })
    }
    private var d: StepDetail { step.detail ?? StepDetail() }

    // Jargon found anywhere in this step (title + explanation + checklist + needed),
    // explained in plain English. Auto-detected — no per-guide authoring.
    private var glossaryTerms: [GlossaryTerm] {
        let text = ([step.text, d.explanation, d.script]
                    + d.miniChecklist.map(\.text) + d.needed).joined(separator: "\n")
        return Glossary.found(in: text)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if isEditing { editor } else { reader }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 14).padding(.top, 20)
            }
            .dismissKeyboardOnTap()
        }
        .onAppear {
            if startInEditMode { isEditing = true }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("STEP").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                if isEditing {
                    TextField("Step", text: $step.text, axis: .vertical)
                        .font(.serifModal).foregroundStyle(Color.ink)
                } else {
                    Text(step.text).font(.serifModal).foregroundStyle(Color.ink).lineSpacing(2)
                }
            }
            Spacer()
            Button { isEditing.toggle() } label: {
                Text(isEditing ? "Done" : "Edit")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    // MARK: read mode

    @ViewBuilder
    private var reader: some View {
        // The authored "why and how" paragraph. Was silently dropped before —
        // every guide's explanation (and official links, below) went unshown.
        if !d.explanation.isEmpty {
            Text(linkified(d.explanation))
                .font(.body14).foregroundStyle(Color.ink).lineSpacing(3)
                .tint(Color.accent)
                .padding(.horizontal, 4)
        }
        if !d.miniChecklist.isEmpty {
            section("CHECKLIST") {
                ForEach(detail.miniChecklist.indices, id: \.self) { i in
                    let sub = detail.miniChecklist.wrappedValue[i]
                    Button {
                        detail.miniChecklist[i].done.wrappedValue.toggle()
                        rollUp()
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            checkbox(sub.done)
                            Text(linkified(sub.text))
                                .font(.body14)
                                .foregroundStyle(sub.done ? Color.faded : Color.ink)
                                .strikethrough(sub.done, color: Color.faded)
                                .tint(Color.accent)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        // A phone script, when authored ("say this when you call").
        if !d.script.isEmpty {
            section("WHAT TO SAY") {
                Text(linkified(d.script))
                    .font(.body14).foregroundStyle(Color.ink).lineSpacing(3)
                    .tint(Color.accent)
            }
        }
        if !d.needed.isEmpty {
            section("WHAT YOU'LL NEED") {
                ForEach(Array(d.needed.enumerated()), id: \.offset) { _, line in bullet(line) }
            }
        }
        // Authored official links (always .gov/.us — see GuideTests) as tappable rows.
        if !d.links.isEmpty {
            section("OFFICIAL LINKS") {
                ForEach(Array(d.links.enumerated()), id: \.offset) { _, link in
                    if let url = URL(string: link.url) {
                        Link(destination: url) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 14, weight: .semibold))
                                Text(link.label).font(.body14).multilineTextAlignment(.leading)
                                Spacer()
                            }
                            .foregroundStyle(Color.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        if !glossaryTerms.isEmpty {
            section("WHAT THESE MEAN") {
                ForEach(glossaryTerms) { t in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.term).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.ink)
                        Text(t.plain).font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        if d.isEmpty {
            Text("No details yet. Tap Edit to add instructions.")
                .font(.subline).foregroundStyle(Color.faded).padding(.horizontal, 4)
        }
    }

    // MARK: edit mode

    @ViewBuilder
    private var editor: some View {
        editSubSteps(detail.miniChecklist)
        editList("WHAT YOU'LL NEED", detail.needed, placeholder: "e.g. ID, account number, a form")
    }

    // When every sub-step is checked, the parent milestone is done too.
    private func rollUp() {
        let subs = step.detail?.miniChecklist ?? []
        if !subs.isEmpty { step.done = subs.allSatisfy(\.done) }
    }

    private func checkbox(_ done: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(done ? Color.ok : Color.faint, lineWidth: 1.5)
            .background(RoundedRectangle(cornerRadius: 4).fill(done ? Color.ok : Color.clear))
            .frame(width: 18, height: 18)
            .overlay { if done { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white) } }
    }

    private func editSubSteps(_ items: Binding<[SubStep]>) -> some View {
        section("CHECKLIST") {
            ForEach(items.wrappedValue.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 8) {
                    TextField("Add a small to-do", text: items[i].text, axis: .vertical).font(.body14).foregroundStyle(Color.ink)
                    Button { items.wrappedValue.remove(at: i) } label: {
                        Image(systemName: "minus.circle.fill").font(.system(size: 18)).foregroundStyle(Color.faint)
                    }.buttonStyle(.plain)
                }
            }
            Button { items.wrappedValue.append(SubStep(text: "")) } label: {
                Label("Add", systemImage: "plus.circle").font(.body14).foregroundStyle(Color.accent)
            }.buttonStyle(.plain).padding(.top, 2)
        }
    }

    private func editList(_ title: String, _ items: Binding<[String]>, placeholder: String) -> some View {
        section(title) {
            ForEach(items.wrappedValue.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 8) {
                    TextField(placeholder, text: items[i], axis: .vertical).font(.body14).foregroundStyle(Color.ink)
                    Button { items.wrappedValue.remove(at: i) } label: {
                        Image(systemName: "minus.circle.fill").font(.system(size: 18)).foregroundStyle(Color.faint)
                    }.buttonStyle(.plain)
                }
            }
            Button { items.wrappedValue.append("") } label: {
                Label("Add", systemImage: "plus.circle").font(.body14).foregroundStyle(Color.accent)
            }.buttonStyle(.plain).padding(.top, 2)
        }
    }

    // MARK: bits

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
