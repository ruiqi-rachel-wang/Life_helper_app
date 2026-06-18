# Notie — Future Features (post-TestFlight)

> Parking lot for features intentionally deferred out of the Phase-1 / first-
> TestFlight scope in `build_plan.md`. Move things here when we decide "not now,
> but yes later," so the build plan stays focused on shipping. Created 2026-06-16.

---

## Accounts, family & monetization
1. **Family sharing / accounts** *(Rachel's #1 future ask)*
   - The Profile tab scaffolds "Sign in / Family sharing / Notie Plus" as
     coming-soon rows. Build the real thing:
   - **Accounts** — sign-in so data isn't trapped on one device (needs a backend;
     until now everything is local-only by design).
   - **Family sharing** — the core differentiator: a daughter/son manages their
     parents' English mail without missing deadlines. Multiple profiles / shared
     inbox; per-person items; "handling this for Mom."
   - **Paid plan ("Notie Plus")** — subscription via Apple In-App Purchase (see
     the legal/business section in `build_plan.md` before charging). Likely gates
     higher scan limits, family sharing, cloud sync.

2. **Configurable default reminder time** *(Rachel's #2 future ask)*
   - Today reminders fire at a fixed **9am** (and overdue nudges every morning at
     9am). Let the user pick their default reminder time in Profile — used whenever
     a specific time isn't already set on the item. A specific time on an item
     (e.g. a flight 3h before) still wins.

## Scanning & input
3. **Multi-page / multi-image scan** *(in near-term plan; may pull forward)*
   - Accept up to **5 images** per document (1 from camera, up to 5 from Photos),
     OCR all and combine — many notices are two-sided (the parking ticket's pay/
     dispute instructions are on the **back**). This directly improves extraction
     quality.

## Onboarding & guidance
4. **First-launch onboarding** *(in near-term plan; may pull forward)*
   - Replace the seeded fake bills with 3 instructional example items (one overdue,
     one in progress, one done) whose steps explain how the app works, so a fresh
     install isn't empty or confusing.

## Localization & content
5. **Picker-controlled UI language** — today the app chrome follows the *iPhone's*
   language (String Catalog). Optionally let the Profile language picker override
   the whole UI, not just the AI output (needs a runtime language-override).
6. **Translate guide content** — guide titles, subtitles, question prompts, and
   step text are still English. For general guides the AI polish already
   translates the checklist; the rest is a content-translation pass.
7. **Bilingual term toggle** — tap a translated field to reveal the English term
   (e.g. 确认码 ↔ "Confirmation code") for forms/clerks. (Detailed note in build plan.)

## Metrics & analytics
8. **TelemetryDeck** — wire the chosen privacy-first analytics SDK (decided in the
   plan) so the launch metric aggregates across testers, not just per device.

## Product depth (Phase 2+)
9. **Per-type Detail layouts** — a bill vs. a phone call vs. a checklist render
   differently (DetailView is already section/item-driven to allow this).
10. **Free-text Q&A** — ask Notie a question about a document (Phase 2 in the plan).
11. **More guides + adaptive depth** — broaden coverage and per-state deep links.
12. **SwiftData VersionedSchema + MigrationPlan** — replace the dev-time resilient
    "wipe-and-recreate on failure" container with real migrations so updates never
    lose tester data.
