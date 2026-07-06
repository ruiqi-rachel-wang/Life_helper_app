# Cuevi — Next-Version Roadmap (post-first-TestFlight)

> Parking lot for work deferred out of the first-TestFlight scope in `build_plan.md`.
> Move things here when we decide "not now, but yes later," so the build plan stays
> focused on shipping. Created 2026-06-16.
>
> **Reorganized 2026-06-23 into numbered Parts.** Beta testing has started, so
> everything here is the **next version** (testers don't have it yet — see the
> version-boundary banner in `build_plan.md`).
>
> **Trimmed 2026-07-06 (Rachel's review):** old Part 6 (product depth) and Part 7
> (SwiftData migrations) removed — Rachel doesn't want them on the roadmap. The
> "make everything obvious" clarity pass (longer tab titles, plainer scan copy,
> bigger fonts, colorful icons) was done the same day; the rest of Part 2 is
> decided but not started.

---

## Part 1 — Metrics tracking backend  *(code DONE — one ship blocker left)*

Anonymous usage stats now reach Rachel: Cloudflare D1 `cuevi-metrics` + `POST /events`
on the `cuevi-ai` Worker; the app uploads un-synced `Metrics` events on
launch/background with a per-install UUID (no PII — never titles/amounts/notes/text).
Privacy policy + Apple label + Profile opt-out all landed; build number bumped to 3.

- **Remaining before the next TestFlight upload:** re-host the public policy page
  `cuevi-legal.pages.dev/privacy.html` so the App Store privacy URL matches the
  in-app policy.
- Reporting: `wrangler d1 execute` queries (see `how_to_view_tester_data.md`);
  a summary endpoint/dashboard only if querying gets tedious.

## Part 2 — First-run onboarding & comprehension  *(NEXT UP — decisions locked 2026-07-06)*

Testers may still not understand how the app works. Decision (Rachel, 2026-07-06):
the 3 seeded example items will be **replaced** by a real first-run walkthrough.

- **First-run walkthrough** *(not started)* — 3 short skippable screens (what Cuevi
  is → the three ways to add → checklist + reminders). Show once, before the
  notification primer; replayable from the empty Inbox. When it lands, remove the
  seeding of `ActionItem.samples` — but KEEP the stored `isExample` property
  (removing it changes the SwiftData schema and would wipe testers' data via the
  resilient container).
- **Keep the scanned photo (new ask, 2026-07-06 — not started)** — save the document
  photo with the item **by default** and show it at the end of its Detail page
  (below notes) so the user can always check the original; a My Settings toggle opts
  out. (Today the photo is already stored in `ActionItem.imageData` but never shown
  after saving.)
- **Clarity pass — DONE 2026-07-06:** longer/plainer tab titles (提醒待办事项 ·
  添加到提醒待办 · 生活指南服务 · 我的设置 / To-Dos & Reminders · Add To-Do · Life
  Guides · My Settings), scan tile says what it's FOR (bills/letters/mail/forms)
  instead of "most used" / "OCR on device", type scale bumped ~2pt everywhere,
  colorful icons on the Add tiles + a teaching three-ways-to-start empty Inbox,
  tab/accent tint warmed to the brand sienna.
- Feeds the one launch metric (confirmed → done before due) — people can't complete
  the loop if they don't understand it.

## Part 3 — Accounts, family & monetization  *(Rachel's #1 future ask)*

The Profile tab scaffolds "Sign in / Family sharing / Cuevi Plus" as coming-soon rows.
Sequencing note: accounts come first — family sharing and cloud sync both need them,
and Cuevi Plus needs the Apple Paid Apps Agreement signed before any of it can charge.

- **Accounts** — sign-in so data isn't trapped on one device (needs a backend; until
  now everything is local-only by design).
- **Family sharing** — the core differentiator: a daughter/son manages their parents'
  English mail without missing deadlines. Multiple profiles / shared inbox; per-person
  items; "handling this for Mom."
- **Paid plan ("Cuevi Plus")** — subscription via Apple In-App Purchase, managed
  through **RevenueCat** *(decided 2026-07-01)*: entitlements, upgrade/downgrade/
  restore, receipt validation, configurable paywall. Free to $2.5k/mo tracked revenue,
  then a small rev-share **on top of** Apple's 15–30% cut. Likely gates higher scan
  limits, family sharing, cloud sync.

## Part 4 — Reminders & personalization

- **Configurable default reminder time** *(Rachel's #2 future ask)* — reminders
  currently fire at a fixed **9am** (overdue nudges too). Add a Profile picker for
  the default time, used whenever an item has no specific time of its own (a timed
  item, e.g. a flight 3h before, still wins). Small and self-contained — can ride
  along with any build.

## Part 5 — Localization & content

Ordered by expected impact:

- **Full verbatim translation of a scanned doc** *(Rachel, 2026-06-23 — the
  high-value one)* — the scan only shows an AI summary + steps, so a line in the
  original can be missed. When explain-language isn't English, offer "点击查看翻译 /
  Tap to translate" on the item's photo that overlays a line-by-line translation of
  the whole document (reuse the OCR text + one translate call).
- **Translate guide content** — guide titles/subtitles/questions/step text are still
  English; general guides get the checklist translated by the AI polish, the rest is
  a content pass.
- **Picker-controlled UI language** — let the Profile language picker override the
  whole UI chrome (today chrome follows the iPhone language via String Catalog);
  needs a runtime language override.
- **Bilingual term toggle** — tap a translated field to reveal the English term
  (确认码 ↔ "Confirmation code") for forms/clerks. (Detailed note in build plan.)

---
