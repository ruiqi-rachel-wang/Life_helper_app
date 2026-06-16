//  ReviewView.swift
//
//  Review & Action — the single confirm screen shared by BOTH scans and guides
//  (Week 6–7). It runs a caller-supplied async `load` (scan: OCR → AI extraction;
//  guide: build template → AI polish), shows the result(s) as an EDITABLE card,
//  and saves on "Add to inbox" (scheduling reminders). Source-agnostic: the photo
//  shows only for scans (when `image` is set).
//
//  Flow: loading → ready (editable) → Add to inbox. Special cases:
//  unreadable/low-confidence → retake/back; no-action (no steps, no due) → Done;
//  several items → a selectable list.
//

import SwiftUI
import SwiftData

struct ReviewView: View {
    // What produces the result(s): scan → OCR+extract, guide → build+polish.
    let load: () async throws -> [ExtractionResult]
    var image: UIImage? = nil                 // shown for scans only
    var source: ItemSource = .scanned         // tags saved items
    var loadingLabel = "Reading your document…"
    // How to leave this screen. Guides/scans pass a closure that pops their
    // whole stack back to the tab's root; falls back to a one-level dismiss.
    var onClose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @AppStorage("keepOriginalScans") private var keepOriginalScans = true

    @State private var phase: Phase = .loading
    @State private var draft = ExtractionResult.empty   // the editable result
    @State private var includeDue = false
    @State private var isEditing = false
    @State private var leadHours = 2                     // for timed reminders
    @State private var items: [ExtractionResult] = []    // when there are several
    @State private var selected: Set<Int> = []           // which multi-items to add
    @State private var detailStep: ChecklistStep?        // tapped step → detail sheet

    enum Phase: Equatable { case loading, ready, readyMulti, noText, failed(String) }

    var body: some View {
        ZStack(alignment: .top) {
            Color.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    photo.padding(.horizontal, 14).padding(.top, 8)
                    content.padding(.horizontal, 14).padding(.top, 14)
                    Spacer(minLength: 40)
                }
                .padding(.top, 48)
            }
        }
        .navigationBarHidden(true)
        .sheet(item: $detailStep) { tapped in
            if let idx = draft.detailedSteps.firstIndex(where: { $0.id == tapped.id }) {
                StepDetailView(step: $draft.detailedSteps[idx])   // edits ride into the saved item
            }
        }
        .task { await run() }
    }

    // MARK: pipeline

    private func run() async {
        do {
            let results = try await load()
            if results.isEmpty {
                phase = .noText
            } else if results.count == 1 {
                draft = results[0]
                includeDue = draft.dueDate != nil
                leadHours = ActionItem.defaultLeadHours(documentType: draft.documentType ?? "", category: draft.category)
                // Keep detailed-step text in sync with the (polished) milestones
                // so the Step Detail sheet shows/edits the same wording.
                if draft.detailedSteps.count == draft.steps.count {
                    for i in draft.steps.indices { draft.detailedSteps[i].text = draft.steps[i] }
                }
                phase = .ready
            } else {
                items = results
                // Default-select only items that are safe to add — skip no-action
                // (nothing to do) and unreadable/low-confidence ones, so neither
                // can silently become a task. The row flags say why; the user can
                // still turn one on.
                selected = Set(results.indices.filter {
                    !Self.isNoAction(results[$0]) && !Self.isUnreadable(results[$0])
                })
                phase = .readyMulti
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // Leave the screen — pop the whole stack to root if the caller gave us a way,
    // otherwise just dismiss one level.
    private func finish() {
        if let onClose { onClose() } else { dismiss() }
    }

    // MARK: header

    private var header: some View {
        HStack {
            Button { finish() } label: {
                Image(systemName: "xmark").font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.faint)
            }
            .accessibilityLabel("Close")
            Spacer()
            Text("REVIEW").font(.system(size: 13, weight: .semibold, design: .monospaced))
                .tracking(1.6).foregroundStyle(Color.faded)
            Spacer()
            if phase == .ready && !isUnreadable {
                Button { isEditing.toggle() } label: {
                    Text(isEditing ? "Done" : "Edit")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.accent)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 30, height: 1)
            }
        }
        .padding(.horizontal, 22)
    }

    @ViewBuilder
    private var photo: some View {
        if let image {
            Image(uiImage: image)
                .resizable().scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 160)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
        }
    }

    // MARK: content by phase

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:  loadingCard(loadingLabel)
        case .readyMulti: multiList
        case .noText:   messageCard("Couldn't read any text. Try a clearer, well-lit photo.", retake: true)
        case .failed(let m): messageCard("Couldn't analyze this document.\n\(m)", retake: true)
        case .ready:
            if isUnreadable {
                messageCard("We couldn't read this clearly, so the details might be wrong. Try retaking the photo in better light.", retake: true)
            } else {
                resultCard
            }
        }
    }

    private func loadingCard(_ label: String) -> some View {
        card {
            HStack(spacing: 8) { ProgressView(); Text(label).font(.body14).foregroundStyle(Color.faded) }
        }
    }

    private func messageCard(_ text: String, retake: Bool) -> some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Text(text).font(.body14).foregroundStyle(Color.bad)
                if retake {
                    Button { finish() } label: {
                        Text(image != nil ? "Retake photo" : "Go back").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.paper).frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.ink))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: result (editable)

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            card { documentHead }
            // Details (claim/policy/confirmation #) sit ABOVE steps — they're
            // what the user reaches for when a website/clerk asks.
            if !combinedIDs.isEmpty || siteURLToShow != nil || isEditing { card { detailsSection } }
            if !draft.steps.isEmpty || isEditing { card { stepsSection } }
            if !draft.notes.isEmpty || isEditing { card { notesSection } }
            footer
        }
    }

    private var documentHead: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text([draft.documentType, draft.sender].compactMap { $0 }.joined(separator: " · ").uppercased())
                .font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)

            if isEditing {
                TextField("Title", text: bind(\.title), axis: .vertical)
                    .font(.serifModal).foregroundStyle(Color.ink)
                TextField("Summary", text: bind(\.summary), axis: .vertical)
                    .font(.body14).foregroundStyle(Color.faded)
            } else {
                if let title = draft.title { Text(title).font(.serifModal).foregroundStyle(Color.ink).lineSpacing(2) }
                if let summary = draft.summary { Text(summary).font(.body14).foregroundStyle(Color.faded).lineSpacing(2) }
            }

            // Show a chip only when there's a value (or while editing, so the
            // user can add one). No empty "—" boxes.
            if draft.amount != nil || draft.dueDate != nil || isEditing {
                HStack(spacing: 8) {
                    if draft.amount != nil || isEditing { amountChip }
                    if draft.dueDate != nil || isEditing { dueChip }
                }
                .padding(.top, 2)
            }

            // When the event has a specific time, let the user pick how far ahead
            // to be reminded (smart default by type).
            if draft.dueHasTime && (draft.dueDate != nil || isEditing) {
                HStack(spacing: 6) {
                    Text("REMIND").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                    Menu {
                        ForEach(ActionItem.leadOptions, id: \.self) { h in
                            Button(ActionItem.leadLabel(h)) { leadHours = h }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text("\(ActionItem.leadLabel(leadHours)) before")
                            Image(systemName: "chevron.down").font(.system(size: 9))
                        }
                        .font(.subline).foregroundStyle(Color.accent)
                    }
                }
                .padding(.top, 2)
            }

            // Fields the AI was unsure about beyond amount/due (which already get
            // the chip underline) — e.g. sender, title, account #, category.
            let otherFlags = draft.lowConfidenceFields.subtracting(["amount", "dueDate"])
            if !otherFlags.isEmpty {
                Text("Double-check: \(otherFlags.sorted().joined(separator: ", "))")
                    .font(.subline).foregroundStyle(Color.accent)
                    .padding(.top, 2)
            }
        }
    }

    // Amount + Due chips, editable in place.
    private var amountChip: some View {
        chipBox("AMOUNT", flagged: draft.lowConfidenceFields.contains("amount")) {
            if isEditing {
                HStack(spacing: 2) {
                    Text("$").font(.subline).foregroundStyle(Color.faded)
                    TextField("0.00", text: amountText).keyboardType(.decimalPad)
                        .font(.serifStat).foregroundStyle(Color.ink)
                }
            } else if let amount = draft.amount {
                Text(amount.formatted(.currency(code: draft.currency ?? "USD")))
                    .font(.serifStat).foregroundStyle(Color.ink)
                    .minimumScaleFactor(0.6).lineLimit(1)
            }
        }
    }

    private var dueChip: some View {
        chipBox("DUE", flagged: draft.lowConfidenceFields.contains("dueDate")) {
            if isEditing {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Has due date", isOn: $includeDue.animation()).labelsHidden().tint(Color.ink)
                    if includeDue {
                        DatePicker("", selection: dueDateBinding,
                                   displayedComponents: draft.dueHasTime ? [.date, .hourAndMinute] : [.date])
                            .labelsHidden().datePickerStyle(.compact)
                        Toggle("Specific time", isOn: bindBool(\.dueHasTime)).font(.subline).tint(Color.ink)
                    }
                }
            } else if let due = draft.dueDate {
                Text(dueDisplay(due, hasTime: draft.dueHasTime))
                    .font(.serifStat).foregroundStyle(Color.warn)
                    .minimumScaleFactor(0.5).lineLimit(2)
            }
        }
    }

    // Detail for milestone i (guides only), if it has any.
    private func stepDetail(_ i: Int) -> StepDetail? {
        guard draft.detailedSteps.indices.contains(i) else { return nil }
        let d = draft.detailedSteps[i].detail
        return (d?.isEmpty == false) ? d : nil
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ACTION STEPS").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
            ForEach(draft.steps.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 10) {
                    Text("•").font(.body14).foregroundStyle(Color.faded)
                        .frame(width: 10, alignment: .leading).padding(.top, isEditing ? 8 : 0)
                    if isEditing {
                        TextField("Step", text: $draft.steps[i], axis: .vertical).font(.body14).foregroundStyle(Color.ink)
                        Button { removeStep(i) } label: {
                            Image(systemName: "minus.circle.fill").font(.system(size: 18)).foregroundStyle(Color.faint)
                        }.buttonStyle(.plain)
                    } else if stepDetail(i) != nil {
                        // Same tap-to-detail as the Detail page, so the user can
                        // see/edit the instructions before adding.
                        Button { detailStep = draft.detailedSteps[i] } label: {
                            HStack(alignment: .top, spacing: 6) {
                                Text(linked(draft.steps[i])).font(.body14).foregroundStyle(Color.ink).tint(Color.accent)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.faint)
                            }
                        }.buttonStyle(.plain)
                    } else {
                        Text(linked(draft.steps[i])).font(.body14).foregroundStyle(Color.ink).tint(Color.accent)
                    }
                }
            }
            if isEditing {
                Button { addStep() } label: {
                    Label("Add a step", systemImage: "plus.circle").font(.body14).foregroundStyle(Color.accent)
                }.buttonStyle(.plain).padding(.top, 4)
            }
        }
    }

    // Step edits must touch BOTH arrays: `steps` (text) and `detailedSteps` (which
    // carries StepDetail). If they fall out of sync, mapSteps falls back to the
    // ORIGINAL detailedSteps and deleted/added steps reappear. detailedSteps is
    // empty for scans, so we only mirror when it's present (guides).
    private func removeStep(_ i: Int) {
        draft.steps.remove(at: i)
        if draft.detailedSteps.indices.contains(i) { draft.detailedSteps.remove(at: i) }
    }
    private func addStep() {
        draft.steps.append("")
        if !draft.detailedSteps.isEmpty { draft.detailedSteps.append(ChecklistStep(text: "")) }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTES").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
            ForEach(draft.notes.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 8) {
                    Text("•").font(.body14).foregroundStyle(Color.faded)
                    if isEditing {
                        TextField("Note", text: $draft.notes[i], axis: .vertical).font(.body14).foregroundStyle(Color.faded)
                        Button { draft.notes.remove(at: i) } label: {
                            Image(systemName: "minus.circle.fill").font(.system(size: 18)).foregroundStyle(Color.faint)
                        }.buttonStyle(.plain)
                    } else {
                        Text(linked(draft.notes[i])).font(.body14).foregroundStyle(Color.faded).tint(Color.accent)
                    }
                }
            }
            if isEditing {
                Button { draft.notes.append("") } label: {
                    Label("Add a note", systemImage: "plus.circle").font(.body14).foregroundStyle(Color.accent)
                }.buttonStyle(.plain).padding(.top, 4)
            }
        }
    }

    // DETAILS — saved IDs / provider / claim #, etc. Values editable inline (tap to
    // fill); labels and add/remove appear in edit mode. The scanned primary
    // reference number (if any) shows read-only above.
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DETAILS").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
            if let acct = draft.accountNumber, !acct.isEmpty,
               !draft.otherIDs.contains(where: { $0.value == acct }) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("REFERENCE").font(.eyebrow).tracking(0.5).foregroundStyle(Color.faded)
                    Text(acct).font(.body14).foregroundStyle(Color.ink).textSelection(.enabled)
                }
            }
            ForEach(draft.otherIDs.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 5) {
                    if isEditing {
                        HStack(spacing: 8) {
                            TextField("Label", text: $draft.otherIDs[i].label)
                                .font(.eyebrow).tracking(0.5).foregroundStyle(Color.faded)
                            Button { draft.otherIDs.remove(at: i) } label: {
                                Image(systemName: "minus.circle.fill").font(.system(size: 18)).foregroundStyle(Color.faint)
                            }.buttonStyle(.plain)
                        }
                    } else {
                        Text(draft.otherIDs[i].label.uppercased())
                            .font(.eyebrow).tracking(0.5).foregroundStyle(Color.faded)
                    }
                    TextField("Tap to fill in", text: $draft.otherIDs[i].value)
                        .font(.body14).foregroundStyle(Color.ink)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.bg))
                }
            }
            if isEditing {
                Button { draft.otherIDs.append(DocID(label: "", value: "")) } label: {
                    Label("Add a detail", systemImage: "plus.circle").font(.body14).foregroundStyle(Color.accent)
                }.buttonStyle(.plain).padding(.top, 2)
            }
            if let site = siteURLToShow {
                Link(destination: site) {
                    Text("Website: \(site.host() ?? site.absoluteString)")
                        .font(.subline).foregroundStyle(Color.accent)
                }
            }
        }
    }

    // The website, but only if it isn't already linkified inside the steps/notes
    // (avoids the duplicate "link below the date" we removed earlier).
    private var siteURLToShow: URL? {
        guard let url = draft.siteURL else { return nil }
        let hay = (draft.steps + draft.notes).joined(separator: " ").lowercased()
        let host = (url.host() ?? url.absoluteString).lowercased()
        return hay.contains(host) ? nil : url
    }

    // MARK: footer — Add (action items) or Done (no-action)

    @ViewBuilder
    private var footer: some View {
        if isNoAction {
            VStack(spacing: 8) {
                Text("Nothing to do — this is just for your information.")
                    .font(.subline).foregroundStyle(Color.faded)
                Button { finish() } label: {
                    primaryLabel("Done")
                }.buttonStyle(.plain)
            }
        } else {
            Button { addToInbox() } label: { primaryLabel("Add to inbox") }.buttonStyle(.plain)
        }
    }

    private func primaryLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.paper)
            .frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.ink))
    }

    private func addToInbox() {
        if !includeDue { draft.dueDate = nil }
        // Drop blank steps, keeping each step's detail aligned by index so nothing
        // the user removed comes back (and added/edited steps stick).
        let keepDetail = !draft.detailedSteps.isEmpty && draft.detailedSteps.count == draft.steps.count
        var steps: [String] = []
        var detailed: [ChecklistStep] = []
        for (i, raw) in draft.steps.enumerated() {
            let text = raw.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            steps.append(text)
            if keepDetail {
                var ds = draft.detailedSteps[i]; ds.text = text
                detailed.append(ds)
            }
        }
        draft.steps = steps
        draft.detailedSteps = detailed   // empty for scans → mapSteps uses steps
        draft.notes = draft.notes.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let item = ActionItem(from: draft, imageData: scanImageData, source: source)
        item.reminderLeadHours = leadHours
        context.insert(item)
        Metrics.record(.confirmed, source: source.rawValue)
        ReminderScheduler.shared.reschedule(for: item)
        router.goToInbox()
        finish()
    }

    // MARK: multi-item — "this scan has N things"

    private var multiList: some View {
        VStack(alignment: .leading, spacing: 14) {
            card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(items.count) THINGS FOUND")
                        .font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                    Text("This scan has several items. Pick which to add — you can edit each one afterward.")
                        .font(.body14).foregroundStyle(Color.faded)
                }
            }
            ForEach(items.indices, id: \.self) { i in
                card { multiItemRow(i) }
            }
            Button { addSelected() } label: {
                primaryLabel(selected.isEmpty ? "Select items to add" : "Add \(selected.count) to inbox")
            }
            .buttonStyle(.plain).disabled(selected.isEmpty)
        }
    }

    private func multiItemRow(_ i: Int) -> some View {
        let it = items[i]
        let on = selected.contains(i)
        return Button {
            if on { selected.remove(i) } else { selected.insert(i) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                multiCheckbox(on)
                VStack(alignment: .leading, spacing: 4) {
                    let tag = [it.documentType, it.sender].compactMap { $0 }.joined(separator: " · ").uppercased()
                    if !tag.isEmpty {
                        Text(tag).font(.eyebrow).tracking(0.8).foregroundStyle(Color.faded)
                    }
                    Text(it.title ?? "Untitled").font(.cardTitle).foregroundStyle(Color.ink)
                        .multilineTextAlignment(.leading)
                    let bits = [
                        it.amount.map { $0.formatted(.currency(code: it.currency ?? "USD")) },
                        it.dueDate.map { dueDisplay($0, hasTime: it.dueHasTime) },
                        it.steps.isEmpty ? nil : "\(it.steps.count) steps",
                    ].compactMap { $0 }
                    if !bits.isEmpty {
                        Text(bits.joined(separator: " · ")).font(.subline).foregroundStyle(Color.faded)
                    }
                    // Flag items that need a second look before they become tasks.
                    if Self.isUnreadable(it) {
                        Text("⚠︎ couldn't read clearly — review before adding")
                            .font(.subline).foregroundStyle(Color.bad)
                    } else if Self.isNoAction(it) {
                        Text("Nothing to do — off by default")
                            .font(.subline).foregroundStyle(Color.faded)
                    } else if !it.lowConfidenceFields.isEmpty {
                        Text("Double-check: \(it.lowConfidenceFields.sorted().joined(separator: ", "))")
                            .font(.subline).foregroundStyle(Color.accent)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func multiCheckbox(_ on: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .stroke(on ? Color.ink : Color.faint, lineWidth: 1.5)
            .background(RoundedRectangle(cornerRadius: 5).fill(on ? Color.ink : Color.clear))
            .frame(width: 20, height: 20)
            .overlay {
                if on {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.paper)
                }
            }
    }

    // The scanned photo to store on the item — nil when the user turned off
    // "Keep original scans" in Profile (saves storage / keeps it off-device).
    private var scanImageData: Data? {
        keepOriginalScans ? image?.jpegData(compressionQuality: 0.7) : nil
    }

    private func addSelected() {
        let img = scanImageData
        for i in items.indices where selected.contains(i) {
            let item = ActionItem(from: items[i], imageData: img, source: source)
            context.insert(item)
            Metrics.record(.confirmed, source: source.rawValue)
            ReminderScheduler.shared.reschedule(for: item)
        }
        router.goToInbox()
        finish()
    }

    // MARK: derived

    static func isUnreadable(_ r: ExtractionResult) -> Bool {
        r.confidence < 0.2 || r.documentType?.lowercased() == "unknown"
    }
    static func isNoAction(_ r: ExtractionResult) -> Bool {
        r.steps.isEmpty && r.dueDate == nil
    }
    // Only a scan (with a photo) can be "unreadable" — guides are deterministic
    // and always produce a valid checklist, so they never hit the retake state.
    private var isUnreadable: Bool { image != nil && Self.isUnreadable(draft) }
    private var isNoAction: Bool { Self.isNoAction(draft) }
    // accountNumber (primary) + otherIDs, deduped by value.
    private var combinedIDs: [DocID] {
        var list = draft.otherIDs
        if let acct = draft.accountNumber, !acct.isEmpty, !list.contains(where: { $0.value == acct }) {
            list.insert(DocID(label: "Reference", value: acct), at: 0)
        }
        return list
    }

    // MARK: bindings into the draft struct

    private func bind(_ key: WritableKeyPath<ExtractionResult, String?>) -> Binding<String> {
        Binding(get: { draft[keyPath: key] ?? "" },
                set: { draft[keyPath: key] = $0.isEmpty ? nil : $0 })
    }
    private func bindBool(_ key: WritableKeyPath<ExtractionResult, Bool>) -> Binding<Bool> {
        Binding(get: { draft[keyPath: key] }, set: { draft[keyPath: key] = $0 })
    }
    private var amountText: Binding<String> {
        Binding(get: { draft.amount.map { ($0 as NSDecimalNumber).stringValue } ?? "" },
                set: { draft.amount = Decimal(string: $0) })
    }
    private var dueDateBinding: Binding<Date> {
        Binding(get: { draft.dueDate ?? .now }, set: { draft.dueDate = $0 })
    }

    // MARK: small view helpers

    private func card<C: View>(@ViewBuilder _ inner: () -> C) -> some View {
        inner()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }

    private func chipBox<C: View>(_ label: String, flagged: Bool, @ViewBuilder _ value: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
            value()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.bg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(flagged ? Color.accent : Color.clear, lineWidth: 1))
    }

    // URLs + phone numbers → tappable links.
    private func linked(_ string: String) -> AttributedString {
        var attr = AttributedString(string)
        let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return attr }
        let ns = string as NSString
        for m in detector.matches(in: string, range: NSRange(location: 0, length: ns.length)) {
            guard let sr = Range(m.range, in: string),
                  let lo = AttributedString.Index(sr.lowerBound, within: attr),
                  let hi = AttributedString.Index(sr.upperBound, within: attr) else { continue }
            let url: URL? = (m.resultType == .phoneNumber)
                ? m.phoneNumber.flatMap { URL(string: "tel:" + $0.filter { $0.isNumber || $0 == "+" }) }
                : m.url
            if let url { attr[lo..<hi].link = url; attr[lo..<hi].underlineStyle = .single }
        }
        return attr
    }
}
