# Cuevi iOS — Build Plan & Architecture

> Canonical build reference. Living doc — update as decisions change.
> Companion docs: the Phase 1 Spec (HTML render), design prototype, and
> **`future_features.md`** (deferred / post-TestFlight features — accounts &
> family sharing, configurable reminder time, …). NOTE: multi-page scan and
> first-launch onboarding are now BUILT (2026-06-18), despite older "deferred" notes.

**Changed 2026-06-19 (renamed to Cuevi — FULL rename):**
- **The whole project is now "Cuevi"** (history: Notie → briefly Plaino → Cuevi). Unlike
  the earlier Plaino pass, this rename is COMPLETE, including the internal Xcode labels:
  the project (`Cuevi.xcodeproj`), **target / scheme / Swift module** (`Cuevi`), test
  targets (`CueviTests` / `CueviUITests`), the source folders (`Cuevi/Cuevi/`, …), bundle
  IDs (`com.rachelwang.Cuevi`), display name, every in-app string + String Catalog
  (en/zh/es), the `@main` struct (`CueviApp`), Theme files (`Color+Cuevi.swift`,
  `Font+Cuevi.swift`), legal docs, and the Cloudflare Worker (`cuevi-ai`). Build commands
  are now `-project Cuevi/Cuevi.xcodeproj -scheme Cuevi`; tests `@testable import Cuevi`.
  Only the **outer working-dir folder `notie_life_helper_app/` is unchanged** (local
  container; the GitHub repo stays `Life_helper_app`).
- **App icon** is a placeholder (three-bar mark on cream) — replace with a real exported
  PNG at `Cuevi/Cuevi/Assets.xcassets/AppIcon.appiconset/icon-1024.png`. (The generator
  script was removed.)
- **Legal depersonalized + in-app**: no personal name/email; contact is a placeholder role
  address `support@cuevi.app` (set up a real inbox before publishing). Privacy/Terms now
  render **in-app** (`LegalContent` + `LegalDocumentView`); the unused `LegalConfig` was deleted.
- **Guide content localization (started):** sensitive guides translate on-device via the
  String Catalog (`ExtractionResult.localized()`), no AI. Done: **bank account, taxes**.
  Remaining guides + richer step detail are in progress.

**Changed 2026-06-18 (legal/privacy for free release):**
- **New `legal/` folder** with drafts: `privacy-policy.md`, `terms-of-service.md`
  (liability + AI disclaimers), `app-store-privacy-label.md` (App Store Connect
  nutrition-label answers), and a `README.md` with hosting + placeholder steps.
- **Disclaimers wired into the app**: `LegalConfig.swift` (privacy/terms URLs +
  contact) → a new **Profile → About & Legal** card (Privacy Policy, Terms,
  always-visible "informational only / AI can be wrong" disclaimer, app version).
- **AI-accuracy disclaimer on every Review result** (scan + guide), under the
  Add/Done button. See the legal section below for the remaining submit-time TODOs
  (fill placeholders, host the policy URL, paste the label answers).

**Changed 2026-06-18 (QA-report fixes):**
- **Cloudflare Worker proxy implemented** (`cloudflare-worker/` + `BackendConfig.swift`).
  `OpenAIClient` now calls `BackendConfig.chatEndpoint`: the Worker when `workerURL`
  is set (no key on the phone), else OpenAI direct with the dev key (simulator only).
  Deploy + set `workerURL` + rotate the old key before TestFlight (see the folder's README).
- **Overdue nudges → ONE repeating daily 9am reminder** (`ReminderScheduler`, key
  `|odDaily`) that truly repeats "until done" (no 14-day cap), plus `refreshAllReminders()`
  on launch/foreground so an item that becomes overdue while away starts nudging.
  Replaces the old fixed list of 14 one-shots (`overdueNudgeDates`, removed).
- **Recurrence correctness**: month-based cadences anchor to the original day-of-month
  (`recurrenceAnchorDay`) so they don't drift after a short month (Jan 31 → Feb 28 →
  *Mar 31*). Spawned occurrences no longer copy period-specific facts (amount/summary/
  notes). Utility docs are no longer force-defaulted to monthly — the AI's cadence wins.
- **Deadline + timezone**: a model-computed relative deadline ("within 90 days") is no
  longer overwritten by a raw date the regex found on the page; timed events can carry a
  UTC offset (`2026-06-25T08:05-04:00`) so flight reminders fire correctly across timezones.
- **Scan quota** is charged only AFTER a successful API response (a network failure no
  longer burns a scan). Prompt adds the `auto` category (9 total) and pushes full
  root-cause step sequences (e.g. ticket → pay AND renew registration AND get sticker).
- **Multi-page**: ordered photo selection, a partial-load warning, and all pages are
  retained (stacked into one stored image), not just the first.
- **Localization**: app chrome localized (To-Do rename, scan/Review messages, photo
  tiles, guide titles/subtitles/questions/options) + first-launch notification primer.

**Earlier (2026-06-16):**
- **AI model → `gpt-4o` for extraction** (guide polish stays `gpt-4o-mini`): extraction
  needs real reasoning; polish only rewords. ~$0.003–0.006/scan, affordable because
  scans are rate-limited.
- **Scan rate limit** (`ScanQuota`): 10/day, 50/month per device. Gated in the Add flow.
- **Extraction prompt reworked** for: lead-with-the-reason summaries, *actionable*
  IDs (ticket/summons # over VIN/plate), specific action links *in the step*, and
  root-cause + conditional steps (fix the cause AND handle the notice).

---

## TL;DR

- **Language/Framework**: 100% Swift + SwiftUI (no Objective-C, no JS, no Python)
- **Stack**: SwiftData (local storage) · Apple Vision (on-device OCR) · GPT-4o (extraction) + GPT-4o-mini (guide polish) via Cloudflare Worker proxy · UNUserNotificationCenter (local notifications)
- **Architecture**: Plain-English folders — `App/` (entry + tab shell) · `Model/` (data: `ActionItem` is a SwiftData `@Model`, plus pure logic like bucketing/reminder math — UI-free, no `Color`/screen types) · `Screens/` (SwiftUI views) · `Theme/` (color/symbol + formatting) · `Notifications/` (UNUserNotificationCenter wrapper). The model uses SwiftData (iOS), but its *logic* (enums, derived state, grouping) is what ports to Android; the view layer owns all presentation.
- **Timeline**: ~10 weeks to TestFlight (Week 0–9: core + guides + release buffer; revised 2026-06-13)
- **Cost**: ~$8–15/month at first 1,000 users · ~$0.0004 per scan
- **One metric that matters**: % of confirmed action items marked done before due date. >50% working, <30% broken loop.

---

## Current status (2026-06-13)

| Weeks | Status |
|---|---|
| 0 Setup · 1 Shell · 2 Persistence · 3 Notifications · 4 Camera+OCR | ✓ complete |
| 5 Rule parser + OpenAI extraction | ✓ complete (2026-06-06) |
| 6 Review spine (scan → AI → edit → Add) | ✓ complete (2026-06-10) — **the shippable moment** |
| 7 Adaptive guides | ✓ complete (2026-06-15) — 11 guides, Step Detail, saved fields, glossary |
| 8 Recurring + release polish | ⏳ in progress — recurring ✓, done-archive/reopen ✓, Profile tab + language wiring ✓ (2026-06-15); polish states, metrics, guide follow-ups next |
| 9 TestFlight launch | pending |

**Working end-to-end today:** scan/upload → on-device OCR (`VisionOCR`) → AI
extraction (`RuleBasedParser` + GPT-4o, one or many items per doc) → one
combined editable **Review** → saved as a rich `ActionItem` → **Inbox** (urgency
sections, sorted by due date) → **Detail** (steps, IDs, fully-editable reminders,
notes). Persistence (SwiftData), notifications (time-based + per-reminder
editable), Mark done / Delete / edit all persist. ~95 unit tests pass; builds
clean (no warnings); iOS 17 target. Backed up on GitHub
(`ruiqi-rachel-wang/Life_helper_app`, `main`).

**Built since (now done):** adaptive guides (11, with Step Detail + glossary),
recurring (`repeats` → `Recurrence`, recurring-aware delete, drift-free anchoring),
multi-page scan, first-launch notification onboarding, and the Cloudflare Worker
proxy (deploy + set `BackendConfig.workerURL` before TestFlight). Profile's
notification row deep-links to iOS Settings.

**Still open for TestFlight:** deploy the Worker + rotate the dev key; legal/privacy
is **drafted** (`legal/` + in-app disclaimers) — still needs placeholders filled, the
policy hosted at a public URL, and the privacy-label answers entered in App Store
Connect (see the Legal section); finish guide *step-body* localization for non-English
(chrome is localized; sensitive-guide bodies still need a careful, reviewed approach —
see Localization below); the custom raised ＋ tab button (optional). Sample items are
seeded on first launch for testing; grep `TEMP:` in code for remaining scaffolding.

---

## Why this tech stack

| Question | Answer |
|---|---|
| Why Swift, not React Native? | Apple Vision OCR is the entire core pipeline; native is faster and simpler than a bridge. The editorial design uses New York/SF Pro — free and gorgeous in SwiftUI. iOS-first is explicit in the spec. |
| Why SwiftUI, not UIKit? | Modern, declarative, matches the prototype's component style. Faster iteration via Previews. Apple's blessed path for new apps. |
| Why GPT-4o (not 4o-mini) for extraction? | Extraction needs real reasoning — explain *why* a notice was issued, find the root cause, give the full fix. 4o-mini is used for the lighter guide-polish rewrite. Swap either via the `Extractor` protocol. |
| Why a Cloudflare Worker proxy? | Embedding the OpenAI key in the app means anyone can extract it from the binary and burn your account. Worker holds the key, rate-limits per IP, free tier covers 100K req/day. |
| Why no backend database? | Phase 1 is local-only per spec. No login, no sync, no servers — all data in SwiftData on device. |
| Why no vision/multimodal AI? | Cut from Phase 1. Text-only LLM is ~10× cheaper. If OCR is too poor, prompt user to re-shoot. |

---

## Architecture

Folders are plain-English and created only when they have content (grow
incrementally). Today's layout:

```
Cuevi/Cuevi/
├── App/                      ← entry point + app shell
│   ├── CueviApp.swift        ← @main; launches RootTabView
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
│   ├── Color+Cuevi.swift     ← all color tokens
│   └── Font+Cuevi.swift      ← serif / sans / mono scale
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

### Bilingual term toggle (future — decided 2026-06-09)

For bilingual users, the AI explanation is in their language (e.g. 中文), but the
real world (a website form, a clerk) uses the **English** term. Example: the
summary says "确认码" but the airline site asks for the "Confirmation code" — the
user won't know what to look for. So on the Detail/Review page, **tapping certain
words/labels reveals the English original; tapping again toggles back.** Applies
to field labels and key terms (confirmation code, policy number, "storage
facility", etc.). Needs the extraction to keep both the translated text AND the
English term (e.g. each `DocID`/label could carry an `english` variant, or a
parallel English extraction). Not Phase-1-core; a strong accessibility win for
the ESL target. Builds on the single-language setup — this is the "show the
English when you need it" escape hatch, not a full live re-translate.

### CueviTests/ (auto-created with the project)

```
CueviTests/        RecurrenceTests, RuleBasedParserTests, …   (Wk 2+)
CueviUITests/      basic tap-through (auto-generated)
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
| 5 guides with AI customization | **Adaptive hybrid guides** (changed 2026-06-05; shipped Week 7, expanded after): hardcoded questions + base checklist, light AI polish on non-sensitive guides only. **11 guides**: moving, bank, taxes, new job, SSN/ITIN, driver's license, USCIS paperwork, school enrollment, health insurance, doctor's appointment, car accident. New `auto` category for car accident. |
| Recurring monthly + yearly hardcoded | Cadence read from the document by AI (any interval) |
| Overdue follow-up daily up to 7 days | One overdue reminder the next morning |
| Vision-AI fallback for bad OCR | No vision model. Re-shoot the photo. |
| Draft reply / phone-call scripts | Cut entirely |

**Hard NO list for Phase 1:** login · cloud sync · family sharing · password manager · backend DB · provider DB · bank linking · autopay · email forwarding · chatbot · voice · Android · analytics dashboard

---

## Build order — ~10 weeks (Week 0–9: core + guides + release buffer)

### Week 0: Setup (NOT code)
- [x] Install Xcode (free, ~15GB)
- [ ] Apple Developer account — **deferred until Week 6 (intentional)**
- [x] Sign in to Xcode with free Apple ID → "Personal Team"
- [x] Create OpenAI account, generate API key, set $20/mo spending cap
- [x] Create Cuevi Xcode project (SwiftUI, Swift, Storage: None, Tests: ✓)
- [x] Set up folder structure (flat for now — grow incrementally as features need them)
- [x] Write design tokens (Color+Cuevi.swift, Font+Cuevi.swift)
- [ ] Pick product name (test "Noted" vs "Handle" with 5 target users)
- [ ] Pick launch language (EN, 中文, or ES)

**Done when:** Xcode signed in, "Hello World" running in simulator, design tokens compile. ✓

### Week 1: SwiftUI shell with fake data ✓ COMPLETE
- [x] Tab bar: Inbox · Guides · ＋ · Settings
- [x] All 5 screens built (Inbox, Guides, Detail, Review, Create) + Settings stub
- [x] Reusable row/section/tile components (built per-screen; extract further when reused)
- [x] Navigation: inbox row → Detail, guide → Detail, ＋ Scan/Upload → Review
- [ ] *Polish deferred:* raised ＋ tab button (floating circle) → Week 8

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
  recurring-aware confirm dialog lands with recurrence in **Week 8**; Week 2
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

### Week 5: Parser + OpenAI extraction ✓ DONE (2026-06-06)

`ExtractionResult` (the shared type) + minimal `Recurrence` enum; `RuleBasedParser`
(regex amount/currency/date/account, cue-aware dates that handle appointments /
expiries / departures, not just bills); `Extractor` protocol → `OpenAIClient`
(GPT-4o-mini, JSON mode) + `MockExtractor`; `ExtractionService` runs the parser
then the LLM and **merges** (parser wins on exact amount/date/account; skips the
LLM only on empty OCR). Tolerant JSON parsing (handles `"confidence":"high"`,
category-as-array) + a category synonym map. Tuning corpus in `sample_documents.md`.

**API key (DECIDED 2026-06-06):** dev calls OpenAI directly with the key in a
**gitignored `AI/APIKeys.swift`** — **never commit it.** Before TestFlight the
call moves behind a free **Cloudflare Worker** so the key never ships (a one-line
swap, thanks to the `Extractor` protocol) — see Week 9. The Worker is $0 (free
tier covers it); the only real cost is OpenAI (~$0.0004/scan).

### Week 6: Review screen end-to-end (THE SPINE) ✓ DONE (2026-06-10)

One combined editable **ReviewView** after every capture: OCR → AI extraction →
editable card (title · summary · type/sender · amount + due date/time · steps ·
notes · details/IDs · tappable links; low-confidence fields underlined) → **Add
to inbox** saves a rich `ActionItem` + schedules reminders. Replaced the old
read-only ScanResultView and the mock Review.

- **Rich detail persisted:** `ActionItem` gained `title`, `summary`, `sender`,
  `documentType`, `otherIDs`, `notes`, `siteURL`, `dueHasTime`, `source` (+ the
  `ActionItem(from:)` mapping). `confidence`/`lowConfidenceFields` stay transient.
- **Detail page** redesigned to match Review: tag · title · chips → steps →
  details → reminders → notes.
- **Reminders fully editable** — stored `reminders` list (add / remove / retime
  each), with a smart-default fallback: bills 3d/1d/due-day @9am; timed events a
  day-before heads-up + N hours before the exact time (default lead by type,
  editable). Scheduler fires the effective list.
- **Multi-item docs** → multiple items: extractor returns `[ExtractionResult]`,
  Review shows an "N things found" selectable list, each added as its own item
  (fixed the appointment-list that used to drop events).
- **No-action docs** (no steps + no due) → show summary + **Done**, no inbox item
  (inbox stays action-only).
- **Unreadable / low-confidence** → a "retake the photo" state, not a fake item.
- **Inbox**: subtitle is amount + date only; sections sorted by due date.

~95 unit tests pass. **The shippable moment** — everything after is polish + breadth.

### Week 7: Adaptive guides

Goal: tap a guide → answer a few hardcoded questions → a tailored checklist (your
answers filled in) → the **same Review screen** scans use → Add to inbox (tagged
"Guide"). A guide never opens a Detail directly.

**Decisions (2026-06-13; updated 2026-06-14):**
- **Deterministic structure + MINIMAL AI polish.** Questions pick a hardcoded branch
  and fill answers into the steps via templates. A best-effort GPT-4o-mini pass then
  lightly rewords — it only reorganizes/clarifies, must NOT invent new advice, can
  only APPEND notes (never replace), and is rejected if it changes the step count.
  AI never decides the checklist shape; offline → the templated checklist.
- **Sensitive guides skip AI entirely.** Each guide carries a `risk` level; the
  `.sensitive` ones (immigration, banking, medical, car accident) are built fully
  on-device and never sent to the polish pass (shown via a small "stays on your
  device" badge on the questions page).
- **Required answers, no assumed defaults.** Choice/state questions must be answered
  before "Build my checklist" (we never seed the first option — assuming e.g. "no
  injuries" was unsafe). Text questions stay optional.
- **Framework + guides:** shipped with 7 this week, since expanded to **11**:
  Moving, Bank account, Taxes, New job, SSN/ITIN, Driver's license, USCIS paperwork
  (renamed from "Green card / visa"), School enrollment, Health insurance, Doctor's
  appointment, and Car accident (now in the new `auto` category).

**Build:**
1. **Reuse Review for prefilled content.** Refactor `ReviewView` to be
   source-agnostic: take an async `load: () async throws -> [ExtractionResult]`
   producer + optional `image` + `source`. Scans pass OCR→extract; guides pass
   build→polish. Hide the photo/OCR UI when there's no image. One confirm screen
   for both (per the architecture).
2. **Guide model + branching.** Expand `Guide` with `questions: [GuideQuestion]`
   (per-question `choice` / `text` / `state` kinds; hardcoded) and a pure
   `build(answers:) -> ExtractionResult` (pick a base checklist, fill answers via
   templates like `{state}`/`{employer}`, set title/category, optional due/repeat
   hints). Deterministic → unit-tested. Also carries `officialSource`, `lastReviewed`,
   and `risk` provenance metadata (stamped in `Guide.all`).
3. **AI polish pass.** `OpenAIClient.polish(_:context:language:)` (reuses the key)
   takes the base result + answers → lightly reworded steps only (never adds notes);
   best-effort with fallback, and SKIPPED for `.sensitive` guides. Runs as a Review
   phase ("Personalizing…") using the existing loading UI.
4. **Questions screen.** Tap guide → a single scrollable form of its questions →
   Continue builds the base result and pushes Review (which runs the polish).
   Back/cancel saves nothing.
5. **Author content** for the launch guides (questions, branches, templated
   checklists, safety notes, official links where appropriate). Save items with
   `source = .guide` (shows the guide tag). Started at 7; now 11.

**Step Detail (decided 2026-06-13, guides only for now):** the main checklist
shows MILESTONES; tapping a step with detail opens a Step Detail sheet
(explanation · one-level mini-checklist · what you'll need · what to say · links).
`ChecklistStep` gained an optional `StepDetail`; guides author it on heavy steps
(e.g. Moving's "set up utilities/internet"); scans leave it nil. Rule: one level
only (flat mini-checklist, no nesting). AI may reword but must not invent live
facts (provider names/availability).

**Shipped 2026-06-14 (was deferred):**
- **Editable "fields to save"** — `StepDetail.fields: [SavedField]`. Values editable
  inline even in read mode; labels add/removable in edit mode; tolerant decoder so
  older saved steps still load. Authored on car-accident claim, USCIS case status,
  doctor booking, moving internet; users can add fields to any step.
- **Plain-English glossary** — `Glossary` auto-detects jargon (I-9, ITIN, EAD,
  N-400, deductible, in-network, etc.) in a step's own text and shows a "What these
  mean" card. Applies to scanned docs too.

**Done when:** every guide can be answered → tailored checklist in Review → edit
if needed → Add → saved in the Inbox tagged "Guide", survives force-quit, with
editable steps/reminders and tap-through Step Detail. AI-offline still produces
the templated checklist.

### Week 8: Recurring + release polish

Goal: make completed tasks, recurrence, settings, and edge states feel coherent
before handing the app to testers.

1. **Recurring tasks** — ✓ DONE (2026-06-15)
   - `ActionItem.recurrence: Recurrence?` (replaced the old `repeatsMonthly` Bool);
     `ExtractionResult.repeats` now carries straight onto the item. SwiftData
     round-trip verified (the `everyNDays` associated value persists).
   - `Recurrence.nextDate(after:)` + `ActionItem.makeNextOccurrence()` (pure):
     advances the due date by the cadence, resets all step checks + status, resets
     reminders to defaults, carries the rich detail over. Unit-tested.
   - Mark-done (Detail **and** the notification "Mark done" action) spawns the next
     cycle and schedules its reminders; the completed instance stays in Done.
   - Recurring-aware delete: a live recurring item asks "Delete just this one"
     (keeps the series going at the next date) vs "Delete this and all future"
     (stops it). One-off / done items get the plain confirm.
   - Detail shows a **REPEATS** row (read: the cadence; edit: a None/Monthly/Yearly
     menu) so recurrence is settable by hand, not just from a scan.
   - **QA fixes (2026-06-15):** mark-done is now idempotent (guards `status != .done`
     on both the Detail and notification paths) so a stale delivered notification
     can't double-complete / double-spawn. The "delete just this one vs. all future"
     split is only offered when the item is recurring **and** dated (`canSplitRecurring`)
     — a no-due-date recurring item can't advance, so it gets a plain delete instead
     of a misleading split. *Deferred (post-launch):* the REPEATS menu still can't
     re-pick an AI-read `everyNDays(n)` cadence (shows the label, edits only
     None/Monthly/Yearly).
2. **Done archive + reopen** — reopen ✓ DONE (2026-06-15)
   - Done items stay visible in a past/done area, with delete. ✓ (Inbox Done section)
   - **Reopen ✓** — a done item's Detail now shows "Mark as not done" (→ active,
     reminders rescheduled) above Delete. The Inbox re-buckets it by urgency
     (part-checked → in progress). Unit-tested. Delete stays final, no undo.
     *Edge case:* reopening a recurring item that already spawned its next cycle
     leaves both (distinguishable by due date) — acceptable; no parent-link yet.
   - **Reminder notification text ✓ DONE (2026-06-15):** `reminders` is now a list
     of `ReminderItem` (date + optional note) instead of bare `[Date]`. Each
     reminder has an editable note on Detail; the scheduler shows the note verbatim
     in the banner when set, else falls back to the auto body ("Due in 3 days").
     Defaults carry no note. SwiftData round-trip verified. (Guides default to NO
     reminders — no due date — which is correct.)
3. **Profile tab (replaces Settings)** — ✓ DONE (2026-06-15)
   - Tab renamed Settings → **Profile** (person icon); `AppRouter.Tab.settings`
     → `.profile`; `SettingsView` → `ProfileView`.
   - Layout: Guest profile header · **Language** picker on top · coming-soon
     **Account** rows (Sign in / Family sharing / Cuevi Plus, "SOON" chips) ·
     a **Notifications** row that shows the current permission status and taps
     through to iOS Settings (added 2026-06-18) · DEBUG test reminder in its own
     labeled block. (There is NO keep-original-scans toggle — that earlier note
     was never built; scans always store their photo.)
   - **Language is WIRED:** `@AppStorage(ExplainLanguage.storageKey)`, resolved via
     `ExplainLanguage.resolve(stored:)` (empty/unknown → `deviceDefault` from the
     locale, else the user's override). Threaded into the **scan** call
     (`CreateView` → `ExtractionService.extract(language:)`) and the **guide**
     call (`GuidesView` → `OpenAIClient.polish(language:)`). Picker shows each
     language in its own script (English / 中文 / Español).
     Unit-tested; Profile screen visually verified in the simulator.
     *Known limit:* sensitive guides skip the polish pass, so they stay English
     even when another language is picked (they never reach the translating AI).
     The Profile language hint now says this out loud (QA fix 2026-06-15) so it
     isn't a surprise.
   - **App UI now localized — CHANGED 2026-06-16 (was deferred):** Rachel pulled
     full UI localization into scope. The app **chrome follows the iPhone's
     language** (not the picker) via a String Catalog (`Localizable.xcstrings`,
     en/zh-Hans/es): tabs, Inbox + urgency sections, screen titles/eyebrows,
     buttons, empty/error states, privacy banner, notification text, recurrence &
     category labels, and relative-date/overdue strings (plural-correct). Computed
     labels use `String(localized:)`; section titles wrap in `LocalizedStringKey`.
     The Profile picker still independently controls the **AI output** language.
     *Remaining (follow-ups):* guide content (titles/subtitles/question prompts/
     step text) is still English — large content; for general guides the AI polish
     already translates the checklist steps. DEBUG strings intentionally untranslated.
   - **Scans always keep their photo** (all pages, stacked into one image). There is
     no keep-original-scans toggle — an earlier plan note described one, but it was
     never built; this entry is corrected (2026-06-18).
4. **Polish states** — partly done (2026-06-15)
   - Empty states: Inbox "Nothing yet" ✓. (Guides always list; "no result yet"
     is covered by Review's loading state.) Could still add a dedicated empty-Done
     hint — minor.
   - Error states: ✓ mostly — Review handles `.noText` ("couldn't read any text"),
     `.failed` (analysis/LLM/network error message), and a low-confidence "retake"
     state. Could make the offline case friendlier ("You're offline") — minor.
   - Privacy banner on Inbox: ✓ already shipped (`PrivacyBanner`).
   - **App icon placeholder ✓ DONE** — serif "N" on cream, opaque 1024² in
     `AppIcon.appiconset` (generated; Times serif). Replace with New York-rendered
     art later if desired.
   - **Custom raised ＋ tab button — TRIED & DROPPED (2026-06-15).** Built a
     centered floating ＋ over a custom bar; with only 4 destinations it left one
     side of the bar lighter and read as unbalanced. Reverted to the stock flat
     `TabView` bar, and **reordered tabs to Inbox · Add · Guides · Profile** (Add
     moved to 2nd). Revisit a FAB only if a balancing 5th destination appears.
5. **Local metrics** — local logging ✓ DONE (2026-06-15)
   - `Metrics` logs `confirmed` (on every user save: scan / guide / manual, with
     source) and `completed` (on mark-done, with on-time vs. late) to a local
     JSON file (`Model/Metrics.swift`). `MetricsSummary.from` reduces it to the
     completion rate + on-time rate + per-source breakdown (pure, unit-tested).
   - Viewer: Profile → DEBUG panel shows the numbers + Export (ShareLink) + Reset.
     Logging runs in all builds; only the viewer is DEBUG-gated.
   - **QA fix (2026-06-15):** events carry an `itemID`, and `MetricsSummary.from`
     runs the funnel **per confirmed item** — de-duping repeat completions (reopen →
     re-done, stale notification taps) and ignoring completions of items that were
     never confirmed (the seeded dev samples, which insert without a confirmed
     event). So completion/on-time rates can't be inflated by samples or doubles.
   - **Cross-tester roll-up — DECIDED 2026-06-15: TelemetryDeck, added before
     widening the beta.** Local-only shows each device only its own numbers, and
     asking testers to Export is impractical. Apple gives crashes + sessions via
     App Store Connect, but NOT custom events. Chose **TelemetryDeck** (privacy-
     first, no PII, free tier) over Firebase to protect the privacy positioning
     the ESL/immigrant audience depends on; Firebase only wins if Cuevi later goes
     cross-platform (Android + accounts), and a backend can carry analytics then.
     This consciously revisits the "no analytics dashboard" hard-NO.
   - **Integration is a ~10-min add, no lock-in:** every event already flows
     through the single `Metrics.record()` chokepoint — adding TelemetryDeck =
     the Swift package + one forwarding line there + the app ID from Rachel's
     (free) account. Not needed for the first ~10-person beta; local numbers
     suffice to sanity-check the loop. Wire it up when widening testers.
6. **Guides — follow-ups (updated 2026-06-14)**
   - ~~Editable "fields to save"~~ — **DONE** (`SavedField`, shipped 2026-06-14).
   - **Deeper source metadata — ✓ DONE (2026-06-15).** `GuideSource` (authority ·
     domain · official URL · `Jurisdiction` federal/per-state · real `lastReviewed`
     Date) replaces the free-text label; `risk` stays on `Guide` (it also drives
     the AI-skip and applies to source-less guides). Stamped on all 11 guides with
     stable root-domain URLs, and now **shown** as a tappable, dated citation
     footer on the guide's questions screen. Unit-tested (every guide has an
     https source; per-state guides flagged as such).
   - **Verify USCIS pages manually** — the canonical-looking USCIS URLs (uscis.gov/i-90,
     /n-400, /i-765, /file-online, case-status) could NOT be reliably fetched by the
     browser tool. Open each in a real browser and confirm before TestFlight.
   - **More step-detail breadth** — author detail on the remaining steps across
     all guides (currently the heavy ones have it).
   - **Per-state appointment deep-links** — today the DMV link is each state's
     official homepage; add verified "book appointment" deep-links for big states.
   - **UI tap-through tests — ✓ DONE (2026-06-15).** `CueviUITests`: `testTabsNavigate`
     (taps Add/Profile/Guides/Inbox, asserts each screen renders) and
     `testGuideFlowAddsItemToInbox` (Taxes guide → answer → Build → Review → Add →
     asserts the item lands in the Inbox). Uses a sensitive guide so it's
     network-free/deterministic; a `-uitest` launch flag skips the notification
     prompt so the system alert can't block automation. Both pass.
   - Bilingual term toggle (separate future note) ties in here.

**Done when:** recurring items regenerate correctly, done items can be reopened
or deleted, core empty/error states are visible, Profile has the launch controls,
and a release-style build has no obvious debug scaffolding in the main flow.

### Week 9: TestFlight launch

Goal: remove shipping blockers, archive the app, and get it into 10 real users'
hands.

1. **Security blocker: move the OpenAI key off-device**
   - Until now the key lives in gitignored `AI/APIKeys.swift`, which is fine on
     the Simulator but gets compiled into any shipped build.
   - Create a free Cloudflare Worker holding the key + per-IP rate limit.
   - Point `OpenAIClient.endpoint` at the Worker URL and remove the app-side
     OpenAI `Authorization` header.
   - Remove the real key from `APIKeys.swift`.
   - Verify the shipped build contains only the Worker URL, not the OpenAI key.
2. **SwiftData migration safety (surfaced 2026-06-15)**
   - In dev, changing a stored property's TYPE (e.g. `reminders: [Date]` →
     `[ReminderItem]`) is NOT a lightweight migration, so `try! ModelContainer`
     hard-crashes at launch on an old store (we just erase the simulator). Before
     real testers, either (a) freeze the schema, (b) add explicit `VersionedSchema`
     + `MigrationPlan`, or (c) make the container init resilient (recreate the
     store on failure). Decide before the first TestFlight build so a future schema
     change doesn't crash testers' installed app.
   - **Notification permission timing (QA finding 2026-06-15):** today the prompt
     fires at launch (`CueviApp` `.task`, skipped under `-uitest`). A tester sees it
     before understanding what reminders are, which can depress opt-in — and
     reminders are the core of the launch metric. Move the request to a contextual
     moment (e.g. first time a reminder is actually scheduled) before widening the
     beta.
3. **Apple release setup**
   - Apply for Apple Developer Program if not already approved (1–3 days).
   - Create App Store Connect app record.
   - Add app icon, bundle/version/build numbers, privacy answers, and tester
     notes.
4. **Archive + TestFlight**
   - Xcode → Product → Archive → Distribute App → App Store Connect.
   - Wait for Apple processing / automated review.
   - Add 10 testers in App Store Connect → TestFlight tab.
   - Recruit testers from target audience (immigrants, ESL families).
5. **Tester checklist**
   - Ask each tester to try: scan/upload, manual item, one guide, one reminder,
     mark done, reopen, delete.
   - Track the one launch metric: confirmed action items marked done before due
     date.

**Done when:** 10 real users have the build, the OpenAI key is not in the
binary, and the first tester feedback loop is running.

> **Timeline note (2026-06-13):** adaptive guides are real Phase-1 scope, so the
> endgame is split into Week 7 guides, Week 8 recurrence/polish, and Week 9
> TestFlight. This keeps the scan→review→done spine stable while giving guides
> and release hardening their own passes.

---

## Legal, privacy & business — before money or public launch

> **Not legal/tax advice** — talk to a lawyer/accountant, especially for the
> liability disclaimers (this app touches tax / immigration / insurance / medical /
> legal matters). Added 2026-06-16 at Rachel's request.

**You cannot charge during TestFlight** (beta is free), so none of this blocks the
first 10-user beta. It matters before a **paid** or **public** App Store launch.

### Required even for a FREE public/TestFlight release (we process personal data)
> **Drafted 2026-06-18** — see the new **`legal/`** folder. Documents are written and
> the disclaimers are wired into the app; the only remaining work is filling the
> `[BRACKETED]` placeholders, hosting the policy URL, and pasting the label answers
> into App Store Connect at submission. None of this blocks the free 10-user beta.

- **Privacy Policy** — ✓ DRAFTED (`legal/privacy-policy.md`). Discloses on-device OCR,
  that document **text is sent to OpenAI** via the Cloudflare Worker, sensitive guides
  staying on-device, local-only storage / no account, and CCPA/GDPR basics. **TODO
  before submit:** fill placeholders (`[YOUR NAME OR BUSINESS NAME]`), confirm the
  contact email, and **host it** for a public URL (GitHub Pages steps in
  `legal/README.md`). In-app links live in `LegalConfig.swift` → Profile → About & Legal.
- **App privacy "nutrition label"** — ✓ ANSWERS PREPARED (`legal/app-store-privacy-label.md`).
  Key call: text leaving the device = "data collected," so we declare **User Content
  (Photos + Other), App Functionality, Not linked, No tracking**; everything else Not
  Collected. **TODO:** enter in App Store Connect at submission; update if analytics/
  accounts are ever added.
- **Liability disclaimers — the BIGGEST risk for Cuevi** — ✓ DRAFTED (`legal/terms-of-service.md`)
  AND ✓ IN-APP. Terms cover "informational only — not legal/tax/immigration/financial/
  medical advice," no-warranty, and limitation of liability. In-app: a persistent
  disclaimer in **Profile → About & Legal**, the per-guide `referenceNote`, and the
  sensitive-guide on-device design. **TODO:** fill placeholders; have a professional
  review before a paid/public launch.
- **AI-accuracy disclaimer** — ✓ IN-APP (2026-06-18). Shown on **every Review result**
  (scan and guide), under the action button: "AI-generated — double-check important
  details against the original and the official source," plus the same point in Profile.

### Before charging money (subscription / paid)
- **Business entity** — an **LLC** separates personal liability (recommended given the
  domain); ~$50–500/yr by state. Sole prop is simpler but gives no liability shield.
- **Apple Paid Apps Agreement** in App Store Connect: accept it + add **banking & tax
  info** (W-9 for US) to receive payouts.
- **Use Apple In-App Purchase / subscriptions** for digital features — Apple takes 15%
  (Small Business Program, under $1M/yr) to 30%. You may **not** use outside payment for
  digital goods.
- **Terms of Service / EULA** (Apple ships a standard EULA; a custom one is better here).
- **Income tax** — app revenue is taxable; track OpenAI / Cloudflare / Apple fees as
  business expenses.

### Worth doing
- **Trademark check** on "Cuevi" (USPTO) before investing in the name; consider registering.
- **Security**: OpenAI key off-device (Week 9 Worker), per-IP rate-limit, never log PII.
- **E&O / liability insurance** once there's real usage/revenue.
- **COPPA** — not aimed at under-13s; keep it that way (no child accounts).

**Practical order:** privacy policy + disclaimers → ship the free TestFlight/App Store →
validate the one metric → **then** form the LLC + paid-apps setup when ready to charge.

---

## After Week 9

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
- Write `XCTestCase` subclasses in `CueviTests/`
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
- **Legal/privacy**: `legal/` — privacy policy, terms + disclaimers, App Store privacy-label answers, hosting steps (drafted 2026-06-18; in-app links via `LegalConfig.swift`)

---

## Still-open product decisions (not code-blocking)

- [x] Final product name — **Cuevi** (chosen 2026-06-19; sole proprietor: Ruiqi Wang, New York)
- [ ] Launch language default (EN / 中文 / ES) — Settings picker is Week 8
- [ ] App icon direction (serif "N" placeholder is fine for v1)
- [ ] Domain name (optional, ~$12/year — for a landing page later)

---

*Last updated: 2026-06-13. Update this doc whenever architecture decisions change.*
