//  GuidesView.swift
//
//  The Guides tab — a library of life-event guides. Tapping one opens its
//  questions (GuideQuestionsView); answering builds a tailored checklist and
//  pushes the shared Review screen (build → AI polish → Add to inbox). A guide
//  never opens a Detail directly — it isn't a saved task until you confirm.
//

import SwiftUI
import SwiftData

// A route in the Guides stack. Carries plain values (id + answers) so the whole
// stack can be reset to root with `path.removeAll()` after building a checklist.
nonisolated enum GuideRoute: Hashable {
    case questions(String)
    case review(String, [String: String])
}

struct GuidesView: View {
    @State private var selectedCategory: ItemCategory?   // nil = All
    @State private var path: [GuideRoute] = []

    private var chipCategories: [ItemCategory] {
        Array(Set(Guide.all.map(\.category))).sorted { $0.rawValue < $1.rawValue }
    }
    private var visibleGuides: [Guide] {
        guard let selectedCategory else { return Guide.all }
        return Guide.all.filter { $0.category == selectedCategory }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                Color.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        masthead.padding(.horizontal, 24)
                        categoryChips.padding(.top, 18)
                        VStack(spacing: 10) {
                            ForEach(visibleGuides) { guide in
                                Button { path.append(.questions(guide.id)) } label: {
                                    GuideCard(guide: guide)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                        Spacer(minLength: 40)
                    }
                    .padding(.top, 48)
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: GuideRoute.self) { route in
                switch route {
                case .questions(let id):
                    if let g = Guide.all.first(where: { $0.id == id }) {
                        GuideQuestionsView(guide: g) { answers in path.append(.review(id, answers)) }
                    }
                case .review(let id, let answers):
                    if let g = Guide.all.first(where: { $0.id == id }) {
                        ReviewView(
                            load: {
                                var base = g.build(answers)
                                base.confidence = 1   // deterministic checklist — always certain
                                // Sensitive topics (immigration, money, medical, legal) stay on the
                                // device — we never send them to the AI polish pass (quietly).
                                guard g.risk == .general else { return [base] }
                                let context = "\(g.title). "
                                    + answers.map { "\($0.key): \($0.value)" }.sorted().joined(separator: ", ")
                                return [await OpenAIClient().polish(base, context: context)]
                            },
                            source: .guide,
                            loadingLabel: "Personalizing your checklist…",
                            onClose: { path.removeAll() })   // back to the guide list
                    }
                }
            }
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LIBRARY").font(.eyebrow).tracking(1.4).foregroundStyle(Color.faded)
            Text("Guides").font(.serifTitle).tracking(-0.6).foregroundStyle(Color.ink)
            Text("Life events come with a stack of paperwork. Pick a guide and Notie walks you through it.")
                .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
                .padding(.top, 4).frame(maxWidth: 300, alignment: .leading)
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("All", selected: selectedCategory == nil) { selectedCategory = nil }
                ForEach(chipCategories, id: \.self) { cat in
                    chip(cat.rawValue.capitalized, selected: selectedCategory == cat) { selectedCategory = cat }
                }
            }
            .padding(.horizontal, 18)
        }
    }

    private func chip(_ label: String, selected: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(label).font(.eyebrow).tracking(0.4)
                .foregroundStyle(selected ? Color.paper : Color.faded)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Capsule().fill(selected ? Color.ink : Color.clear))
                .overlay(Capsule().stroke(Color.hairD, lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Guide card

private struct GuideCard: View {
    let guide: Guide

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(guide.category.tint)
                Image(systemName: guide.category.symbol)
                    .foregroundStyle(.white).font(.system(size: 19, weight: .medium))
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(guide.title).font(.cardTitle).foregroundStyle(Color.ink).lineLimit(1)
                Text(guide.subtitle).font(.subline).foregroundStyle(Color.faded).lineLimit(1)
                Text(guide.category.rawValue.uppercased())
                    .font(.eyebrow).tracking(0.5).foregroundStyle(Color.faint).padding(.top, 4)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(Color.faint)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }
}

// MARK: - Questions → Review

struct GuideQuestionsView: View {
    let guide: Guide
    var onContinue: ([String: String]) -> Void
    @State private var answers: [String: String] = [:]

    // Choice and state questions must be answered — we never assume a default,
    // because the wrong assumption (e.g. "no injuries") sends the wrong checklist.
    // Text questions stay optional.
    private var missingRequired: Bool {
        guide.questions.contains { q in
            switch q.kind {
            case .choice, .state: return answers[q.id] == nil
            case .text, .date: return false   // optional
            }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(guide.category.rawValue.uppercased())
                            .font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                        Text(guide.title).font(.serifModal).foregroundStyle(Color.ink)
                        Text("A few quick questions so Notie can tailor the checklist.")
                            .font(.subline).foregroundStyle(Color.faded)
                    }
                    .padding(.horizontal, 8)

                    if guide.risk == .sensitive { privacyBadge }
                    if let note = guide.emergencyNote { emergencyBanner(note) }

                    ForEach(guide.questions) { q in questionCard(q) }

                    Button { if !missingRequired { onContinue(answers) } } label: {
                        Text(missingRequired ? "Answer the questions above to continue" : "Build my checklist")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.paper)
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 12).fill(missingRequired ? Color.faint : Color.ink))
                    }
                    .buttonStyle(.plain)
                    .disabled(missingRequired)
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 14).padding(.top, 24)
            }
        }
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
    }

    // Small reassurance for sensitive topics — built on-device, never sent to AI.
    private var privacyBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.fill").font(.system(size: 10))
            Text("Stays on your device").font(.eyebrow).tracking(0.4)
        }
        .foregroundStyle(Color.faded)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(Color.bg))
        .padding(.horizontal, 8)
    }

    // Emergency notice on the first page (e.g. "call 911"), above the questions —
    // so urgent help is never buried inside the checklist.
    private func emergencyBanner(_ note: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16)).foregroundStyle(Color.bad)
            Text(note).font(.body14).foregroundStyle(Color.ink).lineSpacing(2)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bad.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.bad.opacity(0.4), lineWidth: 1))
    }

    @ViewBuilder
    private func questionCard(_ q: GuideQuestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(q.prompt).font(.cardTitle).foregroundStyle(Color.ink)
            switch q.kind {
            case .choice(let options):
                VStack(spacing: 6) {
                    ForEach(options, id: \.self) { option in
                        let on = answers[q.id] == option
                        Button { answers[q.id] = option } label: {
                            HStack {
                                Text(option).font(.body14).foregroundStyle(Color.ink)
                                Spacer()
                                if on { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.accent) }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(on ? Color.bg : Color.clear))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Color.accent : Color.hair, lineWidth: 1))
                            .contentShape(Rectangle())   // make the whole row tappable, not just the text
                        }
                        .buttonStyle(.plain)
                    }
                }
            case .text(let placeholder):
                TextField(placeholder, text: Binding(
                    get: { answers[q.id] ?? "" },
                    set: { answers[q.id] = $0 }))
                    .font(.body14).foregroundStyle(Color.ink)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.bg))
            case .state:
                Menu {
                    ForEach(USStates.all, id: \.self) { s in
                        Button(s) { answers[q.id] = s }
                    }
                } label: {
                    HStack {
                        Text(answers[q.id] ?? "Select a state")
                            .font(.body14).foregroundStyle(answers[q.id] == nil ? Color.faded : Color.ink)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 12)).foregroundStyle(Color.faint)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.bg))
                }
            case .date:
                // Optional: only sets an answer (and a due date) once turned on.
                let isSet = answers[q.id] != nil
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Set a date", isOn: Binding(
                        get: { isSet },
                        set: { on in answers[q.id] = on ? GuideDate.encode(.now) : nil }))
                        .font(.body14).tint(Color.ink)
                    if isSet {
                        DatePicker("", selection: Binding(
                            get: { GuideDate.decode(answers[q.id]) ?? .now },
                            set: { answers[q.id] = GuideDate.encode($0) }),
                            displayedComponents: [.date])
                            .labelsHidden().datePickerStyle(.compact)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }
}

#Preview {
    GuidesView()
        .modelContainer(for: ActionItem.self, inMemory: true)
        .environment(AppRouter())
}
