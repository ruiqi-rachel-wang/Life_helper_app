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

// Wraps a captured/picked image so navigationDestination can push the
// scan result once an image exists. Hashable by id (UIImage isn't Hashable).
private struct ScanRoute: Identifiable, Hashable {
    let id = UUID()
    let image: UIImage
    static func == (a: ScanRoute, b: ScanRoute) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct CreateView: View {
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var cameraImage: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var scanRoute: ScanRoute?

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.paper.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    Text("NEW ITEM")
                        .font(.eyebrow)
                        .tracking(1.4)
                        .foregroundStyle(Color.faded)
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
            }
            .navigationBarHidden(true)
            // Camera capture (real device only) → OCR result.
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker(image: $cameraImage).ignoresSafeArea()
            }
            // Fallback when there's no camera (e.g. Simulator): pick a photo.
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
            // After capture/pick, push the combined Review screen (OCR → AI →
            // editable result → Add to inbox).
            .navigationDestination(item: $scanRoute) { route in
                ReviewView(image: route.image)
            }
        }
        .onChange(of: cameraImage) { _, new in
            if let new { scanRoute = ScanRoute(image: new); cameraImage = nil }
        }
        .onChange(of: photoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    scanRoute = ScanRoute(image: image)
                }
                photoItem = nil
            }
        }
    }

    // Big primary action: Scan a document → camera → OCR. With no camera
    // (Simulator), fall back to the photo picker so it still works.
    private var heroTile: some View {
        Button {
            if cameraAvailable { showCamera = true } else { showPhotoPicker = true }
        } label: {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MOST COMMON")
                        .font(.eyebrow).tracking(1.4)
                        .foregroundStyle(Color.paper.opacity(0.55))
                    Text("Scan a document")
                        .font(.serifModal).tracking(-0.4)
                        .foregroundStyle(Color.paper)
                    Text("Camera · OCR runs on device")
                        .font(.subline)
                        .foregroundStyle(Color.paper.opacity(0.65))
                }
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.paper.opacity(0.12))
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
    private var secondaryRow: some View {
        HStack(spacing: 8) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                SecondaryTile(symbol: "photo.on.rectangle.angled",
                              title: "Upload from Photos")
            }
            .buttonStyle(.plain)

            NavigationLink {
                CreateForm()
            } label: {
                SecondaryTile(symbol: "square.and.pencil",
                              title: "Create it yourself")
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Secondary tile

private struct SecondaryTile: View {
    let symbol: String
    let title: String

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.bg)
                Image(systemName: symbol)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.ink)
            }
            .frame(width: 32, height: 32)

            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.ink)
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

    @State private var title = ""
    @State private var includeDue = false
    @State private var dueDate = Calendar.current.startOfDay(for: .now)
    @State private var steps: [ChecklistStep] = []
    @State private var note = ""
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
                    dueCard
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
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

    // MARK: due date (optional, behind a toggle)

    private var dueCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add a due date").font(.system(size: 14)).foregroundStyle(Color.ink)
                Spacer()
                Toggle("", isOn: $includeDue.animation()).labelsHidden().tint(Color.ink)
            }
            if includeDue {
                Rectangle().fill(Color.hairD).frame(height: 1).padding(.vertical, 12)
                HStack {
                    Text("Due").font(.subline).foregroundStyle(Color.faded)
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

    // MARK: note (text + optional photo)

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NOTE").font(.eyebrow).tracking(1.0).foregroundStyle(Color.faded)
            TextField("Add a note…", text: $note, axis: .vertical)
                .font(.body14).foregroundStyle(Color.ink).lineLimit(2...5)

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
            category: .other,                       // TODO: optional category picker
            dueDate: includeDue ? dueDate : nil,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            imageData: imageData,
            steps: cleanSteps
        )
        context.insert(item)
        ReminderScheduler.shared.reschedule(for: item)   // schedule reminders
        router.goToInbox()   // land on the Inbox so the new item is visible
        dismiss()
    }
}

#Preview {
    CreateView()
        .modelContainer(for: ActionItem.self, inMemory: true)
        .environment(AppRouter())
}
