# Notie iOS — Build Plan & Architecture

> Canonical build reference. Living doc — update as decisions change.
> Companion docs: the Phase 1 Spec (HTML render) and design prototype.

---

## TL;DR

- **Language/Framework**: 100% Swift + SwiftUI (no Objective-C, no JS, no Python)
- **Stack**: SwiftData (local storage) · Apple Vision (on-device OCR) · GPT-4o-mini via Cloudflare Worker proxy · UNUserNotificationCenter (local notifications)
- **Architecture**: Plain-English folders — `App/` (entry + tab shell) · `Model/` (data: `ActionItem` is a SwiftData `@Model`, plus pure logic like bucketing/reminder math — UI-free, no `Color`/screen types) · `Screens/` (SwiftUI views) · `Theme/` (color/symbol + formatting) · `Notifications/` (UNUserNotificationCenter wrapper). The model uses SwiftData (iOS), but its *logic* (enums, derived state, grouping) is what ports to Android; the view layer owns all presentation.
- **Timeline**: 8 weeks to TestFlight (scoped down from spec's 12-week ambition)
- **Cost**: ~$8–15/month at first 1,000 users · ~$0.0004 per scan
- **One metric that matters**: % of confirmed action items marked done before due date. >50% working, <30% broken loop.

---

## Current progress (as of 2026-05-30)

**Week 0 — Setup** ✓ complete (pending only: product name, launch language — not code-blocking)
**Week 1 — SwiftUI shell** ✓ complete
**Week 2 — Persistence** ✓ complete — SwiftData store; Inbox reads live (@Query) with a Done section; Detail binds to the live object so Mark done / Delete / edits write back; Create form saves (title-only valid) with optional due date, steps, and a text+photo note. Backed up on GitHub (`ruiqi-rachel-wang/Life_helper_app`, branch `main`).
**Week 3 — Notifications** ✓ complete — local reminders (3d/1d/due/overdue at 9am) scheduled on save, cancelled on done/delete, rescheduled on edit; interactive Mark done / Remind me later actions; tap a banner to open the item. 14 unit tests.
**Week 4 — Camera + OCR** ✓ complete — Apple Vision OCR on-device; Scan (camera) / Upload (Photos) → ScanResultView shows the real extracted text. (Test via Upload in the Simulator; camera needs a device.)
**Week 5 — Rule parser + OpenAI extraction** ⏳ next.

What's running today:
- All 5 screens + Settings. Tab bar; navigation wired; Inbox groups items by urgency with a Done section.
- **Persistence works:** Create / Scan-Review / edits / check-offs / Mark done / Delete all save (SwiftData) and survive a restart. `ActionItem` is a `@Model` (UI-free — no `Color`/screen types); the view layer (`Theme/ItemStyle.swift`) maps category → color/symbol and formats strings.
- **Notifications work:** reminders scheduled on save, cancelled on done/delete, rescheduled on edit; interactive Mark done / Remind me later; tap a banner to open the item. DEBUG test button in Settings.
- Interactive controls are `Button`s (accessible).
- 14 unit tests (isOverdue, doneCount, reminderSchedule, inbox bucketing, a SwiftData round-trip) pass via Cmd+U. Deployment target iOS 17.0. Builds clean, no warnings.

Still mock (see "Temporary scaffolding" below): the **scan/Review pre-fill is fake** (no camera/OCR yet — Week 4–6); sample items are seeded on first launch; guides preview a Detail instead of adding; recurring isn't built (Week 7).

---

## Temporary scaffolding — what's fake right now

Everything below is mock/placeholder and gets replaced on the noted week.
**In code, grep `TEMP:` to find each spot.** (Persistence + notifications are
real now — what remains fake is mostly the scan pipeline and recurring.)

| What | Where | Real version |
|---|---|---|
| Sample items seeded on first launch | `ActionItem.swift` sample block + Inbox `.task` | replaced by real data once scanning/onboarding exist; harmless seed for testing |
| ＋ Scan/Upload jumps straight to a mock Review (pre-filled with Con Edison) | `CreateView.swift`, `ReviewView.swift` | Week 4–6 — camera → OCR → AI extraction fills Review for real |
| Review's category is fixed to `.other` on save | `ReviewView.swift` | Week 6 — category from AI extraction |
| Guides → Detail with placeholder steps (should be Review → Add) | `GuidesView.swift` | Week 7 — real template steps, via Review → Add to inbox |
| Recurring not built (no cadence; done/delete don't respawn) | model `repeatsMonthly` unused | Week 7 — Recurrence + auto next-cycle + recurring-aware delete |
| Settings mostly a stub (has a DEBUG test-reminder button) | `SettingsView.swift` | Week 8 — language, reminder timing, privacy, export |
| Raised ＋ tab button (floating circle) | `RootTabView.swift` | Week 7 polish — custom tab bar |

Done since (no longer fake): `ActionItem` is a SwiftData `@Model`; the Inbox
reads the live store and buckets by urgency; Create form saves; Detail edits /
Mark done / Delete persist; Review "Add to inbox" saves; reminders schedule.

Note: the 5 **guides themselves** (Moving, Bank, etc.) are *intentionally*
static for Phase 1 — that's not temporary, it's the design.

---

## Why this tech stack

| Question | Answer |
|---|---|
| Why Swift, not React Native? | Apple Vision OCR is the entire core pipeline; native is faster and simpler than a bridge. The editorial design uses New York/SF Pro — free and gorgeous in SwiftUI. iOS-first is explicit in the spec. |
| Why SwiftUI, not UIKit? | Modern, declarative, matches the prototype's component style. Faster iteration via Previews. Apple's blessed path for new apps. |
| Why GPT-4o-mini, not GPT-4o or Claude? | Task is structured extraction from clean text — doesn't need reasoning. 4o-mini is ~15× cheaper than 4o and plenty accurate. Swap via protocol if needed. |
| Why a Cloudflare Worker proxy? | Embedding the OpenAI key in the app means anyone can extract it from the binary and burn your account. Worker holds the key, rate-limits per IP, free tier covers 100K req/day. |
| Why no backend database? | Phase 1 is local-only per spec. No login, no sync, no servers — all data in SwiftData on device. |
| Why no vision/multimodal AI? | Cut from Phase 1. Text-only LLM is ~10× cheaper. If OCR is too poor, prompt user to re-shoot. |

---

## Architecture

Folders are plain-English and created only when they have content (grow
incrementally). Today's layout:

```
Notie/Notie/
├── App/                      ← entry point + app shell
│   ├── NotieApp.swift        ← @main; launches RootTabView
│   └── RootTabView.swift     ← the 4-tab bar (Inbox · Guides · Add · Settings)
│
├── Screens/                  ← one SwiftUI view per screen (the build plan's "Features")
│   ├── InboxView.swift       ← home list, urgency sections
│   ├── GuidesView.swift      ← 5 guide cards + filter chips
│   ├── DetailView.swift      ← one item: checklist, status, reminders
│   ├── ReviewView.swift      ← post-scan hero (editable)
│   ├── CreateView.swift      ← ＋ picker (scan / upload / manual)
│   └── SettingsView.swift    ← stub
│
├── Model/                    ← data types (no UI)
│   └── ActionItem.swift      ← ActionItem + ChecklistStep + WorkStatus + samples
│
├── Theme/                    ← the app's visual identity
│   ├── Color+Notie.swift     ← all color tokens
│   └── Font+Notie.swift      ← serif / sans / mono scale
│
└── Assets.xcassets
```

### Where future code lands (created the week it's needed)

```
Model/        Recurrence.swift, ExtractionResult.swift     (Wk 2 / Wk 5)
Storage/      ActionItemStore.swift (SwiftData)            (Wk 2)
Notifications/ Reminders.swift (UNUserNotificationCenter)  (Wk 3)
Scanning/     VisionOCR.swift, RuleBasedParser.swift       (Wk 4 / Wk 5)
AI/           OpenAIClient.swift (→ Cloudflare Worker)     (Wk 5)
Components/   shared views, once something is reused twice
```

The "pure logic vs iOS-specific" split (for a future Android port) is kept
by keeping `Model/` and the parsers free of SwiftUI imports — not by a
separate top-level `Core/` folder. Same payoff, less ceremony.

### Per-type Detail structure (future — decided 2026-05-30)

Different item TYPES should eventually render different Detail layouts — a
bill (amount, pay steps, recurring) is not shaped like a phone call (script,
number) or a checklist (just steps). We are **not** building per-type layouts
yet. To stay ready: DetailView is composed of optional, item-driven sections
(stats / steps / reminders / note) that appear only when the item has that
data — so adding type-specific composition later is additive, not a rewrite.
Don't collapse everything into one rigid template.

### NotieTests/ (auto-created with the project)

```
NotieTests/        RecurrenceTests, RuleBasedParserTests, …   (Wk 2+)
NotieUITests/      basic tap-through (auto-generated)
```

### Data flow

```
[Camera/Photos]
      ↓
VisionOCREngine          ← Platform/
      ↓ raw text
RuleBasedParser          ← Core/Services/   (regex, no API cost)
      ↓ low-confidence fields only
OpenAIClient → Cloudflare Worker → OpenAI    ← Platform/  (the only AI call)
      ↓ ExtractionResult
ExtractionService.merge()
      ↓
ReviewViewModel          ← Features/Review/
      ↓ user confirms
ActionItemRepository.save()
      ↓
SwiftDataStorage         ← Platform/
UNNotificationService    ← Platform/  (schedules 3 reminders)
```

### Future Android port

Reuse (port Swift → Kotlin, same logic): `Model/`, the parsers, the LLM prompt/response shape.
Rewrite per-platform: `Storage/` (Room), `Notifications/` (WorkManager), `Scanning/` (ML Kit OCR), `Screens/` (Jetpack Compose).
Keep identical: LLM prompts, `ExtractionResult` shape, design-token values.

---

## Costs

| Item | Cost |
|---|---:|
| Apple Developer Program | $99/year (defer until ~Week 6) |
| OpenAI (GPT-4o-mini) | ~$0.0004 per scan |
| Cloudflare Worker | $0 free tier, $5/mo at scale |
| SwiftData / Vision / Notifications | $0 (on-device) |

**Monthly totals:**
- 10 users (TestFlight): ~$8/mo (just Apple Dev fee amortized)
- 1,000 users: ~$15/mo
- 10,000 users: ~$35/mo

---

## Key scope decisions (changes from the v3 spec)

The README handoff scoped the spec down. Where they conflict, **README wins**:

| Spec said | Build instead |
|---|---|
| EN/中文/ES live toggle on Review | One language only, chosen in Settings, generated once |
| Document history with search | Plain "Past items" list, no search |
| 5 guides with AI customization | 5 static checklist templates, no customization screen |
| Recurring monthly + yearly hardcoded | Cadence read from the document by AI (any interval) |
| Overdue follow-up daily up to 7 days | One overdue reminder the next morning |
| Vision-AI fallback for bad OCR | No vision model. Re-shoot the photo. |
| Draft reply / phone-call scripts | Cut entirely |

**Hard NO list for Phase 1:** login · cloud sync · family sharing · password manager · backend DB · provider DB · bank linking · autopay · email forwarding · chatbot · voice · Android · analytics dashboard

---

## Build order — 8 weeks

### Week 0: Setup (NOT code)
- [x] Install Xcode (free, ~15GB)
- [ ] Apple Developer account — **deferred until Week 6 (intentional)**
- [x] Sign in to Xcode with free Apple ID → "Personal Team"
- [x] Create OpenAI account, generate API key, set $20/mo spending cap
- [x] Create Notie Xcode project (SwiftUI, Swift, Storage: None, Tests: ✓)
- [x] Set up folder structure (flat for now — grow incrementally as features need them)
- [x] Write design tokens (Color+Notie.swift, Font+Notie.swift)
- [ ] Pick product name (test "Noted" vs "Handle" with 5 target users)
- [ ] Pick launch language (EN, 中文, or ES)

**Done when:** Xcode signed in, "Hello World" running in simulator, design tokens compile. ✓

### Week 1: SwiftUI shell with fake data ✓ COMPLETE
- [x] Tab bar: Inbox · Guides · ＋ · Settings
- [x] All 5 screens built (Inbox, Guides, Detail, Review, Create) + Settings stub
- [x] Reusable row/section/tile components (built per-screen; extract further when reused)
- [x] Navigation: inbox row → Detail, guide → Detail, ＋ Scan/Upload → Review
- [ ] *Polish deferred:* raised ＋ tab button (floating circle) → Week 7

**Done when:** every screen renders matching prototype within ~10%. All navigation works. No real data anywhere. ✓

### Week 2: SwiftData + Create flow (first real persistence) ✓ COMPLETE
- [x] SwiftData `@Model` on ActionItem (steps stored as Codable array; + imageData, createdAt)
- [x] Inbox reads from the store via @Query; buckets by urgency + Done section; seeds on first launch
- [x] Create form saves real items (title-only valid; optional due/steps/note + photo)
- [x] Mark done (→ Done section) / Delete / checkbox toggles write back to the store
- [x] Review "Add to inbox" saves too (mock pre-fill, real save)
- [x] Full editing on Detail + Review (title, type/sender, amount, due, steps, note)
- [x] Unit tests incl. a real SwiftData save/load/delete round-trip (10 pass)

**Decisions (2026-05-30):**
- **Create form:** only **Title is required**. Due date optional, steps optional,
  note optional. (No steps = a reminder; with steps = a checklist.)
- **Note supports images:** the note can hold a photo, not just text (e.g. a
  snapshot of the document). Stored as image data (external storage). Stretch
  part of Week 2 — text note first, then add the photo attachment.
- **Marking done (no delete):** the item moves to a **"Done" section at the
  bottom of the Inbox** — it does NOT vanish. It stays there until deleted.
- **Deleting a done item:** it disappears. For a **recurring** task, deleting
  must first ask: **delete just this one, or this and all future ones?**
  (The future-instances part only bites once recurring generates them — so the
  recurring-aware confirm dialog lands with recurrence in **Week 7**; Week 2
  handles plain one-off delete.)

**Done when:** Create a task (title only is enough) → force-quit + reopen →
still there. Mark done → moves to Done section. Delete → gone. Tests pass.

### Week 3: Notifications + workflow states ✓ COMPLETE
- [x] Request notification permission at launch (graceful if denied)
- [x] ReminderScheduler wrapping UNUserNotificationCenter (schedule/cancel/reschedule/snooze)
- [x] Schedule on save: 3d before, 1d before, due day, + overdue follow-up (fire 9am, skip past)
- [x] Cancel reminders when marked done or deleted
- [x] Re-schedule when the due date is edited (Detail .onDisappear)
- [x] **Notification actions**: Mark done (writes to store + cancels), Remind me
  later (snooze 2h), and tapping the banner opens that item's Detail (deep link
  via AppRouter.pendingItemID + navigationDestination)
- [x] `isOverdue` derived + red styling (Week 1/2)
- [x] DEBUG: Settings "Send a test reminder (5s)" + notification-status row

**Done when:** notification fires on a real schedule, with Mark done / Remind
me later / View actions. Mark done cancels future reminders. Overdue → red. ✓

> Status model (decided 2026-05-30): the user does NOT set status manually
> and there is no Defer. `inProgress` is derived (some steps checked), `done`
> comes from the Mark done button, `overdue` is derived. The Detail screen's
> top-right is **Edit** (like Review), not a status menu.

### Week 4: Camera + Apple Vision OCR ✓ COMPLETE
- [x] `VisionOCR` engine — `VNRecognizeTextRequest` (on-device, async), `Scanning/`
- [x] Camera capture (`CameraPicker`, UIImagePickerController) — device only
- [x] Photo upload (`PhotosPicker`) — works in the Simulator too
- [x] `ScanResultView` shows the photo + the raw extracted text (the debug screen)
- [x] `NSCameraUsageDescription` added to build settings (device camera permission)
- [x] Wired: ＋ → Scan (camera) / Upload (Photos) → ScanResultView → (mock) Review

**Done when:** scan/upload a real bill → see extracted text. ✓ (Test in the
Simulator via Upload — drag a bill image onto the simulator first. Camera
needs a real device.)

### Week 5: Parser + OpenAI extraction
- RuleBasedParser: regex for amount, date, account number
- Cloudflare Worker proxy (free tier, ~30 min setup)
- OpenAIClient calls the Worker, not OpenAI directly
- Tune prompt with 5 real bills from Week 4
- ExtractionService skips LLM when parser is confident
- Tests: RuleBasedParserTests (20+ cases), ExtractionServiceTests with mock LLM

**Done when:** paste OCR text → get valid JSON with amount, date, sender, steps, repeats. All-in test cost <$1.

### Week 6: Review screen end-to-end (THE SPINE)
- ExtractionService orchestrates full pipeline
- ReviewView connected to real ExtractionResult
- Quiet progress shimmer on captured photo (~3–5s target)
- Inline field editing
- Low-confidence fields get accent underline (no popup, no friction)
- "Add to inbox" creates real ActionItem + schedules reminders

**Done when:** photo of a letter → pre-filled Review → Add to Inbox → see it. **This is the shippable moment.** Everything after is polish + breadth.

### Week 7: Guides + recurring
- GuideTemplateService: 5 static checklists (Moving, Bank, Job, License, Visa)
- Guides tab: tap a guide → opens the **Review-style "confirm before adding"
  screen** (the SAME screen the scan flow uses, just fed a guide instead of
  an extraction) → review/customize steps → **Add to inbox**.
  Decided 2026-05-30: Review is the single "confirm before adding" screen for
  both scans (Wk 6) and guides (Wk 7) — a guide must NOT open a Detail (it
  isn't a saved task yet). Week-1 mock previews a Detail as a stand-in only.
- RecurringService: on mark-done with repeats, create next cycle with advanced due date
- Pull `repeats` from LLM (don't hardcode)

**Done when:** guide → checklist in 1 tap. Recurring bill marked done → next cycle exists with correct cadence.

### Week 8: Polish + TestFlight
1. Empty states (no inbox, no past items, OCR failed)
2. Error states (LLM down, OCR garbled, no network)
3. Settings: language picker, "keep original scans" toggle, version
4. Privacy banner on Inbox: `LOCAL OCR · NO BANK LINK · NO AUTOPAY`
5. Past items list (Done archive, no search) — **with delete** (swipe-to-delete
   here, plus the Delete button that already appears on a done item's Detail).
   Decided 2026-05-30: done items go to this list and can be removed from it.
6. Analytics events (`action_item_confirmed`, `action_item_completed`) → local JSON file
7. App icon (even placeholder serif "N" on cream)
8. **Apply for Apple Developer Program** if not already (1–3 day approval)
9. Xcode → Product → Archive → Distribute App → App Store Connect
10. 24–48h Apple automated review
11. Add 10 testers in App Store Connect → TestFlight tab
12. Recruit testers from target audience (immigrants, ESL families)

**Done when:** 10 real users have the build. You're logging the one metric.

---

## After Week 8

Run for 4 weeks. Watch the one metric:

> Of users who confirm an action item, what % come back to mark it done before the due date?

- **>50%** → working. Start Phase 2 (free-text Q&A, more guides).
- **30–50%** → fix the reminder loop. Notification timing, copy, frequency.
- **<30%** → return loop broken. Talk to users.

---

## Design tokens (reference)

### Colors

```swift
// Surface
let bg     = Color(hex: "#f4f1ea")   // canvas / chip fill
let paper  = Color(hex: "#fbf9f4")   // screen background
let card   = Color(hex: "#ffffff")   // raised card

// Ink
let ink    = Color(hex: "#29261b")              // primary text
let faded  = Color(hex: "#29261b").opacity(0.58) // secondary
let faint  = Color(hex: "#29261b").opacity(0.32) // chevrons, dividers
let hair   = Color(hex: "#29261b").opacity(0.12) // 1px borders
let hairD  = Color(hex: "#29261b").opacity(0.22) // dashed dividers

// Accents
let accent = Color(hex: "#b14a2a")   // burnt sienna — single brand accent
let ok     = Color(hex: "#1f6b4a")   // success / done
let warn   = Color(hex: "#a8651b")   // due-soon (amber)
let bad    = Color(hex: "#a93420")   // overdue / penalty
```

### Type (use system fonts)

| Prototype | iOS substitute |
|---|---|
| Fraunces (serif) | **New York** (`.system(size:, weight:, design: .serif)`) |
| Inter Tight (sans) | **SF Pro** (default `.system`) |
| IBM Plex Mono (mono) | **SF Mono** (`.system(size:, weight:, design: .monospaced)`) |

### Type scale

| Use | Size | Weight | Tracking | Family |
|---|---:|---:|---:|---|
| Screen title | 26pt | 500 | -0.8 | Serif | trimmed from spec's 34pt — saves vertical space on device |
| Modal title | 24pt | 500 | -0.6 | Serif | trimmed from 30pt |
| Detail title | 22pt | 500 | -0.6 | Serif | trimmed from 28pt |
| Stat number | 26pt | 500 | -1.0 | Serif | trimmed from 32pt |
| Section header | 14pt | 500 | -0.2 | Serif |
| Card title | 14.5pt | 600 | -0.2 | Sans |
| Body | 14pt | 400 | 0 | Sans |
| Subline | 12pt | 400 | 0 | Sans |
| Eyebrow | 10.5pt | 500 | +1.4 (uppercase) | Mono |

### Spacing
2 · 4 · 8 · 12 · 14 · 16 · 18 · 22 · 24 px scale.
Screen horizontal padding: **24** for prose, **14** for cards.

### Radii
- 8 — icon boxes, chip backgrounds
- 12 — buttons, small tiles
- 14 — cards, content groups
- 16 — hero tile (＋ picker)
- 99 — pills, segmented controls, FAB
- 18 — half of 36px avatar circles

### Source tags

| Source | Hex | Label | Meaning |
|---|---|---|---|
| Scanned | `#2A6FDB` | "Scanned" | Camera capture OR photo upload (same pipeline) |
| Guide | `#1F8A5B` | guide name | From a life-guide template |
| Custom | `#7a6a4a` | "Custom" | Created manually |

---

## The critical shared type

Define this BEFORE writing any service:

```swift
struct ExtractionResult {
    var documentType: String?
    var sender: String?
    var senderShort: String?
    var amount: Decimal?
    var currency: String?            // ISO 4217
    var dueDate: Date?
    var accountNumber: String?
    var category: String?            // "electricity", "rent", "violation"...
    var summary: String?             // 1-2 sentence plain-language
    var steps: [String]              // 3-5 action steps
    var siteURL: URL?
    var repeats: Recurrence?         // nil = one-off. AI reads from document.
    var confidence: Double           // 0-1 overall
    var lowConfidenceFields: Set<String>  // field names needing user review
}
```

Every layer produces this same type. ReviewViewModel just reads it. This is the most important interface in the whole codebase.

---

## How testing works on iOS

### Unit tests (XCTest)
- Auto-generated test target when you create the project
- Write `XCTestCase` subclasses in `NotieTests/`
- Run: **Cmd+U** in Xcode, runs in simulator, ~5 seconds
- Test the `Core/` layer aggressively — it has no platform dependencies

### SwiftUI Previews
- Add `#Preview { YourView() }` blocks
- Render in Xcode's canvas without building
- Use `.mock` static factories on models for preview data

### TestFlight (beta to real users)
- Requires Apple Developer Program ($99/year)
- Xcode → Product → Archive → Distribute App → App Store Connect
- 24–48h automated Apple review
- App Store Connect → TestFlight tab → invite testers by email
- Testers install the **TestFlight app**, then your build
- Public link option for open beta

### Cost-zero dev path (Weeks 0–5)
- Use only the iOS Simulator (no device, no fee)
- Local notifications fire in simulator
- Camera in simulator gives placeholder images — use photo picker instead during dev

---

## File pointers

- **Spec (v3)**: `Phase 1 Spec.html` — canonical, read in browser
- **Design prototype**: `index.html` in design folder — interactive canvas, ＋ picker is tweakable
- **Handoff README**: original `README.md` from design package — the spec scope-down rules

---

## Open questions to resolve before Week 1

- [ ] Final product name (Noted? Handle? Something else?)
- [ ] Launch language (EN, 中文, or ES?)
- [ ] App icon direction (defer — serif "N" placeholder is fine for v1)
- [ ] Domain name (optional, ~$12/year — useful for landing page later)

---

*Last updated: 2026-05-30. Update this doc whenever architecture decisions change.*
