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
    @AppStorage(ExplainLanguage.storageKey) private var explainLanguageRaw = ""
    @State private var selectedCategory: ItemCategory?   // nil = All
    @State private var path: [GuideRoute] = []

    private var chipCategories: [ItemCategory] {
        // Follow ItemCategory's most-common-first order, keeping only the
        // categories that actually have a guide.
        let present = Set(Guide.all.map(\.category))
        return ItemCategory.allCases.filter(present.contains)
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
                                .accessibilityIdentifier("guide-\(guide.id)")   // stable hook for UI tests
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
                        let language = ExplainLanguage.resolve(stored: explainLanguageRaw)
                        ReviewView(
                            load: {
                                var base = g.build(answers)
                                base.confidence = 1   // deterministic checklist — always certain
                                // Sensitive topics (immigration, money, medical, legal) stay on the
                                // device — we never send them to the AI polish pass (quietly). Note:
                                // these stay in English even when another language is picked, since
                                // they never reach the (translating) polish pass.
                                // Sensitive guides skip the AI; translate their authored
                                // content on-device via the String Catalog instead.
                                guard g.risk == .general else { return [base.localized(language)] }
                                // Remember the utilities step (if this guide has one) BEFORE the AI
                                // rewords and .localized() regenerates sub-step IDs, so we can drop in
                                // the ZIP-matched providers at the same index afterward.
                                let utilIdx = base.detailedSteps.firstIndex { $0.detail == Guide.utilitiesDetail }
                                let context = "\(g.title). "
                                    + answers.map { "\($0.key): \($0.value)" }.sorted().joined(separator: ", ")
                                // ONE AI call per guide: rewords the steps and (if a ZIP was given)
                                // looks up local utility companies in the same response.
                                let (built, providers) = await OpenAIClient()
                                    .buildGuide(base, context: context, zip: answers["zip"], language: language)
                                // Rewrite (AI) is translated; .localized() then translates the static
                                // summary/notes/detail on-device.
                                var result = built.localized(language)
                                // Replace the generic utilities detail with the named local companies
                                // (already in the user's language from the same call). Best-effort: if
                                // the lookup found nothing, keep the generic detail.
                                if let i = utilIdx, let zip = answers["zip"]?.trimmingCharacters(in: .whitespaces),
                                   let detail = Guide.utilitiesDetail(forZip: zip, providers: providers, language: language) {
                                    result.detailedSteps[i].detail = detail
                                }
                                return [result]
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
            Text("Life Guides & Checklists").font(.serifTitle).tracking(-0.6).foregroundStyle(Color.ink)
            Text("Life events come with a stack of paperwork. Pick a guide and Tadah walks you through it.")
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
            // Labels are app strings ("All" + capitalized category names that match
            // catalog keys), so localize via LocalizedStringKey.
            Text(LocalizedStringKey(label)).font(.eyebrow).tracking(0.4)
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
                // Guide title/subtitle are authored app strings → localize via the
                // catalog (LocalizedStringKey), not shown verbatim.
                Text(LocalizedStringKey(guide.title)).font(.cardTitle).foregroundStyle(Color.ink).lineLimit(1)
                Text(LocalizedStringKey(guide.subtitle)).font(.subline).foregroundStyle(Color.faded).lineLimit(1)
                Text(guide.category.displayName.uppercased())
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

    // Only the questions relevant to the answers so far (hides what doesn't matter).
    private var visibleQuestions: [GuideQuestion] { guide.visibleQuestions(answers) }

    // Choice and state questions must be answered — we never assume a default,
    // because the wrong assumption (e.g. "no injuries") sends the wrong checklist.
    // Text questions stay optional. Only VISIBLE questions are required.
    private var missingRequired: Bool {
        visibleQuestions.contains { q in
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
                        Text(guide.category.displayName.uppercased())
                            .font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                        Text(LocalizedStringKey(guide.title)).font(.serifModal).foregroundStyle(Color.ink)
                        Text("A few quick questions so Tadah can tailor the checklist.")
                            .font(.subline).foregroundStyle(Color.faded)
                    }
                    .padding(.horizontal, 8)

                    if guide.risk == .sensitive { privacyBadge }
                    if let note = guide.emergencyNote { emergencyBanner(note) }

                    ForEach(visibleQuestions) { q in questionCard(q) }

                    Button { if !missingRequired { onContinue(answers) } } label: {
                        Text(missingRequired ? "Answer the questions above to continue" : "Build my checklist")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.paper)
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 12).fill(missingRequired ? Color.faint : Color.ink))
                    }
                    .buttonStyle(.plain)
                    .disabled(missingRequired)

                    sourceFooter
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 14).padding(.top, 24)
            }
        }
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
    }

    // Auditable citation — which official body these steps come from, a tappable
    // link, and when it was last reviewed. Visible provenance builds trust for an
    // audience that's wary of bad/unofficial advice.
    @ViewBuilder
    private var sourceFooter: some View {
        if let s = guide.source {
            VStack(alignment: .leading, spacing: 6) {
                Rectangle().fill(Color.hair).frame(height: 1)
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal").font(.system(size: 11)).foregroundStyle(Color.ok)
                    if let url = URL(string: s.url) {
                        Link(s.label, destination: url)
                            .font(.eyebrow).tracking(0.3).foregroundStyle(Color.accent)
                    } else {
                        Text(s.label).font(.eyebrow).tracking(0.3).foregroundStyle(Color.faded)
                    }
                    Spacer()
                    Text(s.reviewedLabel).font(.eyebrow).tracking(0.3).foregroundStyle(Color.faint)
                }
            }
            .padding(.horizontal, 8).padding(.top, 8)
        }
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
            Text(LocalizedStringKey(note)).font(.body14).foregroundStyle(Color.ink).lineSpacing(2)
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
            Text(LocalizedStringKey(q.prompt)).font(.cardTitle).foregroundStyle(Color.ink)
            switch q.kind {
            case .choice(let options):
                VStack(spacing: 6) {
                    ForEach(options, id: \.self) { option in
                        let on = answers[q.id] == option
                        Button { answers[q.id] = option } label: {
                            HStack {
                                Text(LocalizedStringKey(option)).font(.body14).foregroundStyle(Color.ink)
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
                TextField(LocalizedStringKey(placeholder), text: Binding(
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
                        // Localize the "Select a state" placeholder (a String literal
                        // via `??` uses the NON-localizing Text initializer); a chosen
                        // state name passes through unchanged (not a catalog key).
                        Text(answers[q.id].map { LocalizedStringKey($0) } ?? "Select a state")
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
