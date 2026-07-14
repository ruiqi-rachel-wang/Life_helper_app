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

1. **Re-host the privacy page & upload to TestFlight** — privacy page ✅ done;
   the build-3 upload is deliberately held to fold in the Part 2 fixes first
   (steps 2–3). Signed 1.0 (3) archive is staged in Xcode's Organizer.
2. ✅ **Part 2 as planned (DONE 2026-07-09)** — first-run walkthrough, photo
   shown at the end of Detail, save-photo opt-out. See Part 2 below.
3. ✅ **Swipe-to-complete/delete + "due today" softening (DONE 2026-07-09)** —
   direct hit on the one launch metric. See Part 2 below.
4. **Verbatim document translation** — pulled forward from Part 5; deepens the
   core "I can finally read this" promise (a tester already effectively asked).
   *(next up — start here once build 3 is uploaded, or before if bundling more.)*
5. ✅ **OpenAI spending cap set** ($20/mo + 80%/100% alerts, 2026-07-09) and
   Worker rate limit deployed (2026-07-08). Nothing outstanding here.
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

## Part 2 — First-run onboarding & comprehension  *(DONE 2026-07-09)*

Testers may still not understand how the app works. Decision (Rachel, 2026-07-06):
the 3 seeded example items were **replaced** by a real first-run walkthrough.

- **First-run walkthrough — reworked 4x, 2026-07-11/13 (Rachel's feedback each
  time).** 1st pass: static instructional slides ("not what I mean"). 2nd pass:
  same content as swipeable mockup screens with a Next button ("still screens, I
  want interactive"). 3rd pass: a self-contained interactive demo of a fake
  ConEd bill ("still wrong... I don't want any separate screen or note. I want
  on page instruction... transparent background with arrow telling you what to
  do"). 4th pass: translucent one-line arrow hints (`CoachHint`) on the real
  screens ("still not what i want" — she sent Evernote's onboarding screenshots:
  solid blue cards with a bold title, short body, page dots, and a Next button
  over a dimmed screen). **Current version (2026-07-13) — Evernote-style coach
  marks, still on the REAL screens:** `CoachHint` deleted, replaced by `TourCard`
  (`Components/TourCard.swift`) — a solid `Color.accent` card: bold white title,
  1–2 line body, 4 page dots, Skip + white **Next** button (**Done**, no Skip,
  on the last card). `TourGuide` (`App/TourGuide.swift`) gained a `.welcome`
  step: `.welcome → .addTab → .reviewAdd → .inboxRow → nil`; `Step` is
  `Int`-raw-valued so `rawValue` doubles as the lit page dot.
  - **Inbox, `.welcome`** → centered intro card over a dimmed screen (Evernote's
    "Here's your note" moment): "Welcome to Cuevi."
  - **Inbox, `.addTab`** → card parked just above the tab bar, screen dimmed but
    the tab bar stays BRIGHT and tappable (the overlay lives inside the tab's
    content, so the dim can't reach the bar — Evernote's spotlight effect).
    Next switches to the Add tab itself; tapping the real tab also advances
    (`RootTabView` advances from `.welcome` AND `.addTab` on tab switch, so
    jumping ahead during the intro skips straight to the Review card).
  - **Review, `.reviewAdd`** → card directly above the real **Add to inbox**
    button. NO dim here — the point of Review is reading/editing what Cuevi
    found. Real save still advances inside `addToInbox()`; Next just moves on.
  - **Inbox, `.inboxRow`** → card above the tab bar, NO dim, list fully live —
    it invites tapping/swiping the new row, so the row must work while the card
    shows. Row `onOpen`/`onComplete` or **Done** finishes.
  **Gap fix (Rachel, same day): the tour went silent on the Add page** — Next
  on the `.addTab` card switched tabs and no card followed until Review. Added
  a 5th step `.create` between them: a card on the Add page ("Start with a
  scan"), no dim (the three tiles ARE the instruction), whose **Next opens the
  scan flow itself** (`startScan()` — camera on device, photo picker on the
  Simulator; same quota gate as the hero tile). Real-action advancement moved
  from strict `advance(from:)` chains to `TourGuide.catchUp(to:)` (jump forward
  to wherever the user actually is, never backward, no-op when the tour is
  off): reaching the Add tab → `.create` (RootTabView); ReviewView `.onAppear`
  → `.reviewAdd` (covers scans, uploads, AND guides entered via the Guides
  tab); `CreateForm.save()` → `.inboxRow` (manual items skip Review, so skip
  its card too). `.addTab` card copy shortened ("that's where new to-dos
  start") since `.create` now explains the three ways in.
  Skip (any card) = `tourGuide.finish()` — replaces the old per-hint "×". "Show
  me how Cuevi works" in the empty state still calls `tourGuide.start()`.
  `didShowWelcomeTour` (AppStorage) still gates first-launch autostart and is
  flipped true by `RootTabView` once `tourGuide.step` returns to `nil`. All 10
  new strings localized EN/ZH/ES (3 orphaned CoachHint strings purged); welcome
  card verified on a fresh zh-Hans sim install (screenshot).
  **Polish (Rachel, 2026-07-14):** (1) empty Inbox trimmed to TWO ways to start
  (dropped the "Add it yourself" row) — the manual path still lives as a tile on
  the Add page. (2) Each screen only draws its tour card while its own tab is
  selected (`router.selectedTab == .inbox`/`.add` guards) so a tab switch can't
  flash two cards mid-transition. (3) The scanned photo on Detail is now a small
  96×120 preview with a corner expand badge (was up to 340pt tall and dominated
  the page) — full document still one tap away in the pinch-zoom viewer. All
  verified on the sim (empty-state + a seeded photo item, screenshots).
  First-launch seeding of `ActionItem.samples` removed; `isExample` KEPT on the
  model (old testers still have the seeded items; dropping the property would
  change the schema). `samples` static kept for previews.
- **Keep the scanned photo — DONE 2026-07-09** — the document photo shows at the
  end of Detail (below notes), tap for full-screen pinch-zoom. Saved by default;
  My Settings → Privacy has the "Save document photo with the item" opt-out
  (`AppSettings.savePhoto`). Photos never leave the device.
- **Clarity pass — DONE 2026-07-06:** longer/plainer page titles (提醒待办事项 ·
  添加到提醒待办 · 生活指南服务 · 我的设置 / To-Dos & Reminders · Add a To-Do &
  Reminder · Life Guides & Checklists · My Settings; tabs stay short), scan tile
  says what it's FOR (bills/letters/mail/forms) instead of "most used" / "OCR on
  device", type scale bumped ~2pt everywhere, colorful icons on the Add tiles +
  a teaching three-ways-to-start empty Inbox, tint warmed to the brand sienna.
- **Swipe-to-complete/delete in the Inbox — DONE 2026-07-09** — swipe a row left
  to reveal Done (active rows) + Delete. Custom gesture (rows aren't a List);
  tap still opens Detail; VoiceOver action exposes the same buttons. All three
  completion paths (Detail, swipe, notification) now share one `ItemActions`
  helper so they can't diverge.
- **Soften "due today" — DONE 2026-07-09** — day-of shows amber "Due today /
  今天到期" instead of red overdue; red stays for actually-past items. Display-only
  (`isDueToday`/`isPastDue`/`dueColor`); `isOverdue` (scheduling + bucketing)
  unchanged.
- Feeds the one launch metric (confirmed → done before due) — people can't complete
  the loop if they don't understand it.

## Part 3 — Accounts, family & monetization  *(Rachel's #1 future ask)*

The Profile tab scaffolds "Sign in / Family sharing / Cuevi Plus" as coming-soon rows.
Sequencing note: accounts come first — family sharing and cloud sync both need them,
and Cuevi Plus needs the Apple Paid Apps Agreement signed before any of it can charge.

- **Accounts (free)** — sign in with Apple/Google/email. The only thing this unlocks
  vs. guest is that your data survives sign-out/sign-in (and, eventually,
  reinstall/new-phone) — **one profile, one device.** No family sharing, no
  multi-device. This is deliberately free: it's retention (don't lose your data),
  not a paid feature.
- **Family sharing → Cuevi Plus (paid), decided 2026-07-11** — the free/paid line is
  specifically **multiple profiles / multiple devices under one account.** A free
  account is capped at one profile on one device; Cuevi Plus is what lets a signed-in
  account add more profiles (Mom, Dad) and use them from more than one device —
  a daughter/son manages their parents' English mail without missing deadlines.
  *(Whether Plus also raises the scan quota is still open — not decided, don't
  assume it does until Rachel says so.)*
- **Paid plan ("Cuevi Plus")** — subscription via Apple In-App Purchase, managed
  through **RevenueCat** *(decided 2026-07-01)*: entitlements, upgrade/downgrade/
  restore, receipt validation, configurable paywall. Free to $2.5k/mo tracked revenue,
  then a small rev-share **on top of** Apple's 15–30% cut. Gates family sharing
  (multi-profile, multi-device) per the decision above.

### Layout plan (reference mockups reviewed 2026-07-11)

- **Signed-out Profile — unchanged from today**, plus one new button: guest
  `profileCard` gets a **"Sign in or create account"** button under it (replaces the
  need to tap a coming-soon row). Everything below (Language, Notifications, Privacy,
  About & Legal) stays exactly where it is.
- **Sign in / Create account screen** — Apple + Google sign-in buttons (primary; no
  password to manage) with email + password as a fallback. Standard iOS auth screen,
  nothing custom needed.
- **Signed-in, free account — the common case, keep it boring:** `profileCard`
  becomes a tappable row (avatar + name + email, chevron → **Account Details**).
  No "Current profiles" strip — free is one profile, one device, so there's nothing
  to switch between. `accountCard` shows **Family sharing** (subtitle "Add family
  members" with an "Upgrade" chip → paywall, since it's Plus-only) and **Sign out**.
  That's the entire difference from guest: an identity row + the ability to sign out
  without losing data.
- **Signed-in, Cuevi Plus — `profileCard` and `accountCard` gain the multi-profile
  pieces:**
  - A **"Current profiles"** strip appears directly under `profileCard`: small avatar
    circles for each family member (you first) + a dashed "add" circle, and a small
    "Manage" link → **Family Sharing** screen. Tapping an avatar switches which
    profile's items show in the Inbox (only meaningful once >1 profile exists, which
    requires Plus).
  - `accountCard`'s **Family sharing** row subtitle switches to names once profiles
    exist (e.g. "3 profiles: Jing, Mom, Dad") → Family Sharing screen; **Cuevi Plus**
    row shows active/managed state instead of an upgrade chip; **Sign out** stays a
    plain row at the bottom.
- **Account Details screen** (from tapping the profile row) — kept minimal, no phone
  number field (not needed for anything Cuevi does): avatar (tap to change),
  **name**, **email**, and a **Delete account** row at the
  bottom. Does **not** duplicate Language/Notifications/Privacy/App rows — those
  already live on the main Profile screen; Account Details is just identity + auth.
- **Family Sharing screen** — a grid of profile avatars (owner first, then members)
  + a dashed "add profile" tile, same avatar style as the Current-profiles strip.
  Tapping a profile switches the active one. One line under the grid: "Cuevi Plus
  covers every profile on this account — no extra charge per person."

**Deliberately left out of the mockups (keep it simple):** no per-profile phone
number, no in-screen scan-count dashboard, no password-change flow beyond what
Apple/Google sign-in already handles. Add only if a real need shows up post-launch.

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
