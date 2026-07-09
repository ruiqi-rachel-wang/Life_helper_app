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
>
> **2026-07-08 — full pre-ship review done (code + product).** All watch-list
> hardening landed the same day: Worker per-IP rate limit + per-install AI quota,
> notification scheduling now survives iOS's 64-pending cap (soonest-first
> budget), SwiftData VersionedSchema V1 baseline (+ test proving old stores open
> intact — schema changes are migratable now), custom reminders follow a moved
> due date, decimal-comma amounts parse, and a "Hide details in notifications"
> privacy toggle. Product asks from the review are folded into Parts 2/5 below.

---

## Ship order for the next version *(agreed 2026-07-08)*

1. **Re-host the privacy page & upload to TestFlight** — the one Part 1 blocker;
   everything since build 2 is invisible to testers until this happens.
2. **Part 2 as planned** — first-run walkthrough, photo shown at the end of
   Detail, save-photo opt-out.
3. **Swipe-to-complete/delete in the Inbox + "due today" softening** (Part 2
   additions below) — small, direct hit on the one launch metric.
4. **Verbatim document translation** — pulled forward from Part 5; deepens the
   core "I can finally read this" promise (a tester already effectively asked).
5. **Cloudflare dashboard rate rule + OpenAI spending cap** — 10 minutes, Rachel
   only (code-level limits landed 2026-07-08; these are the outer $ ceilings).
6. **Part 3: accounts → family sharing → Cuevi Plus** — the retention and
   revenue unlock.

## Part 1 — Metrics tracking backend  *(code DONE — upload checklist left)*

Anonymous usage stats now reach Rachel: Cloudflare D1 `cuevi-metrics` + `POST /events`
on the `cuevi-ai` Worker; the app uploads un-synced `Metrics` events on
launch/background with a per-install UUID (no PII — never titles/amounts/notes/text).
Privacy policy + Apple label + Profile opt-out all landed; build number bumped to 3.

- **2026-07-08 — the "re-host the policy page" blocker turned out already done:**
  the live `cuevi-legal.pages.dev/privacy` is byte-identical to `docs/` and
  discloses the usage stats. Verified from here. What WAS stale: the July terms
  §6 clarification — now synced across md / in-app / html; needs one
  `pages deploy` to publish.
- **Remaining (Rachel, ~30 min):** the 4-step checklist in
  `testflight_build3_notes.md` — publish terms page, update the ASC App Privacy
  label (Product Interaction + User ID are NEW since build 2), archive & upload
  build 3, set the OpenAI spend cap. What-to-Test notes (EN+中文) are drafted there.
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
- **Clarity pass — DONE 2026-07-06:** longer/plainer page titles (提醒待办事项 ·
  添加到提醒待办 · 生活指南服务 · 我的设置 / To-Dos & Reminders · Add a To-Do &
  Reminder · Life Guides & Checklists · My Settings; tabs stay short), scan tile
  says what it's FOR (bills/letters/mail/forms) instead of "most used" / "OCR on
  device", type scale bumped ~2pt everywhere, colorful icons on the Add tiles +
  a teaching three-ways-to-start empty Inbox, tint warmed to the brand sienna.
- **Swipe-to-complete/delete in the Inbox** *(from the 2026-07-08 review — not
  started)* — marking done today takes open item → scroll → Mark done; the
  launch metric IS completions, so make it one swipe on the row (with the same
  recurring-spawn + metrics logging the Detail button does).
- **Soften "due today"** *(from the 2026-07-08 review — not started)* — a task
  due today currently shows as 逾期/overdue in red, which punishes exactly our
  audience. Show 今天到期 / "Due today" in amber for day-of; red stays for
  actually-past items. (Keep `isOverdue` for scheduling; this is display-only.)
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

Ordered by expected impact. Review note (2026-07-08): for Chinese users the app
currently feels HALF-translated — chrome is 中文 but guide titles/questions are
English — so the two items below are the credibility gap, not polish.

- **Full verbatim translation of a scanned doc** *(Rachel, 2026-06-23 — pulled
  forward into the ship order, step 4)* — the scan only shows an AI summary +
  steps, so a line in the original can be missed. When explain-language isn't
  English, offer "点击查看翻译 / Tap to translate" on the item's photo that overlays
  a line-by-line translation of the whole document (reuse the OCR text + one
  translate call).
- **Translate guide content** — guide titles/subtitles/questions/step text are still
  English; general guides get the checklist translated by the AI polish, the rest is
  a content pass.
- **Picker-controlled UI language** — let the Profile language picker override the
  whole UI chrome (today chrome follows the iPhone language via String Catalog);
  needs a runtime language override.
- **Bilingual term toggle** — tap a translated field to reveal the English term
  (确认码 ↔ "Confirmation code") for forms/clerks. (Detailed note in build plan.)

---
