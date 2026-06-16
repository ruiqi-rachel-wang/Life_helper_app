# Notie iOS — Build Plan & Architecture

> Canonical build reference. Living doc — update as decisions change.
> Companion docs: the Phase 1 Spec (HTML render) and design prototype.

---

## TL;DR

- **Language/Framework**: 100% Swift + SwiftUI (no Objective-C, no JS, no Python)
- **Stack**: SwiftData (local storage) · Apple Vision (on-device OCR) · GPT-4o-mini via Cloudflare Worker proxy · UNUserNotificationCenter (local notifications)
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
| 8 Recurring + release polish | ⏳ in progress — recurring tasks ✓ (2026-06-15); archive/reopen, Profile tab, polish, metrics next |
| 9 TestFlight launch | pending |

**Working end-to-end today:** scan/upload → on-device OCR (`VisionOCR`) → AI
extraction (`RuleBasedParser` + GPT-4o-mini, one or many items per doc) → one
combined editable **Review** → saved as a rich `ActionItem` → **Inbox** (urgency
sections, sorted by due date) → **Detail** (steps, IDs, fully-editable reminders,
notes). Persistence (SwiftData), notifications (time-based + per-reminder
editable), Mark done / Delete / edit all persist. ~95 unit tests pass; builds
clean (no warnings); iOS 17 target. Backed up on GitHub
(`ruiqi-rachel-wang/Life_helper_app`, `main`).

**Not built yet:** adaptive guides (still preview a Detail), recurring (the
`repeats` → `Recurrence` wiring + recurring-aware delete), Settings (mostly a
stub with a DEBUG test-reminder button), the Cloudflare Worker (key is local-only
for now — see Week 9), the custom raised ＋ tab button. Sample items are seeded on
first launch for testing; grep `TEMP:` in code for remaining scaffolding.

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
2. **Done archive + reopen**
   - Done items stay visible in a past/done area, with delete.
   - Add "Mark as not done" / Reopen from a done item's Detail; it should move
     back to active and reschedule reminders.
   - Keep delete final; no undo is required for delete.
   - **Reminder notification text (decided 2026-06-13, later dev):** each reminder
     should carry a short custom title/note that shows in the notification (today
     the body is auto-computed like "Due in 3 days"). Add an editable per-reminder
     label so the banner is meaningful. (Guides default to NO reminders — they have
     no due date — which is correct.)
3. **Profile tab (replaces Settings) — decided 2026-06-13**
   - Rename the 4th tab Settings → **Profile** (person icon). No accounts yet, but
     Profile is where future **account / family sharing / paid plan** features
     land — scaffold those as "coming soon" rows now so the structure is ready.
   - Layout: profile header (guest for now) · **Language** picker on top · then
     **Settings** nested below (keep-original-scans toggle, version/build row,
     DEBUG-only test reminder kept separate from release settings).
   - **Language must be WIRED, not just shown:** store the choice (e.g.
     `@AppStorage`), thread it into the scan + guide extraction calls (today they
     default to English), default to device language but overridable (per the
     Phase-1 decision). UI chrome stays English.
4. **Polish states**
   - Empty states: no inbox, no done items, no guides result yet.
   - Error states: OCR failed, garbled OCR, LLM down, no network, permission
     denied.
   - Privacy banner on Inbox: `LOCAL OCR · NO BANK LINK · NO AUTOPAY`.
   - Custom raised ＋ tab button.
   - App icon placeholder, even just serif "N" on cream.
5. **Local metrics**
   - Log `action_item_confirmed` and `action_item_completed` to a local JSON
     file or local-only store.
   - Keep this lightweight; the launch metric is more important than a full
     analytics system.
6. **Guides — follow-ups (updated 2026-06-14)**
   - ~~Editable "fields to save"~~ — **DONE** (`SavedField`, shipped 2026-06-14).
   - **Deeper source metadata** — `officialSource` is currently just a label string.
     Make it a structured record: official **URL**, **jurisdiction** (US / per-state),
     **risk**, and a real **last-reviewed date** per guide — so "super accurate" is
     auditable, not just displayed.
   - **Verify USCIS pages manually** — the canonical-looking USCIS URLs (uscis.gov/i-90,
     /n-400, /i-765, /file-online, case-status) could NOT be reliably fetched by the
     browser tool. Open each in a real browser and confirm before TestFlight.
   - **More step-detail breadth** — author detail on the remaining steps across
     all guides (currently the heavy ones have it).
   - **Per-state appointment deep-links** — today the DMV link is each state's
     official homepage; add verified "book appointment" deep-links for big states.
   - **UI tap-through tests** — Guides → answers → Review → Step Detail → Add →
     Inbox. All current coverage is logic-level only.
   - Bilingual term toggle (separate future note) ties in here.

**Done when:** recurring items regenerate correctly, done items can be reopened
or deleted, core empty/error states are visible, Settings has the launch controls,
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
2. **Apple release setup**
   - Apply for Apple Developer Program if not already approved (1–3 days).
   - Create App Store Connect app record.
   - Add app icon, bundle/version/build numbers, privacy answers, and tester
     notes.
3. **Archive + TestFlight**
   - Xcode → Product → Archive → Distribute App → App Store Connect.
   - Wait for Apple processing / automated review.
   - Add 10 testers in App Store Connect → TestFlight tab.
   - Recruit testers from target audience (immigrants, ESL families).
4. **Tester checklist**
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

## Still-open product decisions (not code-blocking)

- [ ] Final product name ("Notie"? something else?)
- [ ] Launch language default (EN / 中文 / ES) — Settings picker is Week 8
- [ ] App icon direction (serif "N" placeholder is fine for v1)
- [ ] Domain name (optional, ~$12/year — for a landing page later)

---

*Last updated: 2026-06-13. Update this doc whenever architecture decisions change.*
