//
//  DocumentTranslationView.swift
//
//  In-picture document translation, Google-Translate-image style. Tapping a
//  scanned photo enlarges it (`FullPhotoViewer`); a "Translate / Show original"
//  toggle then overlays the translated text ON the document, positioned over each
//  original line — no separate screen.
//
//  Translation is Apple's on-device Translation framework (iOS 18+) ONLY: free,
//  private — the document never leaves the phone. There is deliberately no cloud
//  fallback (a product decision for sensitive medical / tax / immigration / money
//  documents). On iOS 17 the Translate control is hidden; if the on-device
//  translator can't run (e.g. the Simulator, or an undownloaded language it can't
//  fetch) the viewer says so rather than sending anything anywhere.
//

import SwiftUI
import Translation

struct FullPhotoViewer: View {
    let photo: UIImage
    var language: ExplainLanguage = .english
    @Environment(\.dismiss) private var dismiss

    @State private var showTranslation = false
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var phase: Phase = .idle
    @State private var lines: [VisionOCR.OCRLine] = []
    @State private var translations: [String] = []

    private enum Phase { case idle, ocring, translating([String]), ready, empty, failed }

    // Only offer translation to a non-English reader on an OS with the on-device
    // framework. iOS 17 users just get the plain photo viewer.
    private var canTranslate: Bool {
        guard language != .english else { return false }
        if #available(iOS 18.0, *) { return true } else { return false }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            if showTranslation {
                translatedLayer
            } else {
                originalLayer.onTapGesture { if canTranslate { toggle() } }
            }

            // Hidden on-device batch translator (iOS 18+), once OCR has the lines.
            if #available(iOS 18.0, *) {
                if case .translating(let texts) = phase {
                    AppleBatchCarrier(texts: texts, target: language.bcp47,
                                      onDone: { translations = $0; phase = .ready },
                                      onFail: { phase = .failed })
                        .frame(width: 0, height: 0).hidden()
                }
            }

            topBar
        }
    }

    // MARK: layers

    private var originalLayer: some View {
        Image(uiImage: photo).resizable().scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(ZoomPan(zoom: $zoom, offset: $offset))
            .contentShape(Rectangle())
    }

    @ViewBuilder private var translatedLayer: some View {
        switch phase {
        case .ready:
            // Image + positioned text scale/pan together (translated text can be small).
            GeometryReader { geo in
                TranslatedOverlay(photo: photo, lines: lines,
                                  translations: translations, container: geo.size)
                    .modifier(ZoomPan(zoom: $zoom, offset: $offset))
            }
        case .empty:
            note("Couldn't read any text in this document.")
        case .failed:
            note("Couldn't translate this document on your device.", retry: true)
        default:  // .idle / .ocring / .translating → working
            ZStack {
                Image(uiImage: photo).resizable().scaledToFit().opacity(0.35)
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Translating…").font(.subline).foregroundStyle(.white)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Capsule().fill(.black.opacity(0.6)))
            }
        }
    }

    private func note(_ text: LocalizedStringKey, retry: Bool = false) -> some View {
        ZStack {
            Image(uiImage: photo).resizable().scaledToFit().opacity(0.35)
            VStack(spacing: 12) {
                Text(text).font(.subline).foregroundStyle(.white).multilineTextAlignment(.center)
                if retry {
                    Button { start() } label: {
                        Text("Try again").font(.system(size: 14, weight: .semibold)).foregroundStyle(.black)
                            .padding(.horizontal, 18).padding(.vertical, 9)
                            .background(Capsule().fill(.white))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
    }

    private var topBar: some View {
        HStack {
            if canTranslate {
                Button { toggle() } label: {
                    Label(showTranslation ? "Show original" : "Translate",
                          systemImage: showTranslation ? "photo" : "globe")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(showTranslation ? Color.accent : .white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(showTranslation ? Color.card : .black.opacity(0.5)))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .buttonStyle(.plain).accessibilityLabel("Close")
        }
        .padding(16)
    }

    // MARK: actions

    private func toggle() {
        zoom = 1; offset = .zero               // each mode starts fit-to-screen
        showTranslation.toggle()
        if showTranslation, case .idle = phase { start() }
    }

    private func start() {
        Task {
            phase = .ocring
            let ls = await VisionOCR.recognizeLines(in: photo)
            guard !ls.isEmpty else { phase = .empty; return }
            lines = ls
            if #available(iOS 18.0, *) {
                phase = .translating(ls.map(\.text))   // on-device only
            } else {
                phase = .failed                        // unreachable (button is gated)
            }
        }
    }
}

// MARK: - Pinch-to-zoom + pan (cumulative)

private struct ZoomPan: ViewModifier {
    @Binding var zoom: CGFloat
    @Binding var offset: CGSize
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .scaleEffect(zoom * pinch)
            .offset(x: offset.width + drag.width, y: offset.height + drag.height)
            .gesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in
                        zoom = min(max(zoom * value.magnification, 1), 6)
                        if zoom == 1 { offset = .zero }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .updating($drag) { value, state, _ in if zoom > 1 { state = value.translation } }
                    .onEnded { value in
                        guard zoom > 1 else { return }
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                    }
            )
    }
}

// MARK: - The translated text, positioned over each source line

private struct TranslatedOverlay: View {
    let photo: UIImage
    let lines: [VisionOCR.OCRLine]
    let translations: [String]
    let container: CGSize

    var body: some View {
        let fit = Self.fittedRect(image: photo.size, in: container)
        ZStack(alignment: .topLeading) {
            Image(uiImage: photo).resizable().scaledToFit()
                .frame(width: container.width, height: container.height)

            ForEach(lines.indices, id: \.self) { i in
                let t = i < translations.count ? translations[i] : ""
                if !t.isEmpty {
                    let b = lines[i].box                       // normalized, bottom-left
                    let w = max(1, b.width * fit.width)
                    let h = max(1, b.height * fit.height)
                    let cx = fit.minX + (b.minX + b.width / 2) * fit.width
                    let cy = fit.minY + (1 - (b.minY + b.height / 2)) * fit.height
                    Text(t)
                        .font(.system(size: h * 0.6))
                        .minimumScaleFactor(0.2)
                        .lineLimit(1)
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 2)
                        // Slightly shorter than the source line so neighbouring
                        // blocks keep a gap and don't cover each other's text.
                        .frame(width: w, height: h * 0.82, alignment: .leading)
                        .background(Color.paper)
                        .position(x: cx, y: cy)
                }
            }
        }
        .frame(width: container.width, height: container.height)
    }

    // scaledToFit rect of the image inside the container (letterboxed).
    static func fittedRect(image s: CGSize, in c: CGSize) -> CGRect {
        guard s.width > 0, s.height > 0, c.width > 0, c.height > 0 else { return .zero }
        let scale = min(c.width / s.width, c.height / s.height)
        let w = s.width * scale, h = s.height * scale
        return CGRect(x: (c.width - w) / 2, y: (c.height - h) / 2, width: w, height: h)
    }
}

// MARK: - Apple on-device batch carrier

// Invisible view hosting a `.translationTask`; translates all lines in one batch
// and reports them back aligned. Its own @available type keeps iOS-18-only
// symbols out of the base view.
@available(iOS 18.0, *)
private struct AppleBatchCarrier: View {
    let texts: [String]
    let target: String            // BCP-47
    let onDone: ([String]) -> Void
    let onFail: () -> Void
    @State private var config: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .translationTask(config) { session in
                do {
                    let requests = texts.enumerated().map {
                        TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset))
                    }
                    var out = Array(repeating: "", count: texts.count)
                    for response in try await session.translations(from: requests) {
                        if let id = response.clientIdentifier, let i = Int(id), out.indices.contains(i) {
                            out[i] = response.targetText
                        }
                    }
                    onDone(out)
                } catch {
                    onFail()
                }
            }
            .onAppear {
                config = TranslationSession.Configuration(target: Locale.Language(identifier: target))
            }
    }
}
