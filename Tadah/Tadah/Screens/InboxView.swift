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
    @Environment(ProfileStore.self) private var profiles
    @Query(sort: \ActionItem.createdAt, order: .reverse) private var allItems: [ActionItem]

    // Only the profile you're currently viewing. Filtered in memory rather than
    // with a dynamic @Query: TaskLimit caps the store at ~100 items per profile
    // (800 for a full family), so this is trivial, and the list is already grouped
    // in memory below. Items with no profile yet are the owner's (see ProfileStore).
    private var items: [ActionItem] {
        guard let active = profiles.activeProfileID else { return allItems }
        let isOwner = profiles.active?.isOwner == true
        return allItems.filter { $0.profileID == active || (isOwner && $0.profileID == nil) }
    }

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
        // Only the currently-selected tab draws a card. During a tab switch both
        // this view and the Add page briefly coexist; without this guard each
        // could show its own card for a frame, which looked "messy" mid-switch.
        switch (router.selectedTab == .inbox) ? tourGuide.step : nil {
        case .welcome:
            ZStack {
                Color.black.opacity(0.35).ignoresSafeArea()
                TourCard(title: "Welcome to Tadah",
                         message: "Let's take a quick tour — add your first to-do and see how Tadah keeps you on track.",
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
                            onReopen: { withAnimation { ItemActions.reopen(item) } },
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

    // The empty Inbox is a teacher, not a dead end: the two ways to start,
    // with colorful icons (tester feedback: make what-to-do-next obvious).
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nothing here yet — two ways to start")
                .font(.serifSection).foregroundStyle(Color.ink)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)

            emptyRow("camera.viewfinder", Color.sourceScanned,
                     "Scan a letter or bill",
                     "Tap ＋ below, then Scan — Tadah explains it and builds your steps.")
            emptyRow("books.vertical.fill", Color.sourceGuide,
                     "Pick a life guide",
                     "Moving, taxes, driver's license… ready-made checklists for life in the U.S.")

            Button { tourGuide.start() } label: {
                Label("Show me how Tadah works", systemImage: "play.circle")
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
// notification tap uses, so there's only one navigationDestination). Swipe LEFT
// toggles done immediately (swipe again to undo); swipe RIGHT reveals a Delete
// button to tap. A horizontal-dominance guard keeps vertical scrolling working,
// and VoiceOver actions expose the same choices.
private struct SwipeRow: View {
    let item: ActionItem
    var done: Bool = false
    let onOpen: () -> Void
    let onComplete: () -> Void
    let onReopen: () -> Void
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0     // live x-offset of the row
    @State private var rest: CGFloat = 0       // committed resting offset (0, or +btnW = Delete open)
    private let btnW: CGFloat = 84
    private let spring = Animation.spring(response: 0.28, dampingFraction: 0.85)

    var body: some View {
        ZStack {
            // Behind the row: Delete on the leading edge (revealed by a RIGHT
            // swipe), and a Done/Undo hint on the trailing edge (shown while
            // swiping LEFT, before the toggle fires on release).
            HStack(spacing: 0) {
                deleteButton
                Spacer()
                doneHint
            }

            // A plain tappable view — NOT a Button. A Button paired with
            // `.simultaneousGesture` fires a phantom tap on release of every
            // swipe, which used to auto-open the row after a left-swipe (done)
            // and slam the Delete tray shut right after a right-swipe. A
            // `.onTapGesture` only fires on a clean tap (the finger didn't move),
            // so a swipe never triggers it, while the drag stays simultaneous so
            // vertical scrolling keeps working.
            InboxRow(
                glyph: item.category.symbol,
                color: item.category.tint,
                title: item.title,
                subtitle: done ? String(localized: "Completed") : item.inboxSubtitle,
                subtitleColor: done ? Color.faded : item.dueColor,
                done: done
            )
            .background(Color.card)   // opaque so the buttons stay hidden until revealed
            .contentShape(Rectangle())
            .offset(x: offset)
            .onTapGesture { rest != 0 ? close() : onOpen() }
            .simultaneousGesture(dragGesture)
            .accessibilityAddTraits(.isButton)
            // Expose the SAME actions to VoiceOver: an active row toggles done, a
            // done row toggles back, and either can be deleted.
            .accessibilityActions {
                if done { Button("Mark as not done") { onReopen() } }
                else { Button("Mark done") { onComplete() } }
                Button("Delete") { onDelete() }
            }
        }
        .clipped()
    }

    // Swipe LEFT toggles done immediately (then springs back — swipe again to
    // undo); swipe RIGHT settles open to reveal Delete. Small drags snap to the
    // nearest resting state; the horizontal-dominance guard keeps vertical
    // scrolling working.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                offset = min(btnW, max(-btnW, rest + value.translation.width))
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    withAnimation(spring) { offset = rest }; return
                }
                let dx = value.translation.width
                let t = btnW * 0.5
                if dx <= -t && rest == 0 {
                    done ? onReopen() : onComplete()                       // LEFT → toggle done
                    withAnimation(spring) { offset = 0 }
                } else if dx >= t {
                    rest = btnW; withAnimation(spring) { offset = btnW }    // RIGHT → reveal Delete
                } else {
                    rest = 0; withAnimation(spring) { offset = 0 }          // close / snap back
                }
            }
    }

    // Tap-to-delete, revealed by a right swipe ("one more click" before it's gone).
    private var deleteButton: some View {
        Button { onDelete() } label: {
            VStack(spacing: 3) {
                Image(systemName: "trash").font(.system(size: 17, weight: .semibold))
                Text("Delete").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(width: btnW).frame(maxHeight: .infinity)
            .background(Color.bad)
        }
        .buttonStyle(.plain)
        .opacity(offset > 1 ? 1 : 0)
    }

    // Feedback while swiping left; the done toggle itself fires on release.
    private var doneHint: some View {
        VStack(spacing: 3) {
            Image(systemName: done ? "arrow.uturn.left" : "checkmark").font(.system(size: 17, weight: .semibold))
            Text(done ? "Undo" : "Done").font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.white)
        .frame(width: btnW).frame(maxHeight: .infinity)
        .background(done ? Color.warn : Color.ok)
        .opacity(offset < -1 ? 1 : 0)
    }

    private func close() {
        rest = 0
        withAnimation(spring) { offset = 0 }
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

// MARK: - Trust banner
//
// Was "On-device scanning · No bank login · No autopay". The on-device claim is
// gone (2026-08-06): we no longer sell local-only storage, since items now back
// up to the account. The other two are about what Tadah will never DO — touch
// your bank or charge you — which stays true and is the real reassurance.

private struct PrivacyBanner: View {
    var body: some View {
        Text("No bank login · No autopay")
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
        .environment(ProfileStore())
}
