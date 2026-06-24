# Cuevi — Next-Version Roadmap (post-first-TestFlight)

> Parking lot for work deferred out of the first-TestFlight scope in `build_plan.md`.
> Move things here when we decide "not now, but yes later," so the build plan stays
> focused on shipping. Created 2026-06-16.
>
> **Reorganized 2026-06-23 into numbered Parts.** Beta testing has started, so
> everything here is the **next version** (testers don't have it yet — see the
> version-boundary banner in `build_plan.md`). Parts are rough priority order, not
> hard sequencing; Part 1 is in progress now.

---

## Part 1 — Metrics tracking backend  *(IN PROGRESS — started 2026-06-23)*

Turn the local-only `Metrics.swift` (already logs `confirmed`/`completed`) into a
tracker whose data actually reaches Rachel, so the launch metric aggregates across
testers instead of being stranded per-device. **Decision: keep & extend `Metrics`,
don't delete it. We build our own on Cloudflare ($0) — this replaces the earlier
"TelemetryDeck" idea.**

- **Phase 1 (backend, done in code):** Cloudflare **D1** database `cuevi-metrics` +
  a `POST /events` endpoint on the existing `cuevi-ai` Worker (same `X-Cuevi-Token`).
- **Phase 2 (app, done in code):** anonymous per-install UUID (UserDefaults, no PII),
  a stable `id` per `MetricEvent`, a synced-count cursor, and `Metrics.flush()`
  uploading un-synced events on launch/background.
- **Phase 3 (REQUIRED before shipping — not done):** update the privacy policy (it
  currently promises "no analytics or tracking") + Apple privacy label, add a Profile
  opt-out toggle. **Do not ship the upload build to TestFlight until this lands.**
- **Phase 4 (reporting):** `wrangler d1 execute` queries first; optional
  `/admin/summary` endpoint or tiny dashboard later.
- Strictly non-PII: kind, date, source, onTime, item UUID, install ID, app version —
  never titles/amounts/notes/document text.
- How Rachel reads it: `how_to_view_tester_data.md`.

## Part 2 — Accounts, family & monetization  *(Rachel's #1 future ask)*

The Profile tab scaffolds "Sign in / Family sharing / Cuevi Plus" as coming-soon rows.
Build the real thing:
- **Accounts** — sign-in so data isn't trapped on one device (needs a backend; until
  now everything is local-only by design).
- **Family sharing** — the core differentiator: a daughter/son manages their parents'
  English mail without missing deadlines. Multiple profiles / shared inbox; per-person
  items; "handling this for Mom."
- **Paid plan ("Cuevi Plus")** — subscription via Apple In-App Purchase (see the
  legal/business section in `build_plan.md` before charging). Likely gates higher scan
  limits, family sharing, cloud sync.

## Part 3 — Reminders & personalization

- **Configurable default reminder time** *(Rachel's #2 future ask)* — today reminders
  fire at a fixed **9am** (and overdue nudges every morning at 9am). Let the user pick
  their default reminder time in Profile — used whenever a specific time isn't already
  set on the item. A specific time on an item (e.g. a flight 3h before) still wins.

## Part 4 — Localization & content

- **Picker-controlled UI language** — today the app chrome follows the *iPhone's*
  language (String Catalog). Optionally let the Profile language picker override the
  whole UI, not just the AI output (needs a runtime language-override).
- **Translate guide content** — guide titles, subtitles, question prompts, and step
  text are still English. For general guides the AI polish already translates the
  checklist; the rest is a content-translation pass.
- **Bilingual term toggle** — tap a translated field to reveal the English term (e.g.
  确认码 ↔ "Confirmation code") for forms/clerks. (Detailed note in build plan.)

## Part 5 — Product depth (Phase 2+)

- **Per-type Detail layouts** — a bill vs. a phone call vs. a checklist render
  differently (DetailView is already section/item-driven to allow this).
- **Free-text Q&A** — ask Cuevi a question about a document (Phase 2 in the plan).
- **More guides + adaptive depth** — broaden coverage and per-state deep links.

## Part 6 — Technical / infrastructure

- **SwiftData VersionedSchema + MigrationPlan** — replace the dev-time resilient
  "wipe-and-recreate on failure" container with real migrations so updates never lose
  tester data. (Increasingly urgent now that testers have real data.)

---

## Done (shipped, kept for history)

- **Multi-page scan** — DONE 2026-06-17: up to 5 images/document (1 camera, 5 Photos),
  OCR'd and combined; Review shows a page-count badge.
- **First-launch onboarding** — DONE 2026-06-17: the seed is now 3 localized example
  items (overdue / in progress / done) whose steps teach the app; flagged `isExample`
  so they never schedule reminders.
