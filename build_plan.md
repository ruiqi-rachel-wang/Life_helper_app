# Notie iOS — Build Plan & Architecture

> Canonical build reference. Living doc — update as decisions change.
> Companion docs: the Phase 1 Spec (HTML render) and design prototype.

---

## TL;DR

- **Language/Framework**: 100% Swift + SwiftUI (no Objective-C, no JS, no Python)
- **Stack**: SwiftData (local storage) · Apple Vision (on-device OCR) · GPT-4o-mini via Cloudflare Worker proxy · UNUserNotificationCenter (local notifications)
- **Architecture**: Plain-English folders — `App/` (entry + tab shell) · `Model/` (data: `ActionItem` is a SwiftData `@Model`, plus pure logic like bucketing/reminder math — UI-free, no `Color`/screen types) · `Screens/` (SwiftUI views) · `Theme/` (color/symbol + formatting) · `Notifications/` (UNUserNotificationCenter wrapper). The model uses SwiftData (iOS), but its *logic* (enums, derived state, grouping) is what ports to Android; the view layer owns all presentation.
- **Timeline**: ~10 weeks to TestFlight (8-week core + adaptive guides + buffer; revised 2026-06-05)
- **Cost**: ~$8–15/month at first 1,000 users · ~$0.0004 per scan
- **One metric that matters**: % of confirmed action items marked done before due date. >50% working, <30% broken loop.

---

## Current progress (as of 2026-05-30)

**Week 0 — Setup** ✓ complete (pending only: product name, launch language — not code-blocking)
**Week 1 — SwiftUI shell** ✓ complete
**Week 2 — Persistence** ✓ complete — SwiftData store; Inbox reads live (@Query) with a Done section; Detail binds to the live object so Mark done / Delete / edits write back; Create form saves (title-only valid) with optional due date, steps, and a text+photo note. Backed up on GitHub (`ruiqi-rachel-wang/Life_helper_app`, branch `main`).
**Week 3 — Notifications** ✓ complete — local reminders (3d/1d/due/overdue at 9am) scheduled on save, cancelled on done/delete, rescheduled on edit; interactive Mark done / Remind me later actions; tap a banner to open the item. 14 unit tests.
**Week 4 — Camera + OCR** ✓ complete — Apple Vision OCR on-device; Scan (camera) / Upload (Photos) → ScanResultView shows the real extracted text. (Test via Upload in the Simulator; camera needs a device.)
**Week 5 — Rule parser + OpenAI extraction** ✓ complete (2026-06-06) —
`ExtractionResult` + minimal `Recurrence`; `RuleBasedParser` (amount/currency/
date/account, cue-aware dates that handle appointments/expiries/departures, not
just bills); `Extractor` protocol + `OpenAIClient` (GPT-4o-mini, JSON mode, calls
OpenAI directly with the gitignored dev key) + `MockExtractor`; `ExtractionService`
(parser+LLM merge, parser wins on exact fields, skips LLM on empty OCR). Prompt
tuned against the real Week-4 samples + a live smoke test (~$0.0002/2 calls):
fixed dueDate-for-non-bills + travel→personal, and made JSON parsing tolerant
(the model returned `"confidence":"high"`). ~61 unit tests pass. Tuning corpus in
`sample_documents.md`. NOT wired into the Review UI yet — that's Week 6.
**Week 6 — Review screen end-to-end (the spine)** ✓ complete (2026-06-10) — one
combined editable Review screen (OCR→AI→edit→Add saves a rich ActionItem +
schedules reminders); Detail page redesigned to match; time-based reminders by
type (editable lead); unreadable→retake; multi-item documents → multiple items.
**This is the shippable moment.** Week 7 (adaptive guides + recurring) ⏳ next.

What's running today:
- All 5 screens + Settings. Tab bar; navigation wired; Inbox groups items by urgency with a Done section.
- **Persistence works:** Create / Scan-Review / edits / check-offs / Mark done / Delete all save (SwiftData) and survive a restart. `ActionItem` is a `@Model` (UI-free — no `Color`/screen types); the view layer (`Theme/ItemStyle.swift`) maps category → color/symbol and formats strings.
- **Notifications work:** reminders scheduled on save, cancelled on done/delete, rescheduled on edit; interactive Mark done / Remind me later; tap a banner to open the item. DEBUG test button in Settings.
- Interactive controls are `Button`s (accessible).
- 14 unit tests (isOverdue, doneCount, reminderSchedule, inbox bucketing, a SwiftData round-trip) pass via Cmd+U. Deployment target iOS 17.0. Builds clean, no warnings.

Still mock (see "Temporary scaffolding" below): scan/upload now runs **real on-device OCR** and shows the recognized text, but the **AI summary** that turns that text into fields (what it is · amount · due · steps) is still to come (Week 5–6) — so the scan screen stops at the text and does **not** open the old mock Review; sample items are seeded on first launch; guides preview a Detail instead of adding; recurring isn't built (Week 7).

---

## Temporary scaffolding — what's fake right now

Everything below is mock/placeholder and gets replaced on the noted week.
**In code, grep `TEMP:` to find each spot.** (Persistence + notifications are
real now — what remains fake is mostly the scan pipeline and recurring.)

| What | Where | Real version |
|---|---|---|
| Sample items seeded on first launch | `ActionItem.swift` sample block + Inbox `.task` | replaced by real data once scanning/onboarding exist; harmless seed for testing |
| ＋ Scan/Upload → real OCR text, but **no AI summary yet** (no Review hand-off) | `CreateView.swift` → `ScanResultView.swift` | Week 5–6 — text → AI extraction writes a plain-English summary + fills Review |
| Review screen is **parked**: mock Con Edison pre-fill, category fixed to `.other`, only reachable from its own `#Preview` until extraction exists | `ReviewView.swift` | Week 6 — opened from a real scan; fields + category from AI extraction |
| Guides → Detail with placeholder steps (should be Review → Add) | `GuidesView.swift` | Week 7 — real template steps, via Review → Add to inbox |
| Recurring not built (no cadence; done/delete don't respawn) | model `repeatsMonthly` unused | Week 7 — Recurrence + auto next-cycle + recurring-aware delete |
| Settings mostly a stub (has a DEBUG test-reminder button) | `SettingsView.swift` | Week 8 — language, reminder timing, privacy, export |
| Raised ＋ tab button (floating circle) | `RootTabView.swift` | Week 7 polish — custom tab bar |

Done since (no longer fake): `ActionItem` is a SwiftData `@Model`; the Inbox
reads the live store and buckets by urgency; Create form saves; Detail edits /
Mark done / Delete persist; Review "Add to inbox" saves; reminders schedule.

Note: guides are now **adaptive (hybrid)** in Phase 1 (decided 2026-06-05) —
hardcoded questions + base checklist, AI fills in details. Built in Week 7–8.

Scan pipeline — what the "summary" means: capture/upload → **on-device OCR**
(`VisionOCR`, done — downsamples first for speed, recognizes en/zh-Hans/es) →
**AI summary / extraction** (Week 5–6) turns the raw text into a short plain-
English summary — *what the document is, the amount, the due date, and the
steps to handle it* — which then pre-fills Review. The scan screen shows a
"What's next" placeholder for this today; the raw text is the real Week-4 output.

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
| 5 guides with AI customization | **Adaptive hybrid guides** (changed 2026-06-05, now in Phase 1): hardcoded questions + hardcoded base checklist, AI only fills in details. 5 starters + car accident. |
| Recurring monthly + yearly hardcoded | Cadence read from the document by AI (any interval) |
| Overdue follow-up daily up to 7 days | One overdue reminder the next morning |
| Vision-AI fallback for bad OCR | No vision model. Re-shoot the photo. |
| Draft reply / phone-call scripts | Cut entirely |

**Hard NO list for Phase 1:** login · cloud sync · family sharing · password manager · backend DB · provider DB · bank linking · autopay · email forwarding · chatbot · voice · Android · analytics dashboard

---

## Build order — ~10 weeks (8-week core + adaptive guides + buffer)

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
- `ExtractionResult` (the shared type, built first) + a **minimal `Recurrence`**
  enum (`monthly` / `yearly` / `everyNDays`). NOTE: `Recurrence` is NOT wired into
  `ActionItem` yet — that migration (off `repeatsMonthly: Bool`) waits for Week 7,
  when recurring behavior is actually built. Defining the enum now just keeps
  `ExtractionResult` stable.
- RuleBasedParser: regex for amount, currency, date, account number (free, exact)
- `Extractor` protocol → real `OpenAIClient` + a test mock both conform
- OpenAIClient (GPT-4o-mini, JSON mode) for summary / steps / category / repeats
- ExtractionService: parser first, then LLM; **merge** prefers the parser's exact
  regex for amount/date/account, takes summary/steps/category from the LLM.
  (Skips the LLM only on empty OCR — the broad "skip when parser is confident"
  optimization is deferred: steps/summary always need the model, so there's no
  real skip path yet. No dead branch.)
- Tune prompt with the 5 real OCR samples from Week 4
- Tests: RuleBasedParserTests (20+ cases), ExtractionServiceTests with the mock
  LLM (verifies merge precedence + empty-OCR skip — zero API cost)

**API key handling (DECIDED 2026-06-06):**
- **Week 5 dev calls OpenAI DIRECTLY** with Rachel's real key — fine because it
  runs on the Simulator only and nothing ships. `OpenAIClient` sits behind the
  `Extractor` protocol, so swapping "direct call" → "call the Worker" later is a
  one-line change.
- The key lives in a **gitignored `AI/APIKeys.swift`** (`APIKeys.swift` is already
  in `.gitignore`). **The key must NEVER be committed** — a leaked OpenAI key in a
  committed `.env` is exactly finding F1 in the JobDrop pre-deploy review; same
  failure mode, don't repeat it.

**Cloudflare Worker — deferred to pre-TestFlight (Week 6+), and it's free:**
- WHY a Worker at all: the app ships as a binary on strangers' phones; any key
  baked in can be extracted and used to run up your OpenAI bill. The Worker holds
  the key server-side so it never ships, and rate-limits per IP. Only matters once
  real users have the build — not during Simulator dev.
- COST: **$0**. Free tier = 100K requests/day; you'd use a few hundred at 1K
  users. You only leave free tier at 10M+ req/month, where the paid plan is a flat
  **$5/mo**. The only real per-scan cost is OpenAI itself (~$0.0004/scan): ~$0/mo
  at 10 testers, ~$2/mo at 1K users, ~$15–20/mo at 10K. See the Costs table.
- Setup is a ~30-min task slotted right before the first TestFlight build.

**Done when:** paste OCR text → get a valid `ExtractionResult` (amount, date,
sender, category, summary, steps, repeats); parser facts win on merge; empty OCR
skips the call; all unit tests green. All-in live-API test cost <$1.

### Week 6: Review screen end-to-end (THE SPINE)

The Week-5 engine exists + is tested; the scan screen shows it read-only. Week 6
turns that into the real, editable Review that saves and schedules. **This is the
shippable moment.**

**Decisions (2026-06-10):**
- **Combine the two screens into ONE.** Today there's a read-only AI card
  (`ScanResultView`) + an old mock editable `ReviewView`. Merge them into a single
  Review screen used after every capture (and later, guides). Retire the duplicates.
- **Single-item first, then multi-item** — multi-item reuses the same per-item card.
- **Keep the rich detail** — extend `ActionItem` so saved items carry the full
  extraction (not just title/amount/due), so the Detail page shows everything.

**Step 1 — One combined Review screen (single item). ✓ DONE (2026-06-10)**
(Merged ReviewView; OCR→extract→editable card→Add saves a rich ActionItem +
schedules reminders; no-action → Done; unreadable → retake. Detail page
redesigned to match. siteURL link surfaced; date/amount formatting unified.)
- New/merged `ReviewView(image:)`: runs OCR → `ExtractionService.extract` with a
  quiet progress shimmer on the captured photo (~3–5s), then renders the editable
  result using the card design (summary · type/sender · amount+due · steps · notes
  · DETAILS/IDs · tappable links).
- Inline editing (Edit/Done toggle): title, summary, amount, due **date + time**,
  category, steps (add/edit/remove), notes.
- Low-confidence fields (`lowConfidenceFields`) get an accent underline — no popup.
- "Add to inbox" → save the ActionItem + schedule reminders → land on Inbox.
- Needs a short **`title`** for the inbox row (e.g. "Con Edison electricity bill",
  "Flight to Chicago"): add a `title` field to the extraction/prompt (recommended)
  rather than deriving it.

**Step 2 — Extend `ActionItem` to keep the rich detail (SwiftData migration).**
- Add stored fields: `title`, `summary`, `documentType`, `sender`, `senderShort`,
  `dueHasTime`, `otherIDs` ([DocID] — make `DocID` Codable), `notes` ([String]),
  `siteURL`, plus a `sourceType` (scanned/guide/custom) for the source tag.
  (`amount`/`currency`/`dueDate`/`category`/`steps` already exist.)
- `repeats`: keep `repeatsMonthly` for now; full `Recurrence` wiring is Week 7.
- `confidence`/`lowConfidenceFields`: **transient** (Review-time only — for the
  underlines); NOT persisted.
- Adding optional fields with defaults = SwiftData lightweight (automatic)
  migration; existing seeded items still load.
- Write the explicit `ExtractionResult → ActionItem` mapping (no dropped fields);
  Detail page renders the new fields (IDs, links, notes).

**Step 3 — Time-based reminders (the `dueHasTime` payoff). ✓ DONE (2026-06-10)**
(Timed events: heads-up the day before @9am + a reminder `reminderLeadHours`
before the exact time, which fires at that time, not 9am. Smart default by type
(flight 3h, appointment 1h, else 2h), editable via a picker on Review + Detail.)
- When `dueHasTime == true` (flight, appointment), fire a few HOURS before the
  actual time, not 9am day-of. **Default lead time by type, user-editable:**
  appointment ~1h, flight ~2–3h, else a sensible default (from `category`/
  `documentType`). Extend `ReminderScheduler` (Week-3 it only does 3d/1d/due-day @9am).

**Step 4 — Unreadable / low-confidence → retake (not a fake item). ✓ DONE (2026-06-10)**
(Prompt pinned: gibberish → documentType "unknown" + confidence < 0.2; Review shows
a retake state for unreadable / low-confidence / no-text / failed.)
- Pin the prompt: if OCR is unreadable/meaningless → documentType "unknown",
  short summary saying so, steps [], confidence < 0.2; never invent. + a unit test.
- Review **consumes `confidence`**: very low (or "unknown") → show a "couldn't read
  this clearly — retake the photo?" state instead of a pre-filled Review. (The
  read-only bridge already shows a banner; Week 6 makes it a proper state.)

**Step 5 — Multi-item documents → multiple ActionItems. ✓ DONE (2026-06-10)**
(Extractor returns `[ExtractionResult]`; prompt returns `{"items":[…]}`; service
applies the regex merge only when there's one item; Review shows an "N things
found" selectable list → Add selected, each its own ActionItem + reminders.
Verified live: the Northwell list yields all 3 appointments, incl. the one that
used to drop.)
- A scan can hold SEVERAL events (appointment list, two deadlines, multi-line
  statement). One-item handling crams them into one item and **drops events** (the
  6/18 CT scan vanished in testing). Fix: extraction returns a LIST of items; the
  prompt returns an array; Review shows "this scan has N things — add them"
  (review/edit each, toggle which to add); each → its own ActionItem + reminders.
  Single item is just N = 1, so the Step-1 card is reused.

**No-action docs (decided 2026-06-10): show, then dismiss.** When a real document
has nothing to do (`steps: []` — a flyer, a paid receipt, a past itinerary),
Review shows the summary so the user understands it, with a **Done/dismiss**
button and **no "Add to inbox"** — the inbox stays action-only. (Docs that imply
an action — e.g. an interest charge → "set a reminder" — still have steps and are
added normally.) Heuristic: empty steps + no due date → treat as no-action.

**Done when:** photo → combined editable Review (AI-filled) → Add to Inbox → see
it, with reminders scheduled (timed events remind hours before). An appointment
list adds all N items. A garbled/blank scan → "retake" state, not a fake item.
**This is the shippable moment.** Everything after is polish + breadth.

### Week 7–8: Adaptive guides + recurring  (expanded — see timeline note)
- **Guides are adaptive, hybrid** (decided 2026-06-05, moved INTO Phase 1):
  - Each guide can ask **a few hardcoded questions** first (e.g. rent vs. buy,
    first-time vs. renewal, which state).
  - The answers pick a **hardcoded base checklist** (deterministic branching —
    no AI for structure).
  - **AI lightly adapts details only** — fills in the state name, employer,
    address, etc. into the steps (reuses the Week 5–6 OpenAI setup). Structure
    stays hardcoded; AI just personalizes wording.
- Topics: the 5 starters (Moving, Bank, Job, License, Visa) **+ car accident**,
  more added from real user requests.
- Flow: tap a guide → answer its questions → **Review-style "confirm before
  adding"** screen (same screen scans use) → **Add to inbox**. A guide never
  opens a Detail (it isn't a saved task yet).
- RecurringService: on mark-done with `repeats`, create next cycle (cadence from
  the document / guide, not hardcoded). Recurring-aware delete ("this one or
  future?").

**Done when:** answer a guide's questions → a tailored checklist with your
details filled in → Add to inbox. Recurring item respawns on the right date.

> **Timeline note (2026-06-05):** adaptive guides are real scope — branching
> model + a questions UI + per-guide authoring. Timeline revised to **~10 weeks**
> (with buffer) to fit them comfortably. Sequencing
> unchanged: build the scan→review→done spine + notifications first; adaptive
> guides come after the AI pipeline (Wk 5–6) is solid, since the "fill in
> details" step depends on it. Phase-1 guides are **no longer static.**

### Week 8: Polish + TestFlight
1. Empty states (no inbox, no past items, OCR failed)
2. Error states (LLM down, OCR garbled, no network)
3. Settings: language picker, "keep original scans" toggle, version
4. Privacy banner on Inbox: `LOCAL OCR · NO BANK LINK · NO AUTOPAY`
5. Past items list (Done archive, no search) — **with delete** (swipe-to-delete
   here, plus the Delete button that already appears on a done item's Detail).
   Decided 2026-05-30: done items go to this list and can be removed from it.
   **Plus an "undo done" / Reopen** (decided 2026-06-05): a done item's Detail
   should offer "Mark as not done" → sets status back to active, reschedules
   reminders, moves it out of the Done section. (Delete stays final — no undo
   needed there; only *done* needs reversing.)
6. Analytics events (`action_item_confirmed`, `action_item_completed`) → local JSON file
7. App icon (even placeholder serif "N" on cream)
8. 🔴 **BLOCKER before Archive — move the OpenAI key off-device (Cloudflare
   Worker).** Until now the key lives in the gitignored `AI/APIKeys.swift`, which
   is fine on the Simulator but **gets compiled into any shipped build** — a
   TestFlight binary with the key in it can be extracted and your account drained.
   `.gitignore` does NOT prevent this (it only stops the GitHub leak). Steps
   (~30 min): create a free Cloudflare Worker holding the key + per-IP rate limit;
   point `OpenAIClient.endpoint` at the Worker URL and drop the `Authorization`
   header (one-line change, thanks to the `Extractor` protocol); remove the real
   key from `APIKeys.swift`. Verify the shipped build contains only the Worker URL.
9. **Apply for Apple Developer Program** if not already (1–3 day approval)
10. Xcode → Product → Archive → Distribute App → App Store Connect
11. 24–48h Apple automated review
12. Add 10 testers in App Store Connect → TestFlight tab
13. Recruit testers from target audience (immigrants, ESL families)

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
