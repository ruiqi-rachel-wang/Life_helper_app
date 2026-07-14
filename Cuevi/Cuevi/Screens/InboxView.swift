//  InboxView.swift
//
//  The home tab — the daily landing screen. Reads items live from the
//  SwiftData store (@Query) and groups them by urgency at render time.
//  Done items collect in a section at the bottom until deleted.
//
//  Marking done / deleting / editing on the Detail screen flows back here
//  automatically, because both screens share the same stored objects.
//

import SwiftUI
import SwiftData

struct InboxView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(TourGuide.self) private var tourGuide
    @Query(sort: \ActionItem.createdAt, order: .reverse) private var items: [ActionItem]

    // Urgency buckets — computed by the pure, tested grouping function.
    private var buckets: InboxBuckets { items.groupedForInbox() }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.paper.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        masthead
                            .padding(.horizontal, 24)
                            .padding(.bottom, 18)

                        if items.isEmpty {
                            emptyState
                        } else {
                            let b = buckets
                            section("Needs attention", b.needsAttention, tone: .bad)
                            section("Due this week", b.dueThisWeek)
                            section("In progress", b.inProgress)
                            section("Upcoming", b.upcoming, muted: true)
                            section("Done", b.done, muted: true, done: true)
                        }

                        PrivacyBanner()
                            .padding(.horizontal, 14)
                            .padding(.top, 24)

                        Spacer(minLength: 40)
                    }
                    .padding(.top, 48)
                }

                tourOverlay
            }
            .animation(.easeInOut(duration: 0.25), value: tourGuide.step)
            .navigationBarHidden(true)
            // Notification tap → open that item's Detail. The binding finds
            // the item by the id the delegate stashed in the router.
            .navigationDestination(item: pendingItem) { item in
                DetailView(item: item)
            }
        }
    }

    // MARK: first-run tour (Evernote-style coach marks)
    //
    // The intro + Add-tab cards dim the screen behind them — but the tab bar
    // sits outside this view, so it stays bright and tappable (the card points
    // at it). The final card doesn't dim anything: it invites you to actually
    // tap/swipe the row it's introducing, so the list has to stay live.
    // The .reviewAdd card renders on the Review screen, not here.
    @ViewBuilder
    private var tourOverlay: some View {
        switch tourGuide.step {
        case .welcome:
            ZStack {
                Color.black.opacity(0.35).ignoresSafeArea()
                TourCard(title: "Welcome to Cuevi",
                         message: "Let's take a quick tour — add your first to-do and see how Cuevi keeps you on track.",
                         stepIndex: TourGuide.Step.welcome.rawValue,
                         onNext: { tourGuide.advance(from: .welcome) },
                         onSkip: { tourGuide.finish() })
                    .padding(.horizontal, 24)
            }
        case .addTab:
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.35).ignoresSafeArea()
                TourCard(title: "Add anything",
                         message: "Tap **Add** below — that's where new to-dos start.",
                         stepIndex: TourGuide.Step.addTab.rawValue,
                         onNext: { router.selectedTab = .add },   // RootTabView advances the tour
                         onSkip: { tourGuide.finish() })
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        case .inboxRow where !items.isEmpty:
            VStack {
                Spacer()
                TourCard(title: "Your to-dos live here",
                         message: "Tap one to open it, or swipe it left to mark it done. You're all set.",
                         stepIndex: TourGuide.Step.inboxRow.rawValue,
                         isLast: true,
                         onNext: { tourGuide.finish() },
                         onSkip: { tourGuide.finish() })
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        default:
            EmptyView()
        }
    }

    // Resolves router.pendingItemID to the actual item; clearing it pops.
    private var pendingItem: Binding<ActionItem?> {
        Binding(
            get: { items.first { $0.id == router.pendingItemID } },
            set: { if $0 == nil { router.pendingItemID = nil } }
        )
    }

    // MARK: masthead

    private var masthead: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(dateLabel)
                    .font(.eyebrow).tracking(1.4).foregroundStyle(Color.faded)
                Text("To-Dos & Reminders")
                    .font(.serifTitle).tracking(-0.6).foregroundStyle(Color.ink)
            }
            Spacer()
            Text("\(buckets.activeCount) active")
                .font(.eyebrow).tracking(0.6).foregroundStyle(Color.faded)
        }
    }

    private var dateLabel: String {
        let weekday  = Date.now.formatted(.dateTime.weekday(.abbreviated)).uppercased()
        let monthDay = Date.now.formatted(.dateTime.month(.abbreviated).day()).uppercased()
        return "\(weekday) · \(monthDay)"
    }

    // MARK: a section (only renders when it has items)

    @ViewBuilder
    private func section(_ title: String, _ rows: [ActionItem],
                         tone: SectionTone = .normal,
                         muted: Bool = false,
                         done: Bool = false) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    // Section titles are app strings passed in as a String, so wrap
                    // in LocalizedStringKey to localize them (a plain Text(String)
                    // would show them verbatim).
                    Text(LocalizedStringKey(title))
                        .font(.serifSection)
                        .foregroundStyle(
                            muted ? Color.faded
                            : tone == .bad ? Color.bad
                            : Color.ink
                        )
                    Spacer()
                    Text("\(rows.count)")
                        .font(.eyebrow).tracking(0.6).foregroundStyle(Color.faded)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                        if index != 0 { InboxRowDivider() }
                        SwipeRow(
                            item: item, done: done,
                            onOpen: { tourGuide.advance(from: .inboxRow); router.pendingItemID = item.id },
                            onComplete: { tourGuide.advance(from: .inboxRow); withAnimation { ItemActions.complete(item, in: context) } },
                            onDelete: { withAnimation { ItemActions.delete(item, in: context) } })
                    }
                }
                .background(Color.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
                .padding(.horizontal, 14)
            }
            .padding(.top, 16)
        }
    }

    // The empty Inbox is a teacher, not a dead end: the three ways to start,
    // with colorful icons (tester feedback: make what-to-do-next obvious).
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nothing here yet — three ways to start")
                .font(.serifSection).foregroundStyle(Color.ink)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)

            emptyRow("camera.viewfinder", Color.sourceScanned,
                     "Scan a letter or bill",
                     "Tap ＋ below, then Scan — Cuevi explains it and builds your steps.")
            emptyRow("books.vertical.fill", Color.sourceGuide,
                     "Pick a life guide",
                     "Moving, taxes, driver's license… ready-made checklists for life in the U.S.")
            emptyRow("square.and.pencil", Color.accent,
                     "Add it yourself",
                     "A quick to-do with a date — Cuevi reminds you before it's due.")

            Button { tourGuide.start() } label: {
                Label("Show me how Cuevi works", systemImage: "play.circle")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(Color.accent)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }

    private func emptyRow(_ symbol: String, _ color: Color,
                          _ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.14))
                Image(systemName: symbol)
                    .font(.system(size: 20)).foregroundStyle(color)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.cardTitle).foregroundStyle(Color.ink)
                Text(body).font(.subline).foregroundStyle(Color.faded).lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hair, lineWidth: 1))
    }
}

enum SectionTone { case normal, bad }

// MARK: - Swipeable row

// Tap opens Detail (via the router's pendingItemID — the same push the
// notification tap uses, so there's only one navigationDestination). Swiping
// left reveals Done (active rows) + Delete. A horizontal-dominance guard keeps
// vertical scrolling working, and a VoiceOver action exposes the same buttons.
private struct SwipeRow: View {
    let item: ActionItem
    var done: Bool = false
    let onOpen: () -> Void
    let onComplete: () -> Void
    let onDelete: () -> Void

    @State private var settled: CGFloat = 0        // 0 = closed, -reveal = open
    @GestureState private var live: CGFloat = 0    // in-flight drag
    @State private var confirmDelete = false       // swipe Delete asks first — no undo exists
    private let btnW: CGFloat = 78

    private var reveal: CGFloat { done ? btnW : btnW * 2 }  // done rows: delete only
    private var offset: CGFloat { min(0, max(-reveal, settled + live)) }

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                if !done {
                    swipeButton("checkmark", "Done", Color.ok) { close(); onComplete() }
                }
                swipeButton("trash", "Delete", Color.bad) { close(); confirmDelete = true }
            }

            Button { offset < 0 ? close() : onOpen() } label: {
                InboxRow(
                    glyph: item.category.symbol,
                    color: item.category.tint,
                    title: item.title,
                    subtitle: done ? String(localized: "Completed") : item.inboxSubtitle,
                    subtitleColor: done ? Color.faded : item.dueColor,
                    done: done
                )
                .background(Color.card)   // opaque so the buttons stay hidden until revealed
            }
            .buttonStyle(.plain)
            .offset(x: offset)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .updating($live) { value, state, _ in
                        // Only react to mostly-horizontal drags, so vertical
                        // scrolling of the list still works normally.
                        if abs(value.translation.width) > abs(value.translation.height) {
                            state = value.translation.width
                        }
                    }
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                            settled = (settled + value.translation.width) < -reveal / 2 ? -reveal : 0
                        }
                    }
            )
            .accessibilityAction(named: done ? Text("Delete") : Text("Mark done")) {
                done ? (confirmDelete = true) : onComplete()
            }
        }
        .clipped()
        // Delete is final (no undo), and a swipe is easy to fat-finger — confirm.
        // The Detail screen keeps the richer recurring "just this one / all future"
        // choice; here the title just says plainly what deleting will do.
        .confirmationDialog(
            item.isRecurring
                ? "This task repeats — deleting it also stops future ones."
                : "Delete this task?",
            isPresented: $confirmDelete, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { settled = 0 }
    }

    private func swipeButton(_ icon: String, _ label: LocalizedStringKey,
                             _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                Text(label).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(width: btnW).frame(maxHeight: .infinity)
            .background(color)
        }
        .buttonStyle(.plain)
    }
}

private struct InboxRowDivider: View {
    var body: some View {
        Rectangle().fill(Color.hair).frame(height: 1).padding(.leading, 64)
    }
}

private struct InboxRow: View {
    let glyph: String
    let color: Color
    let title: String
    let subtitle: String
    var subtitleColor: Color = .faded
    var done: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.faint : color)
                Image(systemName: done ? "checkmark" : glyph)
                    .foregroundStyle(.white)
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.cardTitle)
                    .foregroundStyle(done ? Color.faded : Color.ink)
                    .strikethrough(done, color: Color.faded)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subline)
                    .foregroundStyle(subtitleColor)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.faint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Privacy banner

private struct PrivacyBanner: View {
    var body: some View {
        Text("On-device scanning · No bank login · No autopay")
            .font(.eyebrow).tracking(0.4).foregroundStyle(Color.faded)
            .padding(.vertical, 14).padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bg)
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.accent).frame(width: 2)
            }
    }
}

#Preview {
    InboxView()
        .modelContainer(for: ActionItem.self, inMemory: true)
        .environment(AppRouter())
        .environment(TourGuide())
}
