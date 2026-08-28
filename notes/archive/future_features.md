# Tadah — Next-Version Roadmap (post-first-TestFlight)

> **This is the CURRENT plan — the work actually being built.**
> Anything pushed further out lives in **`later_ideas.md`** (created 2026-08-07):
> instant push notifications, photo backup, usage display, server-side scan quota,
> Google/email sign-in. Nothing in that file may be advertised to users until it
> moves back here and gets built.
>
> Originally a parking lot for work deferred out of the first-TestFlight scope in
> `build_plan.md`. Created 2026-06-16.
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
6. **Part 3: accounts → family sharing → Tadah Plus** — the retention and
   revenue unlock.

## Part 1 — Metrics tracking backend  *(code DONE — upload checklist left)*

Anonymous usage stats now reach Rachel: Cloudflare D1 `cuevi-metrics` + `POST /events`
on the `cuevi-ai` Worker; the app uploads un-synced `Metrics` events on
launch/background with a per-install UUID (no PII — never titles/amounts/notes/text).
Privacy policy + Apple label + Profile opt-out all landed; build number bumped to 3.

- **2026-07-08 — the "re-host the policy page" blocker turned out already done:**
  the live `tadah-legal.pages.dev/privacy` is byte-identical to `docs/` and
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
    "Here's your note" moment): "Welcome to Tadah."
  - **Inbox, `.addTab`** → card parked just above the tab bar, screen dimmed but
    the tab bar stays BRIGHT and tappable (the overlay lives inside the tab's
    content, so the dim can't reach the bar — Evernote's spotlight effect).
    Next switches to the Add tab itself; tapping the real tab also advances
    (`RootTabView` advances from `.welcome` AND `.addTab` on tab switch, so
    jumping ahead during the intro skips straight to the Review card).
  - **Review, `.reviewAdd`** → card directly above the real **Add to inbox**
    button. NO dim here — the point of Review is reading/editing what Tadah
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
  me how Tadah works" in the empty state still calls `tourGuide.start()`.
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

**Phase 1 — free accounts (Sign in with Apple) BUILT 2026-07-30 (not yet on TestFlight):**
- `Model/Account.swift` — `Account` (userID/provider/name/email + displayName/initials
  helpers) and `@Observable AccountStore` (persists one account to UserDefaults; sign
  in/out/update/delete; sign-out and delete NEVER touch the local SwiftData items, so
  "data survives sign-out/sign-in" holds). Injected in `TadahApp` via `.environment`.
- `Screens/SignInView.swift` — Sign in with Apple only (native, no backend/SDK). Google
  + email are noted as "coming soon", not dead buttons.
- `Screens/AccountDetailsView.swift` — avatar/name/email + Delete account (local-only:
  forgets the identity, keeps items).
- `ProfileView` — signed-out gets a "Sign in or create account" button; the ACCOUNT card
  shows Family sharing (UPGRADE chip → coming-soon alert) + Sign out; profile row becomes
  a tappable identity row → Account Details. 8 `AccountStoreTests` pass; build green.
- **⚠️ Rachel's 1 manual step before it works at runtime:** Xcode → Tadah target →
  Signing & Capabilities → **+ Capability → "Sign in with Apple"** (adds the entitlement
  and enables it on the App ID / provisioning — can't be done from the CLI). Until then
  the button compiles but authorization will fail on device.
- **Profile redesigned to Rachel's mockup 2026-07-31** (3-state mockup: No account /
  Free / Family Plus). Reachable states BUILT: guest = "No account" card ("Your
  information stays on this phone" + Create a free account); free = identity card
  ("Free plan" + email → Account Details), a **Tadah Plus** upgrade card (UPGRADE chip
  → coming-soon), then compact **SETTINGS** (Language row → sheet, Notifications row),
  **PRIVACY** (Save photos / Hide details / Share anonymous data toggles + Privacy
  Policy + Terms), a centered **Log out**, **HELP** (Send feedback → mailto), and the
  legal disclaimer + version footer. The long inline language list is now a single row
  → a Language sheet (the main declutter win Rachel asked for).
- **Next phase — NOW IN PROGRESS: family sharing (multi-profile).** Plan at
  `~/.claude/plans/snug-singing-moore.md`. Decided 2026-08-07: ONE Apple sign-in per
  family, profiles switched in-app, 8 profiles / 8 devices; **instant push deferred**
  to `later_ideas.md` — family deadline reminders already work via sync + the existing
  reminder system, so v1 uses a catch-up banner on open.
  *(Google + email sign-in moved to `later_ideas.md`.)*
- **Family Plus screen — mockup captured, BUILD WITH THE PLUS PHASE (not reachable
  until a Plus/family state exists):** identity shows "Family Plus · N family members";
  a **FAMILY** section (Family members, Shared tasks, Family notifications) —
  Rachel: keep this "as before" but restyle *with color / a different layout* (avatar
  circles, not plain rows); an **ACCOUNT** section at the bottom (Manage Family Plus +
  Log out). Rachel's tweak: **for the Plus screen, move MORE of the settings under the
  Account section** rather than listing SETTINGS/MORE SETTINGS/PRIVACY all on the main
  Profile — the Plus screen otherwise has "too many things." (Extra Plus toggles in the
  mockup: notify-when-family-adds-a-task, notify-when-completed, default reminder time
  — the reminder-time one overlaps Part 4.)

The Profile tab scaffolds "Sign in / Family sharing / Tadah Plus" as coming-soon rows.
Sequencing note: accounts come first — family sharing and cloud sync both need them,
and Tadah Plus needs the Apple Paid Apps Agreement signed before any of it can charge.

- **Accounts (free)** — sign in with Apple/Google/email. The only thing this unlocks
  vs. guest is that your data survives sign-out/sign-in (and, eventually,
  reinstall/new-phone) — **one profile, one device.** No family sharing, no
  multi-device. This is deliberately free: it's retention (don't lose your data),
  not a paid feature.
- **Family sharing → Tadah Plus (paid), decided 2026-07-11** — the free/paid line is
  specifically **multiple profiles / multiple devices under one account.** A free
  account is capped at one profile on one device; Tadah Plus is what lets a signed-in
  account add more profiles (Mom, Dad) and use them from more than one device —
  a daughter/son manages their parents' English mail without missing deadlines.
- **Plus caps — decided 2026-08-05: 8 profiles + 8 devices per account, independent.**
  Even Plus isn't unlimited (anti-abuse + sync-cost backstop). The two caps are
  DECOUPLED — not a 1-device-per-profile mapping: any profile can be signed in on
  several devices at once, and the account's limits are simply "≤ 8 profiles total"
  and "≤ 8 devices total." **Free** stays **1 profile / 1 device.** Enforcement lands
  with the family-sharing + multi-device-sync build (foundation only so far — see the
  task-sync notes); nothing enforces these counts yet.
- **Free-tier limits BUILT 2026-08-04, Plus caps wired 2026-08-05** — scans+guides
  share one pool; the task list is capped. Per tier (via `PlusStore.isPlus`,
  `Model/ScanQuota.swift` + `Model/TaskLimit.swift`): **Free** = 10 scans/guides a
  day, 20 per rolling 30 days, 20 tasks. **Plus** = 60/day, 300 per 30 days, 100
  tasks (high enough to feel unlimited, but a real backstop against a runaway
  OpenAI bill). *Decided 2026-08-05 — supersedes the earlier "Plus quota open" note.*
- **✅ DONE 2026-08-07 — privacy policy + terms rewritten for accounts/sync.**
  `App/LegalContent.swift` now describes Sign in with Apple, exactly what is backed up
  (item content incl. reference numbers) vs not (photos, raw OCR text), the free
  one-device rule, retention, and how to get server data deleted. `legal/*.md` and
  `docs/*.html` are now **generated from** LegalContent.swift by one script, so the three
  copies can't drift. `legal/app-store-privacy-label.md` gained a **Linked-to-Identity**
  section (User ID / user content / Purchases) — the old label declared everything as
  not-linked, which stopped being true with accounts.
  - ✅ **Published 2026-08-07** — https://tadah-legal.pages.dev/privacy and /terms both
    live and verified showing "Last updated: August 7, 2026", the account/sync and
    one-device disclosures, RevenueCat in the third-party table, and no leaked dev
    banner. *(Note for next time: the production URL can serve a stale edge-cached copy
    for a minute or two after `pages deploy` — re-check with `?v=<timestamp>` before
    concluding a deploy failed.)*
  - ⚠️ **Still to do (Rachel):** enter the revised answers in App Store Connect →
    App Privacy (the Linked-to-Identity rows in `legal/app-store-privacy-label.md`).
- **Positioning decision (Rachel, 2026-08-06): stop selling "on-device / local" as a
  feature.** Keep the capability, drop the marketing. Removed the guides "Stays on your
  device" badge and reworded the Profile guest card, sign-out confirmation, and Sign-in
  screen copy to sell **backup** instead of device-only storage. Rationale: the product
  is growing into account backup + cross-device sync, so a "never leaves your phone"
  guarantee is a promise we'd have to break. Keep options open, don't advertise them.
- **Moved to `later_ideas.md` (2026-08-07):** photo backup to the account (R2,
  opt-in) and the Profile usage readout. Both are deferred, not cancelled.
- **Paid plan ("Tadah Plus")** — subscription via Apple In-App Purchase, managed
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
- **Signed-in, Tadah Plus — `profileCard` and `accountCard` gain the multi-profile
  pieces:**
  - A **"Current profiles"** strip appears directly under `profileCard`: small avatar
    circles for each family member (you first) + a dashed "add" circle, and a small
    "Manage" link → **Family Sharing** screen. Tapping an avatar switches which
    profile's items show in the Inbox (only meaningful once >1 profile exists, which
    requires Plus).
  - `accountCard`'s **Family sharing** row subtitle switches to names once profiles
    exist (e.g. "3 profiles: Jing, Mom, Dad") → Family Sharing screen; **Tadah Plus**
    row shows active/managed state instead of an upgrade chip; **Sign out** stays a
    plain row at the bottom.
- **Account Details screen** (from tapping the profile row) — kept minimal, no phone
  number field (not needed for anything Tadah does): avatar (tap to change),
  **name**, **email**, and a **Delete account** row at the
  bottom. Does **not** duplicate Language/Notifications/Privacy/App rows — those
  already live on the main Profile screen; Account Details is just identity + auth.
- **Family Sharing screen** — a grid of profile avatars (owner first, then members)
  + a dashed "add profile" tile, same avatar style as the Current-profiles strip.
  Tapping a profile switches the active one. One line under the grid: "Tadah Plus
  covers every profile on this account — no extra charge per person."

**Deliberately left out of the mockups (keep it simple):** no per-profile phone
number, no in-screen scan-count dashboard, no password-change flow beyond what
Apple/Google sign-in already handles. Add only if a real need shows up post-launch.

### Part 3b — EMAIL + PASSWORD AUTH, replacing Sign in with Apple *(decided 2026-08-15)*

**Why this changes.** Sign in with Apple authenticates the Apple ID *on the
device*. So on a family member's own iPhone it can only ever mint THEIR account —
there is no way for them to reach the account holder's. That makes "one account,
several people, several devices" unbuildable on Apple auth: `Plus = 8 devices`
only ever meant the account holder's own devices. Email + password is what lets a
second person sign in to a shared account at all.

**No migration needed.** Accounts have never shipped — build 2 has none — so
there are no users to move. Clean slate. Removing Apple entirely also keeps
guideline 4.8 out of scope (it only applies alongside other social logins).

**Worker (all security-sensitive, all new):**
- `POST /auth/email/register` and `/auth/email/login`. **PBKDF2-HMAC-SHA256**,
  high iteration count, per-account random salt — that's what WebCrypto offers
  natively in Workers; Argon2id would need WASM. Constant-time compare. Rate
  limit both routes hard, per-IP and per-account.
- `accounts` table: id, email (unique, lower-cased), password_hash, salt,
  iterations, verified_at, created_at.
- Email verification + password reset via **Resend** (decided): single-use,
  expiring, constant-time-compared tokens; secret via `wrangler secret put`.
  Needs a domain with DNS records — so the domain purchase (§7) is now a
  dependency, not a nice-to-have.
- `/account/delete` loses the Apple-revocation step; re-auth becomes the password.

**App:**
- `SignInView` becomes register / sign-in / forgot-password. `AppleReauthorization`
  and the applesignin entitlement go.
- RevenueCat's app user id moves off the Apple `sub` to our own account id.
- `SessionStore` / `ReconciliationGate` / sync are **unchanged** — they only ever
  cared about a token and a user id, which is the point of that design.

**Consequences to handle, not discover later:**
1. **We now store real email addresses.** Apple's private relay often meant we
   never saw one. The privacy policy and the App Store label (just corrected to
   match `PrivacyInfo.xcprivacy`) both need another pass — email moves from
   "transmitted in a token" to "stored on our backend".
2. **Password reset is load-bearing.** Without it, one forgotten password is an
   account and every to-do in it, gone. It ships WITH login, not after.
3. This resets a chunk of Part 3 that was otherwise upload-ready.

---

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
- **Two language settings (Rachel, 2026-08-01)** — today's single Profile picker only
  changes the AI *explain* language (scans + guide prose); the app's own UI chrome still
  follows the iPhone language via the String Catalog, so it feels half-translated. Split
  it into **two** rows in SETTINGS:
  - **App language** — overrides the WHOLE UI (all chrome + content). Needs a runtime
    language override (set `AppleLanguages` in UserDefaults + a `.environment(\.locale)`
    override / relaunch prompt).
  - **Explain language** — the existing per-user "explain my documents in…" control, for
    when someone wants the app in English but explanations in 中文 (the customized case).
  Default: Explain language follows App language until the user sets it differently.
- **Bilingual term toggle** — tap a translated field to reveal the English term
  (确认码 ↔ "Confirmation code") for forms/clerks. (Detailed note in build plan.)

---

## Part 6 — Tadah Calls  *(added 2026-08-20)*

An AI agent that phones a business on the user's behalf — book it, cancel it,
chase it, ask whether they take your insurance — and reports the answer back
onto the to-do. Plus-only, server-side (the user is never on the line).

Doubles as the **CALL-E** hackathon submission: the feature and the entry are
the same build, not a throwaway demo.

**Full plan, phases, guardrails and cost caps: `hackathon_calls_plan.md`.**

Gated on build 4 closing out — the App Privacy label is currently inaccurate,
and a calling feature is not what you want to be carrying into that review.
