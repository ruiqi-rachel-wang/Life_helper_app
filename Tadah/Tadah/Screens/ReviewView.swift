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
    var images: [UIImage] = []                 // every scanned page (empty for guides)
    var pageWarning: String? = nil             // e.g. "some pages couldn't be opened"
    var source: ItemSource = .scanned         // tags saved items
    var loadingLabel = "Reading your document…"

    // Derived from the pages. Preview shows the first; the badge shows the count.
    private var image: UIImage? { images.first }
    private var pageCount: Int { images.count }
    // The whole document as one image (all pages stacked) for the full-screen
    // viewer + translation — vs `image`, which is only the page-one preview.
    private var viewerImage: UIImage? {
        guard !images.isEmpty else { return nil }
        return images.count == 1 ? images[0] : UIImage.stackedVertically(images)
    }
    // How to leave this screen. Guides/scans pass a closure that pops their
    // whole stack back to the tab's root; falls back to a one-level dismiss.
    var onClose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(TourGuide.self) private var tourGuide
    @Environment(PlusStore.self) private var plus
    @Environment(ProfileStore.self) private var profiles

    @State private var phase: Phase = .loading
    @State private var draft = ExtractionResult.empty   // the editable result
    @State private var includeDue = false
    @State private var isEditing = false
    @State private var leadHours = 2                     // for timed reminders
    @State private var items: [ExtractionResult] = []    // when there are several
    @State private var selected: Set<Int> = []           // which multi-items to add
    @State private var detailStep: ChecklistStep?        // tapped step → detail sheet
    @State private var showFullPhoto = false             // tapped photo → enlarge/translate
    @State private var limitMessage: String?             // task-list full
    // Who the scanned/guided item is for; defaults to this phone's person.
    @State private var assignee: UUID?
    @State private var assigneeSeeded = false

    // Focus for rows appended by the "Add a …" buttons — see DetailView.Field.
    private enum Field: Hashable { case step(Int), note(Int), detailLabel(Int) }
    @FocusState private var focused: Field?

    @AppStorage(ExplainLanguage.storageKey) private var explainLanguageRaw = ""
    private var explainLanguage: ExplainLanguage { ExplainLanguage.resolve(stored: explainLanguageRaw) }

    enum Phase: Equatable { case loading, ready, readyMulti, noText, failed(String) }

    var body: some View {
        ZStack(alignment: .top) {
            Color.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    photo.padding(.horizontal, 14).padding(.top, 8)
                    if let pageWarning {
                        Label(pageWarning, systemImage: "exclamationmark.triangle")
                            .font(.subline).foregroundStyle(Color.warn)
                            .padding(.horizontal, 18).padding(.top, 8)
                    }
                    content.padding(.horizontal, 14).padding(.top, 14)
                    Spacer(minLength: 40)
                }
                .padding(.top, 48)
            }
            .dismissKeyboardOnTap()   // tap anywhere outside a field to close the keyboard
        }
        .navigationBarHidden(true)
        .sheet(item: $detailStep) { tapped in
            if let idx = draft.detailedSteps.firstIndex(where: { $0.id == tapped.id }) {
                // A plain step (no detail yet) opens straight into edit mode — same
                // rule as the saved-item Detail page.
                StepDetailView(step: $draft.detailedSteps[idx], startInEditMode: !tapped.hasDetail)
            }
        }
        .task { await run() }
        // Reaching Review IS the tour's next milestone, however the user got
        // here (scan, upload, or a guide from the Guides tab) — catch up so
        // the "Add to inbox" card shows once the result renders.
        .onAppear {
            tourGuide.catchUp(to: .reviewAdd)
            if !assigneeSeeded { assignee = profiles.activeProfileID; assigneeSeeded = true }
        }
        .alert("List full", isPresented: Binding(
            get: { limitMessage != nil }, set: { if !$0 { limitMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(limitMessage ?? "") }
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
        // Leaving Review during the tour WITHOUT adding an item (no-action "Done",
        // close, or a failed/unreadable retake): end the tour so it can't get stuck
        // on .reviewAdd — a step no other screen shows — and won't restart next
        // launch. The add paths advance to .inboxRow *before* calling finish(), so
        // they're already past .reviewAdd here and are left untouched.
        if tourGuide.step == .reviewAdd { tourGuide.finish() }
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
            Button { showFullPhoto = true } label: {
                Image(uiImage: image)
                    .resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
                    // Show how many pages were combined when it's more than one.
                    .overlay(alignment: .bottomTrailing) {
                        if pageCount > 1 {
                            Label("\(pageCount) pages", systemImage: "doc.on.doc")
                                .font(.eyebrow).tracking(0.4).foregroundStyle(Color.paper)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(Color.ink.opacity(0.75)))
                                .padding(8)
                        }
                    }
                    // Hint that tapping enlarges — and translates for non-English readers.
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: explainLanguage == .english ? "arrow.up.left.and.arrow.down.right" : "globe")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                            .padding(5).background(Circle().fill(.black.opacity(0.45))).padding(8)
                    }
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showFullPhoto) {
                // The FULL document (all pages stacked), so translating from Review
                // covers every page — not just the page-one preview.
                FullPhotoViewer(photo: viewerImage ?? image, language: explainLanguage)
            }
        }
    }

    // MARK: content by phase

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:  loadingCard(loadingLabel)
        case .readyMulti: multiList
        case .noText:   messageCard(String(localized: "Couldn't read any text. Try a clearer, well-lit photo."), retake: true)
        case .failed(let m): messageCard(String(localized: "Couldn't analyze this document.") + "\n" + m, retake: true)
        case .ready:
            if isUnreadable {
                messageCard(String(localized: "We couldn't read this clearly, so the details might be wrong. Try retaking the photo in better light."), retake: true)
            } else {
                resultCard
            }
        }
    }

    // `label` arrives as a String (loadingLabel), so wrap in LocalizedStringKey
    // to translate it rather than show it verbatim.
    private func loadingCard(_ label: String) -> some View {
        card {
            HStack(spacing: 8) { ProgressView(); Text(LocalizedStringKey(label)).font(.body14).foregroundStyle(Color.faded) }
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
            // Who it's for — right under the document, before the details, since
            // filing a parent's letter under them is the whole point of scanning
            // it on their behalf. Renders nothing when there's no family.
            if profiles.hasFamily { card { AssigneeRow(profileID: $assignee) } }
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
                TextField("Title", text: bind(\.title), prompt: fieldPrompt("Title"), axis: .vertical)
                    .font(.serifModal).foregroundStyle(Color.ink)
                TextField("Summary", text: bind(\.summary), prompt: fieldPrompt("Summary"), axis: .vertical)
                    .font(.body14).foregroundStyle(Color.ink)
            } else {
                if let title = draft.title { Text(title).font(.serifModal).foregroundStyle(Color.ink).lineSpacing(2) }
                if let summary = draft.summary { Text(summary).font(.body14).foregroundStyle(Color.faded).lineSpacing(2) }
            }

            // Show a chip only when there's a value (or while editing, so the
            // user can add one). No empty "—" boxes.
            if draft.amount != nil || draft.dueDate != nil || isEditing {
                // Stacked while editing so the date picker gets full width.
                if isEditing {
                    VStack(spacing: 8) { amountChip; dueChip }.padding(.top, 2)
                } else {
                    HStack(spacing: 8) {
                        if draft.amount != nil { amountChip }
                        if draft.dueDate != nil { dueChip }
                    }
                    .padding(.top, 2)
                }
            }

            // Recurrence — visible/editable right here so a scanned bill's monthly
            // cadence can be confirmed or changed before saving.
            if isEditing || draft.repeats != nil { repeatsRow }

            // Reminders are their own section, independent of the due date: in
            // Edit you can always add absolute-date reminders (with or without a
            // due date); in read mode it shows only when there are any. Edits
            // persist on save (see ActionItem.init(from:)).
            let hasReminders = draft.remindersCustomized ? !draft.reminders.isEmpty : draft.dueDate != nil
            if isEditing || hasReminders {
                card {
                    RemindersEditor(reminders: $draft.reminders,
                                    customized: $draft.remindersCustomized,
                                    defaults: ActionItem.defaultReminders(dueDate: draft.dueDate,
                                                                          dueHasTime: draft.dueHasTime,
                                                                          leadHours: leadHours,
                                                                          defaultMinutes: AppSettings.defaultReminderMinutes),
                                    dueDate: draft.dueDate,
                                    isEditing: isEditing)
                }
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

    // REPEATS — read shows the cadence; edit offers the presets. Saved onto the
    // item via ActionItem(from: draft).
    private var repeatsRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.faded)
            Text("REPEATS").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
            Spacer()
            if isEditing {
                Menu {
                    Button("Doesn't repeat") { draft.repeats = nil }
                    ForEach(Recurrence.presets, id: \.self) { p in
                        Button(p.label) { draft.repeats = p }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(draft.repeats?.label ?? "Doesn't repeat")
                            .font(.subline).foregroundStyle(Color.accent)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.accent)
                    }
                }
            } else if let r = draft.repeats {
                Text(r.label).font(.subline).foregroundStyle(Color.ink)
            }
        }
        .padding(.top, 2)
    }

    // Amount + Due chips, editable in place.
    private var amountChip: some View {
        chipBox("AMOUNT", flagged: draft.lowConfidenceFields.contains("amount")) {
            if isEditing {
                AmountInput(amount: $draft.amount)
            } else if let amount = draft.amount {
                Text(amount.formatted(.currency(code: draft.currency ?? "USD")))
                    .font(.serifStat).foregroundStyle(Color.ink)
                    .minimumScaleFactor(0.6).lineLimit(1)
            }
        }
    }

    private var dueChip: some View {
        chipBox("DATE", flagged: draft.lowConfidenceFields.contains("dueDate")) {
            if isEditing {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Has due date", isOn: $includeDue.animation()).labelsHidden().tint(Color.ink)
                        // Seed the draft the moment the toggle turns on — otherwise the
                        // picker SHOWS today but the draft still holds nil, and the item
                        // saves with no date (and no reminders) unless the picker is touched.
                        .onChange(of: includeDue) { _, on in
                            if on {
                                if draft.dueDate == nil { draft.dueDate = Calendar.current.startOfDay(for: .now) }
                            } else {
                                draft.dueDate = nil   // turning it off removes the date (and its chip)
                            }
                        }
                    if includeDue {
                        DatePicker("", selection: dueDateBinding,
                                   displayedComponents: draft.dueHasTime ? [.date, .hourAndMinute] : [.date])
                            .labelsHidden().datePickerStyle(.compact)
                        Toggle("Specific time", isOn: bindBool(\.dueHasTime)).font(.subline).tint(Color.ink)
                            // A plain date carries midnight; turning "time" on would make a
                            // 12:00 AM event that's instantly overdue. Start at 9am instead.
                            .onChange(of: draft.dueHasTime) { _, on in
                                if on, let due = draft.dueDate,
                                   Calendar.current.dateComponents([.hour, .minute], from: due) == DateComponents(hour: 0, minute: 0) {
                                    draft.dueDate = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: due)
                                }
                            }
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
                        TextField("Step", text: $draft.steps[i], prompt: fieldPrompt("Step"), axis: .vertical)
                            .font(.body14).foregroundStyle(Color.ink)
                            .focused($focused, equals: .step(i))
                        // Add/edit this step's mini-checklist, explanation, etc. — same
                        // edit-mode pencil as the saved-item Detail page.
                        Button { openStepDetail(i) } label: {
                            Image(systemName: "pencil.circle").font(.system(size: 18)).foregroundStyle(Color.accent)
                        }.buttonStyle(.plain)
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
                        .addRowTapTarget()
                }.buttonStyle(.plain)
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
        focus(.step(draft.steps.count - 1))
    }

    // One runloop hop — the appended row doesn't exist yet when this runs, and
    // @FocusState silently drops a value with no matching field.
    private func focus(_ field: Field) {
        Task { @MainActor in focused = field }
    }

    // A scan's `detailedSteps` starts empty (only guides pre-author detail) — back
    // it with one entry per step on first use, so any step can open a detail sheet
    // to add a mini-checklist/explanation, same as the saved-item Detail page.
    private func openStepDetail(_ i: Int) {
        if draft.detailedSteps.count != draft.steps.count {
            draft.detailedSteps = draft.steps.map { ChecklistStep(text: $0) }
        }
        detailStep = draft.detailedSteps[i]
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTES").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
            ForEach(draft.notes.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 8) {
                    Text("•").font(.body14).foregroundStyle(Color.faded)
                    if isEditing {
                        TextField("Note", text: $draft.notes[i], prompt: fieldPrompt("Note"), axis: .vertical)
                            .font(.body14).foregroundStyle(Color.ink)
                            .focused($focused, equals: .note(i))
                        Button { draft.notes.remove(at: i) } label: {
                            Image(systemName: "minus.circle.fill").font(.system(size: 18)).foregroundStyle(Color.faint)
                        }.buttonStyle(.plain)
                    } else {
                        Text(linked(draft.notes[i])).font(.body14).foregroundStyle(Color.faded).tint(Color.accent)
                    }
                }
            }
            if isEditing {
                Button {
                    draft.notes.append("")
                    focus(.note(draft.notes.count - 1))
                } label: {
                    Label("Add a note", systemImage: "plus.circle").font(.body14).foregroundStyle(Color.accent)
                        .addRowTapTarget()
                }.buttonStyle(.plain)
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
                            TextField("Label", text: $draft.otherIDs[i].label, prompt: fieldPrompt("Label"))
                                .font(.subline).foregroundStyle(Color.ink)
                                .focused($focused, equals: .detailLabel(i))
                            Button { draft.otherIDs.remove(at: i) } label: {
                                Image(systemName: "minus.circle.fill").font(.system(size: 18)).foregroundStyle(Color.faint)
                            }.buttonStyle(.plain)
                        }
                    } else {
                        Text(draft.otherIDs[i].label.uppercased())
                            .font(.subline).tracking(0.5).foregroundStyle(Color.faded)
                    }
                    TextField("Value", text: $draft.otherIDs[i].value, prompt: fieldPrompt("Tap to fill in"))
                        .font(.body14).foregroundStyle(Color.ink)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.bg))
                }
            }
            if isEditing {
                Button {
                    draft.otherIDs.append(DocID(label: "", value: ""))
                    focus(.detailLabel(draft.otherIDs.count - 1))
                } label: {
                    Label("Add a detail", systemImage: "plus.circle").font(.body14).foregroundStyle(Color.accent)
                        .addRowTapTarget()
                }.buttonStyle(.plain)
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
        VStack(spacing: 10) {
            if isNoAction {
                Text("Nothing to do — this is just for your information.")
                    .font(.subline).foregroundStyle(Color.faded)
                Button { finish() } label: { primaryLabel("Done") }.buttonStyle(.plain)
            } else {
                // Tour card sits directly above the real button it introduces.
                // No dimming here — the point of Review is READING what Tadah
                // found (and editing it), so the content stays fully usable.
                if tourGuide.step == .reviewAdd {
                    TourCard(title: "Here's what Tadah found",
                             message: "Check the steps and due date, then tap **Add to inbox** to save it.",
                             stepIndex: TourGuide.Step.reviewAdd.rawValue,
                             onNext: { tourGuide.advance(from: .reviewAdd) },
                             onSkip: { tourGuide.finish() })
                }
                Button { addToInbox() } label: { primaryLabel("Add to inbox") }.buttonStyle(.plain)
            }
            // Always-visible AI-accuracy disclaimer (legal/risk control): the result
            // is AI-generated and can be wrong — tell the user to verify.
            Text("AI-generated — double-check important details against the original and the official source.")
                .font(.subline).foregroundStyle(Color.faint)
                .multilineTextAlignment(.center).lineSpacing(2)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
        }
    }

    private func primaryLabel(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.paper)
            .frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.ink))
    }

    private func addToInbox() {
        if let reason = TaskLimit.blockedReason(context, plus: plus.isPlus,
                                                profileID: assignee) {
            limitMessage = reason; return
        }
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
        if draft.remindersCustomized {        // user edited the list in Review → carry it over
            item.reminders = draft.reminders
            item.remindersCustomized = true
        }
        item.profileID = assignee                    // who it's for
        context.insert(item)
        Metrics.record(.confirmed, itemID: item.id, source: source.rawValue)
        ReminderScheduler.shared.reschedule(for: item)
        SyncCoordinator.shared.noteLocalChange()
        tourGuide.advance(from: .reviewAdd)
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

    // The scanned photo to store on the item. Stacks ALL pages into one tall
    // image so a multi-page document keeps its back pages too (the old code kept
    // only the first). Single-page documents store as-is. Saved by default so
    // the user can always check the original on the Detail page — the My Settings
    // toggle (AppSettings.savePhoto) opts out. Photos are not uploaded today (see
    // TaskDTO); backing them up to the account is a planned OPTION, not a promise
    // that they stay local.
    private var scanImageData: Data? {
        guard AppSettings.savePhoto, !images.isEmpty else { return nil }
        let stored = images.count == 1 ? images[0] : UIImage.stackedVertically(images)
        return stored?.jpegData(compressionQuality: 0.7)
    }

    private func addSelected() {
        let chosen = items.indices.filter { selected.contains($0) }
        let room = TaskLimit.remaining(context, plus: plus.isPlus, profileID: assignee)
        guard room > 0 else {
            limitMessage = TaskLimit.blockedReason(context, plus: plus.isPlus, profileID: assignee)
            return
        }
        // Add what fits, oldest-selected first; tell the user if some didn't fit.
        let toAdd = Array(chosen.prefix(room))
        let img = scanImageData
        for i in toAdd {
            let item = ActionItem(from: items[i], imageData: img, source: source)
            item.profileID = assignee
            context.insert(item)
            Metrics.record(.confirmed, itemID: item.id, source: source.rawValue)
            ReminderScheduler.shared.reschedule(for: item)
        }
        SyncCoordinator.shared.noteLocalChange()
        if toAdd.count < chosen.count {
            limitMessage = String(localized: "Your list is full at \(TaskLimit.cap(plus: plus.isPlus)) items, so only \(toAdd.count) of \(chosen.count) were added. Delete some to add the rest.")
            selected = Set(chosen.dropFirst(room))   // leave the ones that didn't fit checked
            return
        }
        tourGuide.advance(from: .reviewAdd)   // → .inboxRow, like the single-item path
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
            let label = draft.accountLabel?.trimmingCharacters(in: .whitespaces)
            list.insert(DocID(label: (label?.isEmpty == false ? label! : "Reference"), value: acct), at: 0)
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
    private var dueDateBinding: Binding<Date> {
        Binding(get: { draft.dueDate ?? .now },
                set: { newValue in
                    // Same rule as Detail: reminders the user already customized
                    // slide with the date instead of going stale.
                    if draft.remindersCustomized {
                        draft.reminders = ActionItem.shiftedReminders(
                            draft.reminders, fromDue: draft.dueDate, toDue: newValue)
                    }
                    draft.dueDate = newValue
                })
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

    private func chipBox<C: View>(_ label: LocalizedStringKey, flagged: Bool, @ViewBuilder _ value: () -> C) -> some View {
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

    // URLs + phone numbers → tappable links (shared with Detail/StepDetail).
    private func linked(_ string: String) -> AttributedString { linkified(string) }
}
