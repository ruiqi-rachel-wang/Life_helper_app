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
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false

    // A non-optional view of the detail for editing; clears back to nil if emptied.
    private var detail: Binding<StepDetail> {
        Binding(get: { step.detail ?? StepDetail() },
                set: { step.detail = $0.isEmpty ? nil : $0 })
    }
    private var d: StepDetail { step.detail ?? StepDetail() }

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
        if !d.explanation.isEmpty {
            Text(d.explanation).font(.body14).foregroundStyle(Color.ink).lineSpacing(2).padding(.horizontal, 4)
        }
        if !d.miniChecklist.isEmpty {
            section("STEPS") {
                ForEach(Array(d.miniChecklist.enumerated()), id: \.offset) { i, line in
                    HStack(alignment: .top, spacing: 10) {
                        Text(String(format: "%02d", i + 1)).font(.eyebrow).foregroundStyle(Color.faded)
                            .frame(width: 22, alignment: .leading)
                        Text(linkified(line)).font(.body14).foregroundStyle(Color.ink).tint(Color.accent)
                        Spacer()
                    }
                }
            }
        }
        if !d.needed.isEmpty {
            section("WHAT YOU'LL NEED") {
                ForEach(Array(d.needed.enumerated()), id: \.offset) { _, line in bullet(line) }
            }
        }
        if !d.script.isEmpty {
            section("WHAT TO SAY") {
                Text(linkified(d.script)).font(.body14).foregroundStyle(Color.ink).tint(Color.accent)
            }
        }
        if !d.links.isEmpty {
            section("LINKS") {
                ForEach(Array(d.links.enumerated()), id: \.offset) { _, link in
                    if let url = URL(string: link.url) {
                        Link(destination: url) {
                            Label(link.label.isEmpty ? (url.host() ?? link.url) : link.label, systemImage: "safari")
                                .font(.body14).foregroundStyle(Color.accent)
                        }
                    }
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
        section("EXPLANATION") {
            TextField("Explain this step…", text: detail.explanation, axis: .vertical)
                .font(.body14).foregroundStyle(Color.ink)
        }
        editList("STEPS", detail.miniChecklist, placeholder: "Sub-step")
        editList("WHAT YOU'LL NEED", detail.needed, placeholder: "Document or info")
        section("WHAT TO SAY") {
            TextField("Script / what to say…", text: detail.script, axis: .vertical)
                .font(.body14).foregroundStyle(Color.ink)
        }
        editLinks(detail.links)
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

    private func editLinks(_ links: Binding<[StepLink]>) -> some View {
        section("LINKS") {
            ForEach(links.wrappedValue.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 8) {
                    VStack(spacing: 6) {
                        TextField("Label", text: links[i].label).font(.body14).foregroundStyle(Color.ink)
                        TextField("https://…", text: links[i].url).font(.subline).foregroundStyle(Color.faded)
                            .textInputAutocapitalization(.never)
                    }
                    Button { links.wrappedValue.remove(at: i) } label: {
                        Image(systemName: "minus.circle.fill").font(.system(size: 18)).foregroundStyle(Color.faint)
                    }.buttonStyle(.plain)
                }
            }
            Button { links.wrappedValue.append(StepLink(label: "", url: "")) } label: {
                Label("Add a link", systemImage: "plus.circle").font(.body14).foregroundStyle(Color.accent)
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
