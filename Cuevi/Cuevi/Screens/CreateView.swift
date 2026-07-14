//  CreateView.swift
//
//  The Add tab — the picker shown when the user wants to add something.
//  Three entries: scan with the camera, upload from Photos, or create
//  by hand. Scan/Upload feed the OCR pipeline (→ Review); create-by-hand
//  opens a manual form.
//
//  "Sheet" layout from the spec: a big primary Scan hero + two smaller
//  secondary tiles. "Create it yourself" opens a real form that saves to
//  the store (title-only is valid). Scan/Upload run OCR → AI extraction in
//  the combined ReviewView (edit → Add to inbox).
//

import SwiftUI
import SwiftData
import PhotosUI

// Wraps the captured/picked image(s) — one document can be several pages (e.g.
// the front and back of a notice). Hashable by id (UIImage isn't Hashable).
private struct ScanRoute: Identifiable, Hashable {
    let id = UUID()
    let images: [UIImage]
    var warning: String? = nil   // e.g. "some pages couldn't be opened"
    static func == (a: ScanRoute, b: ScanRoute) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct CreateView: View {
    static let maxPages = 5   // up to 5 photos per document (1 from the camera)

    @Environment(TourGuide.self) private var tourGuide
    @Environment(AppRouter.self) private var router
    @AppStorage(ExplainLanguage.storageKey) private var explainLanguageRaw = ""
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var cameraImage: UIImage?
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var scanRoute: ScanRoute?
    @State private var quotaMessage: String?

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    // Gate a scan on the rate limit; shows the limit message and returns false
    // when the user is out of scans for the day/month.
    private func allowScan() -> Bool {
        if let reason = ScanQuota.blockedReason() { quotaMessage = reason; return false }
        return true
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.paper.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    // Masthead matches the other tabs: eyebrow + a long serif
                    // title (添加到提醒待办) + a one-liner saying what this page
                    // can DO — the three ways in, and what comes out.
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NEW ITEM")
                            .font(.eyebrow)
                            .tracking(1.4)
                            .foregroundStyle(Color.faded)
                        Text("Add a To-Do & Reminder")
                            .font(.serifTitle).tracking(-0.6)
                            .foregroundStyle(Color.ink)
                        Text("Scan a paper, upload a photo, or type it yourself — it becomes a to-do with reminders.")
                            .font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 24)

                    heroTile
                        .padding(.horizontal, 14)
                        .padding(.top, 20)

                    secondaryRow
                        .padding(.horizontal, 14)
                        .padding(.top, 10)

                    Spacer()
                }
                .padding(.top, 48)

                // Tour card for this page — parked above the tab bar, nothing
                // dimmed: all three tiles must stay tappable, they ARE the
                // instruction. Next opens the scan flow itself (Evernote-style:
                // the button takes you into the next thing); doing any tile by
                // hand advances the tour the same way. Gated on the Add tab
                // being selected so it can't linger over the Inbox mid-switch.
                if router.selectedTab == .add, tourGuide.step == .create {
                    VStack {
                        Spacer()
                        TourCard(title: "Start with a scan",
                                 message: "Try **Scan a document** — Cuevi reads it and builds your steps. Or upload a photo you already have, or type one in yourself.",
                                 stepIndex: TourGuide.Step.create.rawValue,
                                 onNext: { startScan() },
                                 onSkip: { tourGuide.finish() })
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: tourGuide.step)
            .navigationBarHidden(true)
            // Camera capture (real device only) → OCR result.
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker(image: $cameraImage).ignoresSafeArea()
            }
            // Fallback when there's no camera (e.g. Simulator): pick up to 5 photos.
            // `.ordered` so the numbered pick order = page order (front first).
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItems,
                          maxSelectionCount: Self.maxPages, selectionBehavior: .ordered,
                          matching: .images)
            // After capture/pick, push the combined Review screen. The scan `load`
            // OCRs every page, joins the text, then runs AI extraction once.
            .navigationDestination(item: $scanRoute) { route in
                // Resolve the user's language once, here, so the async load
                // closure captures a plain value (per the Profile picker).
                let language = ExplainLanguage.resolve(stored: explainLanguageRaw)
                ReviewView(
                    load: {
                        var pages: [String] = []
                        for image in route.images {
                            let text = await VisionOCR.recognizeText(in: image)
                            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { pages.append(text) }
                        }
                        guard !pages.isEmpty else { return [] }
                        // One document across pages — join so the model sees it all.
                        let ocr = pages.enumerated()
                            .map { pages.count > 1 ? "--- Page \($0.offset + 1) ---\n\($0.element)" : $0.element }
                            .joined(separator: "\n\n")
                        // Charge a scan only AFTER the request succeeds — a network
                        // or server failure shouldn't burn the user's daily quota.
                        let results = try await ExtractionService(extractor: OpenAIClient())
                            .extract(from: ocr, language: language)
                        ScanQuota.record()   // one document = one scan, regardless of page count
                        return results
                    },
                    images: route.images,
                    pageWarning: route.warning,
                    source: .scanned,
                    onClose: { scanRoute = nil })   // back to the Add screen
            }
        }
        .onChange(of: cameraImage) { _, new in
            if let new, allowScan() { scanRoute = ScanRoute(images: [new]) }
            cameraImage = nil
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                let requested = min(items.count, Self.maxPages)
                var images: [UIImage] = []
                for item in items.prefix(Self.maxPages) {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) { images.append(image) }
                }
                // Tell the user when some pages didn't load instead of silently
                // dropping them — they may think a page is included when it isn't.
                let warning = images.count < requested
                    ? String(localized: "Only \(images.count) of \(requested) photos could be opened — continuing with those.")
                    : nil
                if !images.isEmpty, allowScan() {
                    scanRoute = ScanRoute(images: images, warning: warning)
                }
                photoItems = []
            }
        }
        .alert("Scan limit reached", isPresented: Binding(
            get: { quotaMessage != nil }, set: { if !$0 { quotaMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(quotaMessage ?? "") }
    }

    // Big primary action: Scan a document → camera → OCR. With no camera
    // (Simulator), fall back to the photo picker so it still works.
    // The subtitle says what scanning is FOR — tester feedback: "most used" and
    // "OCR runs on device" meant nothing; examples do.
    // The hero tile's action, also fired by the tour card's Next: camera on a
    // real device, photo picker on the Simulator (no camera there).
    private func startScan() {
        guard allowScan() else { return }
        if cameraAvailable { showCamera = true } else { showPhotoPicker = true }
    }

    private var heroTile: some View {
        Button {
            startScan()
        } label: {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Scan a document")
                        .font(.serifModal).tracking(-0.4)
                        .foregroundStyle(Color.paper)
                    Text("Bills, letters & mail, notices, forms — Cuevi explains what to do")
                        .font(.subline)
                        .foregroundStyle(Color.paper.opacity(0.75))
                        .lineSpacing(2)
                }
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accent)
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.paper)
                }
                .frame(width: 56, height: 56)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.ink))
        }
        .buttonStyle(.plain)
    }

    // Two smaller tiles: Upload from Photos (→ OCR), Create it yourself.
    // Top-aligned: the captions wrap differently, so the cards differ in height.
    private var secondaryRow: some View {
        HStack(alignment: .top, spacing: 8) {
            PhotosPicker(selection: $photoItems, maxSelectionCount: Self.maxPages,
                         selectionBehavior: .ordered, matching: .images) {
                SecondaryTile(symbol: "photo.on.rectangle.angled",
                              color: .sourceScanned,
                              title: "Upload from Photos",
                              caption: "A photo or screenshot you already have")
            }
            .buttonStyle(.plain)

            NavigationLink {
                CreateForm()
            } label: {
                SecondaryTile(symbol: "square.and.pencil",
                              color: .sourceGuide,
                              title: "Create it yourself",
                              caption: "Type a quick to-do by hand")
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Secondary tile

private struct SecondaryTile: View {
    let symbol: String
    let color: Color
    let title: String
    let caption: String   // one plain line on what this option is for

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.14))
                Image(systemName: symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(color)
            }
            .frame(width: 38, height: 38)

            // LocalizedStringKey so the passed-in literals ("Upload from Photos",
            // "Create it yourself", captions) are translated, not shown verbatim.
            Text(LocalizedStringKey(title))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
            Text(LocalizedStringKey(caption))
                .font(.system(size: 11.5))
                .foregroundStyle(Color.faded)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hair, lineWidth: 1))
    }
}

// MARK: - Manual create form

// Only Title is required; due date, steps, and note (text + optional photo)
// are all optional. Saving inserts a real ActionItem into the store, so it
// appears in the Inbox and survives a restart.
private struct CreateForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(TourGuide.self) private var tourGuide

    @State private var title = ""
    @State private var category: ItemCategory = .other
    @State private var includeDue = false
    @State private var dueDate = Calendar.current.startOfDay(for: .now)
    @State private var steps: [ChecklistStep] = []
    @State private var amount = ""
    @State private var notes: [String] = []
    @State private var reminders: [ReminderItem] = []
    @State private var remindersCustomized = false
    @State private var photoItem: PhotosPickerItem?
    @State private var imageData: Data?

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    titleField
                        .padding(.horizontal, 14)
                        .padding(.top, 18)
                    categoryCard
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                    amountCard
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                    dueCard
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                    // Reminders only make sense with a due date — no date, no reminders.
                    if includeDue {
                        remindersCard
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
                    }
                    stepsCard
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                    noteCard
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                    saveButton
                        .padding(.horizontal, 14)
                        .padding(.top, 18)
                    Spacer(minLength: 40)
                }
                .padding(.top, 48)
            }
            .dismissKeyboardOnTap()
        }
        .navigationBarHidden(true)
    }

    // MARK: header

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium)).foregroundStyle(Color.faint)
            }
            .accessibilityLabel("Cancel")
            Spacer()
            Text("NEW TASK").font(.eyebrow).tracking(1.4).foregroundStyle(Color.faded)
            Spacer()
            Color.clear.frame(width: 22, height: 1)   // balances the × for centering
        }
        .padding(.horizontal, 22)
    }

    // MARK: title (required)

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TITLE").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
            TextField("What needs doing?", text: $title, axis: .vertical)
                .font(.system(size: 17, weight: .medium)).foregroundStyle(Color.ink)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }

    // MARK: category (pick the type → drives the icon/color)

    private var categoryCard: some View {
        HStack {
            Text("Category").font(.system(size: 14)).foregroundStyle(Color.ink)
            Spacer()
            Menu {
                ForEach(ItemCategory.allCases, id: \.self) { c in
                    Button { category = c } label: { Label(c.displayName, systemImage: c.symbol) }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: category.symbol).font(.system(size: 13)).foregroundStyle(category.tint)
                    Text(category.displayName).font(.body14).foregroundStyle(Color.ink)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 11)).foregroundStyle(Color.faint)
                }
            }
        }
        .padding(16)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }

    // MARK: amount (optional)

    private var amountCard: some View {
        HStack {
            Text("Amount").font(.system(size: 14)).foregroundStyle(Color.ink)
            Spacer()
            HStack(spacing: 2) {
                Text("$").font(.body14).foregroundStyle(Color.faded)
                TextField("0.00", text: $amount)
                    .keyboardType(.decimalPad)
                    .font(.body14).foregroundStyle(Color.ink)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
            }
        }
        .padding(16)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }

    // MARK: due date (optional, behind a toggle)

    private var dueCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add a date").font(.system(size: 14)).foregroundStyle(Color.ink)
                Spacer()
                Toggle("", isOn: $includeDue.animation()).labelsHidden().tint(Color.ink)
            }
            if includeDue {
                Rectangle().fill(Color.hairD).frame(height: 1).padding(.vertical, 12)
                HStack {
                    Text("Date").font(.subline).foregroundStyle(Color.faded)
                    Spacer()
                    DatePicker("", selection: $dueDate, displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.compact)
                }
            }
        }
        .padding(16)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }

    // MARK: steps (optional)

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("STEPS").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
                Spacer()
                Text("OPTIONAL").font(.eyebrow).tracking(0.6).foregroundStyle(Color.faint)
            }
            .padding(.bottom, steps.isEmpty ? 0 : 8)

            ForEach($steps) { $step in
                HStack(alignment: .top, spacing: 10) {
                    TextField("Step", text: $step.text, axis: .vertical)
                        .font(.body14).foregroundStyle(Color.ink)
                    Button { steps.removeAll { $0.id == step.id } } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 18)).foregroundStyle(Color.faint)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 8)
            }

            Button { steps.append(ChecklistStep(text: "")) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle").font(.system(size: 16))
                    Text(steps.isEmpty ? "Add a step (or leave empty for a reminder)"
                                       : "Add a step").font(.body14)
                }
                .foregroundStyle(Color.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }

    // MARK: reminders (only with a due date) — same editor as Review / Detail

    private var remindersCard: some View {
        RemindersEditor(
            reminders: $reminders,
            customized: $remindersCustomized,
            defaults: ActionItem.defaultReminders(dueDate: dueDate, dueHasTime: false, leadHours: 2),
            dueDate: dueDate,
            isEditing: true)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }

    // MARK: notes (a checklist of notes — same as Review / Detail) + optional photo

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NOTES").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
            ForEach(notes.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 8) {
                    Text("•").font(.body14).foregroundStyle(Color.faded)
                    TextField("Note", text: $notes[i], axis: .vertical)
                        .font(.body14).foregroundStyle(Color.ink)
                    Button { notes.remove(at: i) } label: {
                        Image(systemName: "minus.circle.fill").font(.system(size: 18)).foregroundStyle(Color.faint)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button { notes.append("") } label: {
                Label("Add a note", systemImage: "plus.circle").font(.body14).foregroundStyle(Color.accent)
            }
            .buttonStyle(.plain)

            if let imageData, let uiImage = UIImage(data: imageData) {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: uiImage)
                        .resizable().scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Button { self.imageData = nil; photoItem = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white, .black.opacity(0.5))
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    HStack(spacing: 8) {
                        Image(systemName: "photo").font(.system(size: 16))
                        Text("Add a photo").font(.body14)
                    }
                    .foregroundStyle(Color.accent)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
        .onChange(of: photoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    imageData = data
                }
            }
        }
    }

    // MARK: save

    private var saveButton: some View {
        Button { save() } label: {
            Text("Save to inbox")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.paper)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(canSave ? Color.ink : Color.faint))
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
    }

    private func save() {
        let cleanSteps = steps
            .map { ChecklistStep(text: $0.text.trimmingCharacters(in: .whitespaces), done: $0.done) }
            .filter { !$0.text.isEmpty }
        let item = ActionItem(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            dueDate: includeDue ? dueDate : nil,
            imageData: imageData,
            steps: cleanSteps
        )
        item.notes = notes.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let amt = AmountParsing.decimal(from: amount), amt > 0 {
            item.amount = amt
        }
        // Reminders only when there's a due date; if the user edited them, keep
        // their list, otherwise leave them off the custom path so the item uses
        // the smart defaults.
        if includeDue, remindersCustomized {
            item.reminders = reminders
            item.remindersCustomized = true
        }
        context.insert(item)
        Metrics.record(.confirmed, itemID: item.id, source: ItemSource.custom.rawValue)
        ReminderScheduler.shared.reschedule(for: item)   // schedule reminders
        // Manual items skip the Review screen, so skip its tour card too —
        // jump straight to the final "your to-dos live here" card.
        tourGuide.catchUp(to: .inboxRow)
        router.goToInbox()   // land on the Inbox so the new item is visible
        dismiss()
    }
}

#Preview {
    CreateView()
        .modelContainer(for: ActionItem.self, inMemory: true)
        .environment(AppRouter())
}
