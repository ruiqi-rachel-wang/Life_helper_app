# Notie iOS — Build Plan & Architecture

> Canonical build reference. Living doc — update as decisions change.
> Companion docs: the Phase 1 Spec (HTML render) and design prototype.

---

## TL;DR

- **Language/Framework**: 100% Swift + SwiftUI (no Objective-C, no JS, no Python)
- **Stack**: SwiftData (local storage) · Apple Vision (on-device OCR) · GPT-4o-mini via Cloudflare Worker proxy · UNUserNotificationCenter (local notifications)
- **Architecture**: Clean layered — `Core/` (zero platform imports, future Android-portable) + `Platform/` (iOS adapters) + `Features/` (SwiftUI views) + `Shared/` (design tokens, components)
- **Timeline**: 8 weeks to TestFlight (scoped down from spec's 12-week ambition)
- **Cost**: ~$8–15/month at first 1,000 users · ~$0.0004 per scan
- **One metric that matters**: % of confirmed action items marked done before due date. >50% working, <30% broken loop.

---

## Current progress (as of 2026-05-30)

**Week 0 — Setup** ✓ mostly complete (pending: OpenAI key, product name, launch language)
**Week 1 — SwiftUI shell** ⏳ in progress (Inbox built; Guides/Create/Settings are stubs; Detail + Review not yet created; navigation not wired)

What's running today: tap-through tab bar where Inbox shows 4 sections with 5 mock items, masthead with live date, and privacy banner. Cmd+R works in the simulator.

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

```
Notie/
├── App/
│   └── NotieApp.swift                  ← @main entry point
│
├── Core/                                ← "Backend" — pure logic, ZERO UIKit/SwiftUI imports
│   ├── Models/
│   │   ├── ActionItem.swift             ← Codable struct
│   │   ├── Step.swift
│   │   ├── Recurrence.swift             ← unit + interval + nextDate() math
│   │   ├── WorkflowState.swift          ← .todo / .inProgress / .deferred / .done
│   │   ├── Source.swift                 ← .scanned / .guide / .custom
│   │   └── ExtractionResult.swift       ← THE critical shared type
│   ├── Protocols/                       ← interfaces Android reimplements
│   │   ├── StorageProtocol.swift
│   │   ├── NotificationProtocol.swift
│   │   └── LLMClientProtocol.swift
│   ├── Services/
│   │   ├── ExtractionService.swift      ← orchestrates OCR → parse → (LLM) → merge
│   │   ├── RuleBasedParser.swift        ← regex: amount, date, account#
│   │   ├── RecurringService.swift       ← creates next cycle on mark-done
│   │   └── GuideTemplateService.swift   ← returns 5 static checklists
│   └── Repositories/
│       └── ActionItemRepository.swift   ← talks to StorageProtocol
│
├── Platform/                            ← iOS-specific implementations of Core protocols
│   ├── SwiftDataStorage.swift           ← implements StorageProtocol
│   ├── UNNotificationService.swift      ← implements NotificationProtocol
│   ├── VisionOCREngine.swift            ← Apple Vision wrapper
│   └── OpenAIClient.swift               ← implements LLMClientProtocol (HTTPS → Worker)
│
├── Features/                            ← SwiftUI views + ViewModels (one folder per screen)
│   ├── Inbox/
│   ├── Review/                          ← the hero screen
│   ├── Detail/
│   ├── Guides/
│   ├── Create/
│   └── Settings/
│
├── Theme/                                ← colors, fonts — the app's visual identity
│   ├── Color+Notie.swift                 ← all tokens from spec
│   └── Font+Notie.swift                  ← New York + SF Pro + SF Mono scale
├── Components/                           ← reusable views used by many screens
│   ├── SourceTagView.swift
│   ├── StatCardView.swift
│   ├── StepRowView.swift
│   └── EyebrowText.swift
│
└── NotieTests/                          ← XCTest unit tests
    ├── CoreTests/
    │   ├── RuleBasedParserTests.swift
    │   ├── RecurrenceTests.swift
    │   └── ExtractionServiceTests.swift
    └── UITests/
        └── InboxUITests.swift
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

Reuse: `Core/Models/`, `Core/Services/`, `Core/Protocols/`, `Core/Repositories/` (port Swift → Kotlin, same structure)
Rewrite: `Platform/` (Room, WorkManager, ML Kit OCR) + `Features/` (Jetpack Compose)
Keep identical: prompts to LLM, ExtractionResult shape, design tokens

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

### Week 1: SwiftUI shell with fake data
- [x] Tab bar: Inbox · Guides · ＋ · Settings
- [ ] 5 screen views with hardcoded mock data — **Inbox done (4 sections, 5 items, masthead, privacy banner); Guides / Create / Settings are stubs; Detail + Review not yet created**
- [ ] Reusable components — `SourceTag` enum done; `InboxRow` / `InboxSection` / `InboxRowDivider` / `PrivacyBanner` built inline in InboxView (extract when reused); `StatCardView`, `StepRowView`, `EyebrowText` not yet built
- [ ] Navigation: inbox row → Detail, ＋ → Create sheet, Guide → Detail

**Done when:** every screen renders matching prototype within ~10%. All navigation works. No real data anywhere.

### Week 2: SwiftData + Create flow (first real persistence)
- SwiftData models: ActionItem, Step
- StorageProtocol + SwiftDataStorage
- ActionItemRepository (only thing ViewModels touch)
- InboxViewModel reads from repo (delete mocks)
- CreateView saves real items (title, due date, optional notes, optional steps)
- First XCTest: ActionItemRepositoryTests, RecurrenceTests

**Done when:** Create form saves; force-quit + reopen → item still there. Cmd+U runs tests, they pass.

### Week 3: Notifications + workflow states
- Request notification permission (graceful degradation if denied)
- NotificationProtocol + UNNotificationService
- Schedule on save: 3d before, 1d before, due day, +1 morning after overdue
- Cancel reminders on done
- State transitions in Detail's segmented control
- `isOverdue` derived state + red styling

**Done when:** notification fires on a real schedule. Mark done cancels future reminders. Overdue items render red.

### Week 4: Camera + Apple Vision OCR
- Camera UI (UIImagePickerController in SwiftUI, or AVFoundation)
- Photo picker (native SwiftUI `PhotosPicker`)
- VisionOCREngine using `VNRecognizeTextRequest`
- Debug screen showing raw OCR text

**Done when:** scan a real bill → see extracted text. Works for ~80% of typical printed mail.

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
- Guides tab: tap → instant ActionItem with source `.guide`
- RecurringService: on mark-done with repeats, create next cycle with advanced due date
- Pull `repeats` from LLM (don't hardcode)

**Done when:** guide → checklist in 1 tap. Recurring bill marked done → next cycle exists with correct cadence.

### Week 8: Polish + TestFlight
1. Empty states (no inbox, no past items, OCR failed)
2. Error states (LLM down, OCR garbled, no network)
3. Settings: language picker, "keep original scans" toggle, version
4. Privacy banner on Inbox: `LOCAL OCR · NO BANK LINK · NO AUTOPAY`
5. Past items list (Done archive, no search)
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
