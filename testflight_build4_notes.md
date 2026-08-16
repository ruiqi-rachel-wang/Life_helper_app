# TestFlight build 4 — upload checklist & What to Test

> Prepared 2026-08-07. Version 1.0, `CURRENT_PROJECT_VERSION = 4`.
> **Build 3 was never uploaded** — testers are still on **build 2**, so build 4
> carries *both* the build-3 work and everything since. Supersedes
> `testflight_build3_notes.md` (keep that file only for its history).

---

## ⚠️ Two decisions needed BEFORE uploading

### 1. Tadah Plus paywall — no longer a blocker, but read this

**Resolved 2026-08-11.** Tapping UPGRADE used to show RevenueCat's own developer
alert — *"Error 23: There is an issue with your configuration… rev.cat/
sdk-troubleshooting"* — because there is no current Offering with fetchable
products yet. That is a message for a developer, and it made the app look broken.

`PaywallView` now checks for a usable offering **before** handing over to
RevenueCatUI, and shows a plain, on-brand **"Tadah Plus is coming soon"** screen
when there isn't one. So the app is safe to ship as-is: nobody sees an error, and
the moment the products go live the real paywall appears with no code change.

Also added: **`Tadah/Tadah.storekit`**, attached to the (new, shared) `Tadah`
scheme's Run action. Running from Xcode (⌘R) in the Simulator resolves and
transacts `com.ruiqiwang.cuevi.plus.monthly` / `.yearly` locally, so a **purchase**
can be tested with no App Store Connect setup. It affects local runs only — never
archives.

**Why "coming soon" kept appearing (2026-08-13).** Diagnosed from the SDK's own
debug log rather than guessed. With `Purchases.logLevel = .debug`, launching the
app prints:

```
store_kit: No existing products cached, starting store products request for:
           ["com.ruiqiwang.cuevi.plus.monthly", "com.ruiqiwang.cuevi.plus.yearly"]
offering:  ERROR ... RevenueCat.OfferingsManager.Error 1
           None of the products registered in the RevenueCat dashboard could be
           fetched from App Store Connect (or the StoreKit Configuration file)
```

So the dashboard is **correct** — it asks for exactly the two reverse-DNS ids that
`Tadah.storekit` declares. *(An earlier note here claimed the dashboard used bare
`monthly` / `yearly` ids and that this mismatch was the bug. That was wrong: the
`monthly` / `yearly` strings visible in the Offering screenshot are the package
labels, `$rc_monthly` / `$rc_annual`, not store product ids. The mirrored ids that
were briefly added to `Tadah.storekit` have been reverted.)*

The real cause is that **the StoreKit configuration is not being applied to the
run at all** — the log line `Using a simulator. Ensure you have a StoreKit Config
file set up` appears, then StoreKit returns zero products for ids that are
verbatim in the file. `Tadah.storekit` was never a member of the Xcode project
(`grep -c storekit project.pbxproj` → 0); it was created on disk with a
hand-written `StoreKitConfigurationFileReference` in the scheme, and Xcode
resolves that reference through the project's file references.

Fixed by adding a `PBXFileReference` for it to the project's root group **with no
target membership**. Verified `find Tadah.app -name '*.storekit'` → **0**, i.e. it
is still not copied into the app bundle. (It was briefly moved into the
synchronized `Tadah/Tadah/` folder, which does make it a project member
automatically — but that folder's contents get copied into the bundle, so it was
moved back out.)

Three scheme identifier spellings (`../Tadah.storekit`, `Tadah.storekit`,
`../Tadah/Tadah.storekit`) were each probed with a throwaway test calling
`Product.products(for:)`; all returned 0. That probe is **not conclusive** — the
Test action may not honour a StoreKit configuration at all — so the last step has
to be confirmed by running from Xcode. If ⌘R still shows "coming soon", set it
once through **Edit Scheme → Run → Options → StoreKit Configuration**, which makes
Xcode write the reference itself.

**Corrected 2026-08-12 — the StoreKit file alone does not show the real paywall.**
An earlier draft of this note claimed it did; that was wrong. RevenueCat fetches
*Offerings from its own backend*, not from the local file, so with an empty
dashboard the SDK throws `.configurationError` and the app shows "coming soon".
To see the real paywall in the Simulator you also need, in the **RevenueCat
dashboard**: products with those two IDs, in an **Offering marked Current**, with
the `Tadah Pro` entitlement. (Those can be added in RevenueCat by product ID
before the App Store Connect products are live; the `.storekit` file then lets the
purchase actually complete.)

To make it real for testers, the remaining work is all portal-side: Paid Apps
Agreement → subscription products in App Store Connect → those products in a
RevenueCat **Offering marked Current** with the `Tadah Pro` entitlement.

<details><summary>Original note (kept for history)</summary>

**Corrected 2026-08-11:** the app now uses the **production** Apple key
(`appl_…`) — the "test store" wording below was left over from an earlier draft
and was wrong. What still has to be true before a tester can actually buy
anything is the App Store Connect side (agreement, products, Offering).
Profile → **UPGRADE** opens the real `PaywallView`. A tester who taps it gets a
paywall that cannot make a genuine App Store purchase. Pick one:

- **(a) Hide it for build 4** *(recommended, smallest risk)* — point the UPGRADE
  row back at the existing "coming soon" alert (`showPlusComingSoon`) and leave
  the paywall code in place, unreachable. Ship the free tier only.
- **(b) Make it real** — needs, in order: Apple **Paid Apps Agreement** signed;
  subscription products created in App Store Connect; those products added to a
  RevenueCat **Offering** with the `Tadah Pro` entitlement; the app switched to
  the **public Apple key** (`appl_…`). Then test with a sandbox account.

</details>

### 2. The new free-tier limits will throttle your testers

Nobody has Plus, so **every tester is on the free tier**: 10 scans+guides/day,
**20 per rolling 30 days**, and **20 tasks total**. Testers are exactly the people
who scan a lot, and a tester who already has more than 20 items will be unable to
add anything. Options: raise the free numbers for the beta, treat testers as Plus,
or ship as-is and say so plainly in the notes (the draft below does).

---

## Twentieth pass (2026-08-15/16) — three external review rounds on the auth swap

Every finding was verified before acting; all were real. Grouped by what they
taught, because several were the same mistake wearing different clothes.

**Secrets that failed OPEN (round 1).** `PASSWORD_PEPPER` fell back to a public
constant and `EMAIL_FROM` to Resend's shared sender — so a deploy that forgot
either kept working while silently losing the protection. Both now fail closed
(503 / throw), documented as ⚠️ REQUIRED in `wrangler.toml`, with tests. A
secret whose absence is invisible is the worst kind.

**Read-then-write races (round 1).** The reset attempt cap was SELECT-then-UPDATE,
so concurrent guesses all passed a "five attempts" check. Now a conditional
`UPDATE … WHERE attempts < 5 RETURNING` — the increment IS the check. The reset
code was also an unkeyed SHA-256 (six digits = instantly searchable in a leak);
now HMAC-keyed with the pepper. Two sibling races — the resend cooldown and
confirm-vs-reissue — are deferred to §8g with the throttle work.

**The false-touch bug, THIRD occurrence (round 1).** `ProfileStore.rename`
stamped `updatedAt` unconditionally, so opening Family → Edit → Save with no
change could overwrite a genuine remote edit under LWW. Fixed at the root so
every caller inherits the guard, as with task and step detail before it.

**Half-applied features (rounds 2 and 3).** Per-person reminder times synced but
didn't reschedule queued notifications; the Add tile used `familyUnlocked` while
Save still used `isPlus`; rescheduling cancelled `|snooze` and never recreated
it, silently eating "Remind me later". Each worked in the place it was written
and nowhere else.

**Documentation that described a different app (all three rounds).** The in-app
policy, the published policy, the App Store label notes and `wrangler.toml` all
still described Sign in with Apple. Worse, the label doc had been *annotated*
twice rather than rewritten, so it argued with itself. Now rewritten, and Apple
is genuinely removed from the Worker (route, verification, JWKS, revocation) with
a route test pinning the 404 — the previous comment claimed removal while the
handler was still live.

**⚠️ A LESSON WORTH KEEPING: `legal/*.md` and `docs/*.html` are GENERATED** from
`LegalContent.swift` by `legal/make_legal_pages.py`. A date fix applied directly
to `privacy-policy.md` was overwritten by the next generator run. Edit the Swift,
then regenerate, then deploy — which is exactly what that script's docstring
already said.

**Verification:** **265/265** iOS · **32/32** Worker helper · **51/51** Worker
route · 0 PasswordCrypto actor warnings (marked `nonisolated`) · 0 npm
vulnerabilities.

---

## Nineteenth pass (2026-08-15) — AUTH SWAPPED TO EMAIL + PASSWORD

The largest change in build 4, and it came from a question rather than a bug:
*"if you use Apple sign in, how does another family member sign in?"*

**They couldn't.** Sign in with Apple authenticates the Apple ID **on the device**,
so on Mum's iPhone it can only ever mint Mum's own account — there is no way to
reach the account holder's. "One account, several people, several devices" was
unbuildable on it, and `Plus = 8 devices` only ever meant the owner's own devices.
A shared email and password can be handed to someone; an Apple ID cannot.

No migration was needed: accounts never shipped, so there were no users to move.

**Built:**
- `accounts` + `password_resets` tables; `/auth/email/register`, `/login`,
  `/reset/request`, `/reset/confirm`; `sendEmail` via Resend.
- `PasswordCrypto` — PBKDF2-HMAC-SHA256, 600k iterations, ON THE PHONE. A
  free-plan Worker gets **10ms CPU per request** and real PBKDF2 needs hundreds,
  so server-side hashing would either 1102 or have to run ~60× below guidance.
  Moving it client-side keeps the per-guess cost identical for an attacker.
- The salt is derived from the email, not random — it must be reproducible before
  contacting the server, and fetching a salt by address is itself an enumeration
  oracle.
- **Reset**: 6-digit code (a link needs a website; there isn't one), 15-min
  expiry, single use, 5-attempt cap, SHA-256 only, all sessions revoked on
  success. Request answers identically for unknown addresses and swallows send
  failures, so it can't be used to discover who has an account.
- **Account deletion now works for email accounts** — it did not, and 5.1.1(v)
  requires it. Users were being asked for an Apple grant their account can't
  produce. Now a separate password confirmation.
- Apple code DELETED: `AppleReauthorization`, `AuthService.authenticate`, the
  delete branch, and the comments describing them. `Account.Provider.apple` stays
  — it's a persisted Codable case.

**Rachel still to do:** remove the Sign in with Apple capability in Xcode's
Signing & Capabilities (left to the UI deliberately — a hand-edited entitlement
mid-testing invites a signing failure), and the privacy policy + App Store label
pass, which is now REQUIRED: real email addresses are stored on the backend where
Apple's private relay previously meant we often never saw one.

**⚠️ ALSO OPEN — a SwiftData versioning trap.** Adding `Profile.reminderMinutes`
while `TadahSchemaV3` pointed at the live types made a real V3 store unopenable
("Can't open your saved to-dos"). The by-the-book fix — freeze V3, add V4 — was
tried and made it worse: a second `@Model` class named `Profile` makes SwiftData
fail every live fetch. Reverted. Survivable ONLY because V3 has never shipped, so
the fix is delete-and-reinstall on a dev phone. **This must be solved before
accounts ship**; see TadahSchema.swift.

**Verification:** **265/265** iOS · **33/33** Worker helper · **47/47** Worker
route · catalog **1112** keys, es/zh complete · 0 npm vulnerabilities · email
auth confirmed working end-to-end against the LIVE Worker from a real device.

---

## Eighteenth pass (2026-08-14) — third external review, all four findings valid

Small pass; every finding was correct, including one where a comment I wrote made
a security claim that wasn't true.

- **The JWKS forced refresh was an amplifier, and its comment said otherwise.**
  The rotation fix refetched on an unknown `kid`, and the comment claimed an
  attacker couldn't hammer Apple with it. **That only held for a *repeated* kid.**
  `kid` is an unverified field in the token, so a stream of tokens each naming a
  DIFFERENT bogus key forced one outbound JWKS fetch per inbound request —
  refreshing the cache is no defence, because the next bogus kid is unknown all
  over again. Now throttled to **one forced refresh a minute** (a real rotation
  needs far less), with the honest reasoning written down. Two helper tests added,
  and **mutation-tested**: removing the cooldown fails exactly the new test.
- **Step checkboxes stamped twice.** `rollUp()` reported, then dismissal saw the
  same tick as still "different from when the sheet opened" and reported again.
  The debounce swallowed it, so it was waste rather than a bug. Reporting now
  re-baselines the snapshot, so "changed" means *since we last said so*.
- **The DTO contract test missed `recurrence`.** Correct as written — `TaskDTO`
  does carry it and the round-trip test covers it — but the *contract* test is
  the one that guards change detection, so a gap there is a gap in the alarm.
  Added `recurrence` (set and cleared), `seriesID`, `recurrenceAnchorDay`,
  `reminderLeadHours` and `senderShort`.
- **`later_ideas.md` §8f contradicted the code**, still listing stale profile
  caching, the editable email and the JWKS refresh as deferred after all three
  were fixed. Corrected, with a short "already done" note so the record doesn't
  read as still-open.

Everything else in that review matched: the false-touch blocker is closed, the
live privacy page and Worker redeploy remain external checklist items, and the
genuinely deferred items (failed sign-in, reassignment, destructive profile
removal, the logout-policy decision) are accurately described.

---

## Seventeenth pass (2026-08-13) — second external review

### ⚠️ It caught a regression the sixteenth pass introduced. It was right.

Fixing "edits never sync" by stamping `updatedAt` on the way out of a screen was
**half a fix**. `StepDetailView.onDisappear` fired `onChange()` unconditionally,
and `DetailView` committed whenever edit mode had been open — so simply OPENING a
step to read it, or tapping Edit and changing nothing, bumped the item's
timestamp. Under last-writer-wins that makes the untouched local copy the newest
version, and it **overwrites a genuine edit from another device**. One data-loss
path traded for another, in the same direction: whoever looked last wins.

Both screens now stamp **only when the value actually changed**:

- `DetailView` snapshots `TaskDTO(item)` when edit mode opens and commits on Done
  *or* dismissal only if it differs. `TaskDTO` is the item's own Equatable value
  form, so this compares every synced field without hand-listing them.
- `StepDetailView` snapshots the `ChecklistStep` (Hashable) on appear and compares
  on dismiss. `rollUp()` still reports unconditionally — it only runs from an
  actual checklist tick.

The whole mechanism now rests on `TaskDTO` staying sensitive to every editable
field, so **`taskDTOEqualityNoticesEveryEditableField`** pins exactly that: 22
mutations must each register, and an untouched item must compare EQUAL. If a
field is ever dropped from the DTO, edits to it would silently stop syncing again
and nothing else would fail — this is that alarm.

### Also fixed this pass

- **Reconciliation said "to-dos" while counting to-dos AND profiles.** Someone
  with 2 profiles and no to-dos was told they had "2 to-dos". Copy now says
  *items*, matching what `localPersonalDataCount` actually returns. Old strings
  retired from the catalog rather than left orphaned.
- **Apple key rotation could break sign-in for up to 6 hours.** An unknown `kid`
  failed outright against a cached JWKS. It now refetches **once**, bypassing the
  cache, before giving up — a bogus `kid` still costs one fetch and then fails.
- **Family profiles went stale after a background pull.** `SyncCoordinator` never
  reloaded `ProfileStore`, whose cached array feeds the switcher and the assignee
  picker — so a person added or removed elsewhere stayed invisible (or pickable)
  until Family was opened. It reloads on every successful pass now.
- **The account email field was editable and did nothing.** It's Apple's, and
  typing in it changed only a local display string, so the next sign-in showed the
  old address. Now read-only, shown only when Apple actually gave us one, with
  "From your Apple ID. Change it in iPhone Settings."
- **Copy that promised things we don't do:** "Google, email coming soon" (no
  date, nothing actionable — removed), "we'll let you know the moment Plus is
  ready" (no push, no email list → "check back soon"), and Plus's "share tasks",
  which implies your mum signs in with her own Apple ID → "keep a separate list
  for each person".

### Still open, unchanged and deliberate

- **Deploy the docs site and redeploy the Worker.** Both are now REQUIRED, not
  optional: the live privacy page still omits family profiles and describes the
  old email-us deletion process, and the profile-cap + JWKS fixes are server-side.
  Neither can be done or verified from the repo. Checklist items #2 and #6.
- **Failed-sign-in dead end** and **to-do reassignment** stay in `later_ideas.md`
  §8f. Both are flow changes, not patches, and the review agrees they're
  "before a wider beta" rather than blockers.
- **Logout revocation is best-effort by design** — the local session is always
  destroyed, and the server token expires on its own. Making it guaranteed needs a
  retry queue; noted in §8f.
- **The owner can read "Unnamed" until the next launch.** The repair now
  propagates (it stamps `touch()`), but it still happens a launch late, because
  `ensureOwnerProfile` runs at startup before sign-in completes. Fixing the timing
  means reordering identity mutation around the reconciliation gate — not
  something to do hours before an upload.
- **UI suite still unverified.** Both reviews hit simulator Accessibility-daemon
  failures; that's an environment failure, not an app assertion. Unit coverage
  stands in for it.

---

## Sixteenth pass (2026-08-13) — acting on an external review

An external review raised ~20 findings. Verified each against the tree rather
than taking them on trust; the ones below were real and are **fixed**.

**Its headline blocker — "the tree does not compile" — was already resolved.**
It described `CreateView.swift` mid-save, with `$focused` / `Field` declared on
the outer `CreateView` while `CreateForm` used them. That window was open for
roughly six minutes during concurrent editing. Verified after the fact:
`build-for-testing` **succeeds** and the unit suite is green. Nothing to do.

### Data-correctness fixes (these are the ones that mattered)

- **Item edits abandoned without tapping Done never synced.** Every field in
  `DetailView` binds straight to `$item`, so typing mutates the stored model, but
  `touch()` only ran on the Done button. Leaving by the back chevron or a swipe
  saved the edit locally with a stale `updatedAt` — so the push filter
  (`updatedAt > watermark`) skipped it and the next pull from another device
  overwrote it. Silent loss of exactly the thing the account is supposed to
  protect. `onDisappear` now commits when still editing.
- **Nothing in the step-detail sheet ever synced.** `StepDetailView` had *no*
  reference to `touch()` or `noteLocalChange()` while editing step text, the
  explanation, and the mini-checklist through a binding into `item.steps[i]`.
  Same silent-loss shape, on the richest content in the app. It now takes an
  `onChange` callback, fired from `rollUp()` (checklist ticks) and on dismiss
  (text edits); `DetailView` stamps the item, `ReviewView` passes the no-op
  default because its draft isn't a stored item yet.
- **A lapsed Plus family could not sync at all.** The Worker's profile cap
  counted the FINAL live total, so an account already above the cap — precisely
  what a Plus family becomes when the subscription ends (3 profiles, cap drops
  to 1) — got a 409 on *any* profile push, including a plain rename. The route
  rejects the whole request, so their **tasks** stopped syncing too, and the app
  hides routine sync errors, so it looked like the app had quietly stopped
  saving. The cap now blocks only ids that would be **added**, which is what the
  comment above it had claimed all along. Two route tests added (edit-while-over-
  cap succeeds and carries its task; adding while over cap still 409s) and
  **mutation-tested** — reverting the guard fails exactly the new test.
- **The owner-name repair never propagated.** `ensureOwnerProfile` fills a blank
  owner name on a later launch but didn't `touch()`, so every other device kept
  showing "Unnamed" forever.
- **`setupComplete` was written and never read** — a fair catch. The durable
  guard rested entirely on `ReconciliationGate`, which lives in UserDefaults
  (lazily flushed) while the session is a Keychain value (written synchronously).
  A hard kill in that window loses the gate and keeps the credential, and the
  relaunch comes up authenticated and unblocked — the exact cross-account upload
  the gate exists to stop. `SessionStore.isSetupIncomplete` is now checked in
  `run()` (and re-raises the gate), and `markSetupComplete()` is paired with
  every gate clear on a success path. Covered by a new test.
- **An involuntary sign-out left the RevenueCat identity behind.** Only the
  deliberate log-out called `Purchases.logOut()`; the 401-revocation and
  abandon-session paths called the plain `signOut()`, so the phone kept the
  departed user's Plus entitlement and the next person inherited it. New
  `AccountStore.signOutAfterSessionEnded()` is used by all three.

### Smaller fixes

- **Limit alerts were dead ends.** "Scan limit reached" and "List full" offered
  only OK. Free users now also get **See Tadah Plus** (subscribers don't — they
  can't buy past their own ceiling). Localized es + zh-Hans.
- **The rename sheet opened blank**, with Save disabled until you typed — so
  tapping Rename to check a spelling gave you a dead sheet. It prefills the
  current name.
- **The privacy label doc contradicted the shipped manifest.**
  `PrivacyInfo.xcprivacy` declares Name and Email as collected + **linked**;
  `legal/app-store-privacy-label.md` said they were device-only and undeclared.
  Apple compares the two, so this was a submission risk. The doc now matches the
  manifest (the conservative direction, which that doc's own rule prefers) and
  says to change the manifest first if the call is ever revisited.

### Confirmed real, NOT fixed here — deliberately

- **The published privacy page is stale.** Already checklist item #2 below; the
  review adds a sharp detail worth keeping: the live page carries the correct
  **August 7** date with older content, so the mismatch is easy to miss. Deploy
  `docs/` before submitting and re-read the deletion paragraph specifically.
- **Deployment can't be certified from the repo.** Unchanged and correct — see
  the checklist. The Worker responding to an unauthenticated `/sync` proves
  nothing about which build, schema or secrets are live. **The profile-cap fix
  above makes a redeploy mandatory, not optional.**
- **A failed sign-in can leave a dead-end local account** ("Continue anyway"
  persists the account before a backend session exists, and the sign-in entry
  point then disappears; recovery is log out and back in). Real, but the fix is a
  sign-in state-machine change, which is not a thing to start hours before an
  upload. Written up in `later_ideas.md` §8f.
- **Sync failures remain invisible** (§8e, already recorded), **profiles can go
  stale until Family is opened**, **to-dos can't be reassigned from Detail**, and
  **the editable account email is local-only display data**. All now in
  `later_ideas.md` §8f with the reasoning.

**Verification:** **261/261** iOS unit in 23 suites (257 + this pass's new gate
test + tests added concurrently) · **21/21** Worker helper · **29/29** Worker
route (27 + 2 new cap tests) · profile-cap fix mutation-tested · `node --check`
clean · catalog **1077** keys, es/zh-Hans complete (only symbols/brand
untranslated) · `build-for-testing` succeeds.

---

## Fifteenth review pass (2026-08-13) — full-tree review, small cleanups

A comprehensive review of everything on the branch (committed + working tree)
against the plan docs. **No new blockers found.** The sync/gate/worker
architecture, the paywall fallback, family sharing and the reconciliation flow
all hold together and match what the earlier passes recorded. Small fixes:

- **Dead "Family sharing is coming with Tadah Plus" alert removed** from
  ProfileView. Nothing has set `showPlusComingSoon` since the paywall got its own
  coming-soon screen, so the alert was unreachable — and its two catalog strings
  were still translator-visible. Both deleted. Catalog: **1022** strings.
- **`SessionStore.markSetupComplete()` removed** — never called; the durable
  guard is `ReconciliationGate`, not the session's `setupComplete` flag. (The
  flag itself stays: it's written into existing Keychain sessions, and removing
  the field would sign those devices out on decode.)
- **A succeeded retry now retracts the failure alert.** `keepLocalTasks` sets
  both `reconciliationFailed` and `isShowingReconciliation` on failure; if
  SwiftUI happened to present the question first and the retry succeeded, the
  still-true failure flag would present "We couldn't finish that" *after* it
  visibly finished. Success paths now clear it.
- **"What to Test" no longer points at the removed Backup row** (EN + 中文) —
  the fourteenth pass deleted the row from Profile, but the tester notes still
  said "Check Profile → Backup shows 'Backed up …'".

**Second round of the same pass — the two deferred items were then fixed:**

- **A failed family removal now says so.** `FamilySharingView.remove()` swallowed
  the throw with `try?`, so a failure left the person sitting in the grid with no
  explanation — which reads as the app ignoring the tap. It now shows "Couldn't
  remove" and does **not** nudge a sync for a no-op. The copy claims "nothing was
  changed" and that is literally true: both of `ProfileStore.delete`'s throw
  points (the owner guard, the child-item fetch) happen before it mutates
  anything. Localized es + zh-Hans. Catalog: **1024** strings.
- **The dead code is gone.** `TaskBackup.swift` (and its snapshot/restore test)
  plus `SyncService.suppressPush` / `resetCursor` were deleted. They were the
  machinery of the destructive path: a local backup to guard a wipe, and the two
  halves of "pull everything, push nothing". With reconciliation now
  non-destructive there is nothing left for them to protect, and keeping helpers
  whose only purpose is discarding local state invites reintroducing exactly the
  bug class the fourteenth pass removed by construction. Verified no production
  caller existed, and no shipped build ever contained `TaskBackup` (it postdates
  build 2), so no device holds an orphaned snapshot that mattered.
- Two **stale comments** corrected while in there: `TaskDTO`'s header still
  described itself as the backup format, and `ProfileView`'s said the Family-Plus
  layout "isn't built here yet" — it is.

**Everything else deferred is now written down in `later_ideas.md` §8**
("Engineering debt from the build-4 review passes"), so it survives past this
file: the `URLProtocol` end-to-end gap for `SyncService.sync()` (§8a — the
biggest one), App Attest (§8b), the cap-preflight race (§8c), and the smaller
follow-ups including whether a "last backed up" reassurance should ever come back
(§8e). Live two-device verification stays on the checklist below (#6) because it
is an upload-time step, not debt.

**Verification (this pass):** **257/257** iOS unit in 23 suites — 258 before the
cleanup, minus the snapshot/restore test that went with `TaskBackup` · **21/21**
Worker helper · **27/27** Worker route, re-run after the `checkPlus` move ·
`node --check worker.js` clean · catalog validated as JSON with es/zh-Hans
complete (**1024** keys; the only untranslated entries are symbols and the brand
name) · `Tadah.storekit` prices confirmed to match the decided $6.99 / $59.99 ·
`git diff --check` clean.

> Note for anyone reading the logs: this run took three attempts, and the first
> two failures were **not** regressions. The working tree was being edited
> concurrently and the build twice caught `CreateView.swift` mid-save, with
> `$focused` / `Field` declared in `CreateView` while used in `CreateForm`. Every
> other file typechecked cleanly throughout; only that one batch failed. The
> third run, after the declarations moved into `CreateForm`, is the green one
> above.

---

## Fourteenth review pass (2026-08-12) — "Start fresh" removed

Six blockers and three gaps. Four of the blockers were **removed by
construction** rather than patched: they all existed only to make the destructive
"Start fresh / use your account's copy" option safe (photos are device-only so a
restore could never bring them back; the restore wasn't atomic; it wasn't wired
into sync; and it couldn't read v1 backup files). Rachel's call was to drop the
option entirely, which is also the better product answer — nothing in the app now
deletes a user's to-dos on their behalf.

- **The destructive option is gone.** Signing in as a *different* account offers
  only **"Move them to this account"** or **"Not now — sign out"**. Signing back
  into the account that already owns the local data **auto-merges with no
  prompt** — the question only appears when it's genuinely ambiguous.
- **`TaskBackup.swift` is reverted to `HEAD`.** The v2 format from the Thirteenth
  pass existed only to serve the restore path; with that gone, the shipped file is
  byte-identical to the committed one, so the v1-decode blocker is moot rather
  than fixed. *(This supersedes the TaskBackup and "reachable restore" bullets in
  the Thirteenth pass below.)*
- **Launch no longer mutates identity while blocked.** `sync.configure` runs
  first, and `ensureOwnerProfile` is skipped entirely when
  `isBlockedPendingReconciliation` — previously the owner profile was re-keyed
  before the user had answered the question.
- **The session is one checked Keychain value.** `Session {token, userID,
  setupComplete}` written and read as a single `Codable` record with a thrown
  `StoreError.keychain(OSStatus)`; three independent keys could previously tear.
  A failed sign-in now always reaches `abandonSession` → gate clear → session
  clear → `signOut()` → best-effort server `logout`.
- **Outgoing future timestamps are clamped.** A device with a wrong clock stamped
  `updatedAt` years ahead and then won every LWW comparison forever, on every
  device. Anything beyond a 5-minute skew horizon is repaired to `.now` before it
  is sent.
- **The pull watermark is one atomic value.** It was two `UserDefaults` keys, so a
  crash between the writes left a stamp with a mismatched id and silently skipped
  rows. Now a single dictionary, with a legacy two-key migration that reads the
  stamp alone. **Mutation-tested** (revert → 22/23, restore → 23/23).

**Found by running it (2026-08-12).** A Simulator run in 中文 showed
**"无法加载 Tadah Plus / 请检查网络连接后重试"** — the retry screen. The network was
fine: RevenueCat *throws* `.configurationError` (error 23) when there's no Current
Offering rather than returning an empty list, and `checkAvailability` sent every
thrown error to `.couldNotLoad`. So the one permanent condition we actually expect
right now was being reported as a transient one, telling the user to check their
connection and offering a Retry that could never succeed. Errors are now
classified: `.configurationError` / `.productNotAvailableForPurchaseError` →
**"coming soon"**, everything else stays retryable (an unrecognised error must not
be able to hide a real outage behind a reassuring screen). Covered by
`PaywallAvailabilityTests` (4 tests) and **mutation-tested** — dropping error 23
from the list fails 1 of 4.

Localization: 6 new/changed strings in `es` and `zh-Hans` (the two new buttons,
the different-account message, "Sign-in didn't finish", and the setup-failure
copy). The two dead keys the removal orphaned — `Start fresh on this account` and
`Use my account's tasks` — were deleted from the catalog so no translator works on
strings the app can no longer show. Catalog is at **1016** strings.

**Honest boundary, unchanged:** photos attached to a to-do are still **device-only
and are not uploaded** with the cloud backup. This is now stated rather than
worked around — no path in the app claims to restore them.

**Still open (not blockers, documented):** the push-starvation and
envelope-authority fixes are covered at the helper level but not end-to-end
through `SyncService.sync()` — that needs `URLProtocol` stubbing. Deferred: App
Attest for AI-quota identity (a rotating `X-Cuevi-Install` still bypasses the
quota), and the cap preflight race outside the D1 batch.

**Verification (this pass):** clean **Release** build, **no source warnings**
(the only match is the `appintentsmetadataprocessor` tool note — this run did
*not* filter it) · **249/249** iOS unit · **5/5** iOS UI · **21/21** Worker
helper · **27/27** Worker route · `npm audit --omit=dev` 0 vulnerabilities ·
`wrangler deploy --dry-run` clean (38.85 KiB) · `git diff --check` clean.
The iOS UI suite failed once as `testLaunch` / "Timed out waiting for AX loaded
notification" while a Release build competed for the simulator; it passed 5/5
after a `simctl` reboot with nothing else running. Harness flake, not a
regression. Re-run after the catalog cleanup and the paywall fix:
**253/253** unit (249 + 4 new), build green, `git diff --check` clean.

**Nothing is committed.** The whole pass is working-tree only, per instruction.

---

## Thirteenth review pass (2026-08-12)

Six blockers, all fixed:

- **"Add/Move local tasks" never cleared the durable gate**, so `run()` saw the
  disk flag, refused, and re-asked — permanently, across every relaunch. (My
  earlier edit matched the wrong block; only `useAccountTasks` had it.) Now
  cleared, and **mutation-tested**.
- **A process-death window between authentication and the gate.** The Keychain
  session was durable before anything blocked it. `SessionStore.adopt` now raises
  the block and persists the credential in one call, block first — also
  mutation-tested. A `.setupIncomplete` block found at launch hands the session
  back rather than guessing.
- **"A backup is saved either way" is now true.** `TaskBackup` v2 includes
  **profiles and profile tombstones** (replacement deletes those too, so family
  identities were unrecoverable), the snapshot's success is **checked** rather
  than `try?`-discarded, the destructive option is **hidden** when no backup
  exists, and there is a **reachable restore** in Account Details — the copy now
  points at something real.
- **"Use account tasks" cleared the gate too early** — before the owner claim,
  push suppression and cursor reset were durable. It's now the final commit.
- **Paged pushes could starve a stream forever.** One shared budget spent in
  category order meant 25 changed profiles + 1 changed task sent the same profiles
  every pass and never the task. Tasks and profiles now have **independent
  watermarks and budgets**.
- **The client discarded the server-authoritative envelope.** It decoded only the
  opaque payload, throwing away the id/timestamp the Worker had validated and
  clamped — losing sub-second LWW ordering, re-introducing future-dated stamps,
  and never checking that the payload id matched. Pulled DTOs now take the
  envelope's timestamp and are rejected if their id disagrees.

Also: launch now restores the gate **before** `ensureOwnerProfile` mutates local
identity; the Swift 6 main-actor conformance warning is fixed; `AccountDetailsView`
was missing its `SwiftData` import (a real Release warning).

**Not fixed, deliberately:** the storage-ceiling preflight is still a read outside
the batch, so concurrent syncs can overshoot it by a row or two. Folding the count
into the INSERT was tried and **rejected** — SQLite won't accept a subquery over
the target table in an upsert, and it broke every sync write. Documented in
`worker.js`. This is a storage safety net, not a billing boundary.

**Also found while verifying:** my own new tests wrote `LocalDataOwner` to the
shared `UserDefaults`, and Swift Testing runs suites in parallel — which broke four
owner-identity tests. They now pass `previousAccountOverride` explicitly and are
hermetic; the suite was re-run twice clean to confirm.

**Verification:** Release build succeeds (one benign AppIntents warning) ·
**246/246** iOS unit (×2 runs) · **5/5** iOS UI · **21/21** Worker helper ·
**27/27** Worker route · audit clean · dry-run clean · `git diff --check` clean.

---

## Twelfth review pass (2026-08-12)

- **The reconciliation gate didn't survive a relaunch.** `pendingReconciliation`
  lived only in memory, while the account and session were already on disk — so
  killing the app before answering the cross-account question discarded the one
  thing standing between account A's data and account B's backup. Relaunch built a
  fresh coordinator with no question, startup called `syncNow`, every guard
  passed, and A's to-dos uploaded into B. Same leak as before, resurrected through
  process death.
  New **`ReconciliationGate`** persists it, scoped to the session user, restored in
  `configure()`, and cleared only once a reconciliation has actually been carried
  out. `run()` checks the persisted flag as well, so no path — lifecycle, edit
  nudge, or relaunch — can slip past the in-memory copy.
- **The local sign-out on setup failure wasn't actually guaranteed.** It used
  `account?.signOut()` on a stored optional that is nil until `configure()` runs,
  and both new tests used an unconfigured coordinator — so the assertion that
  mattered was never exercised. `afterSignIn` now takes the `AccountStore`
  **explicitly**, making it impossible to reach that path without one, and the
  tests assert `!account.isSignedIn`.

**Tests:** a relaunch test builds a **fresh coordinator** and confirms the
question comes back verbatim; another confirms a gate raised *after* configure
still blocks syncing (the case that exercises `run()`'s check rather than
`syncNow`'s in-memory guard). All three guarantees — gate restore, `run()` check,
local sign-out — were **mutation-tested**: removing each fails exactly the tests
that should catch it.

**Verification:** Release build succeeds (one benign AppIntents warning) ·
**244/244** iOS unit · **5/5** iOS UI · **21/21** Worker helper · **27/27** Worker
route · audit clean · dry-run clean · `git diff --check` clean.

---

## Eleventh review pass (2026-08-12)

- **A failed sign-in setup left the device authenticated.** `AuthService` writes
  the session to the **Keychain** the moment the Worker issues it — before owner
  migration runs. So rolling back the store and returning `.failed` left that
  session live *and persisted*: the next edit or foreground would pass syncNow's
  checks (valid session, no pending question) and sync an identity whose
  canonical-owner migration never completed. Surviving relaunch is exactly why an
  in-memory "it failed" flag would not have covered this.
  The failure path now **abandons the session**: clears the Keychain first (so
  nothing can use it, even after a relaunch), signs the account out locally, then
  best-effort revokes that specific token via a new `AuthService.logout(token:)`.
  Two tests assert `.failed` leaves `SessionStore.isAuthenticated == false` and
  that a subsequent `syncNow` does nothing — **both fail if the fix is reverted**.
- `account` is now a **strong** reference like `profiles`. A weak one would have
  silently no-op'd the sign-out and left the UI showing a signed-in account with
  no session behind it.
- **Sign-in no longer claims "signed in on this phone only" after a setup
  failure** — the session has been given back, so the user is *not* signed in.
  A distinct `setupFailed` state says so, with a Try again.
- **Removed two `assertionFailure` traps** (`requireProfiles`, `run`). Both sit on
  deliberately-handled, recoverable paths; trapping turned "fail safe" into a
  Debug crash and made the failure path impossible to test — which is how the new
  tests found them.

**Verification:** Release build succeeds (one benign AppIntents warning) ·
**239/239** iOS unit · **5/5** iOS UI · **21/21** Worker helper · **27/27** Worker
route · audit clean · dry-run clean · `git diff --check` clean.

---

## Tenth review pass (2026-08-12)

- **The cap preflight and the actual write disagreed on ties.** I declared
  "a tie goes to the delete" in the preflight, but the batch ran CHANGES first and
  every conflict clause needs a strictly newer stamp — so the change won and the
  row stayed live. At the ceiling, one id sent as both a change and a same-stamp
  delete passed the check as "deleted" and left **201** live tasks; the same trick
  bypassed the profile cap. Fixed by making the database match the declared
  policy: **deletions are collected separately and executed first**.
  The tie tests now assert the **stored row is tombstoned** and the live count is
  still capped, instead of only checking for HTTP 200 — and there's a profile
  equivalent. Both fail if the ordering is reverted.
- **The race test no longer sleeps.** It synchronises on the body stream's second
  read — which can only happen after the handler has authenticated — so there's no
  timer to lose a race with, and it now requires **exactly 200** rather than
  accepting 200-or-401 (which would also have passed if the session had been
  deleted *before* auth, a different and already-covered case). Still
  mutation-tested against the `WHERE EXISTS` guard.
- **`profiles` is no longer weak or optionally-chained on destructive paths.**
  `try profiles?.bindOwner(...)` silently succeeded when the store was missing,
  which would let a destructive reconciliation commit with no owner established.
  It's a strong reference now, and `requireProfiles()` throws before anything is
  mutated.
- **Restore errors are distinguishable again.** `PlusStore.restore()` returned a
  bare Bool built on `try?`, so a network failure told a paying user they'd never
  bought anything. It now returns `.restored` / `.nothingToRestore` / `.failed`,
  and the paywall words the retryable case differently.
- **21 new user-facing strings localized** (es + zh-Hans): the reconciliation
  prompts and failure alert, the store-load alert, all account-deletion messages,
  the sign-in failure copy, and the whole paywall fallback including Restore.
  Catalog: 1015 strings.
- **Node floor raised to 22.12** (`engines` + `.nvmrc`), matching what the
  Vite/Rolldown toolchain actually needs; `package-lock.json` regenerated so the
  engine declaration is recorded there too.

**Verification:** Release build succeeds (one benign AppIntents warning) ·
**237/237** iOS unit · iOS UI green · **21/21** Worker helper · **27/27** Worker
route · schema applies twice · audit clean · dry-run clean.

---

## Ninth review pass (2026-08-12)

- **⚠️ The bindOwner fix from the previous pass was never actually in the file.**
  My edit was a text substitution whose pattern didn't match; it silently did
  nothing, the build still succeeded, and I reported it as done. `bindOwner` was
  still calling the non-throwing `reload`. It now uses `reloadThrowing`, and —
  the part that mattered more — a **successful-but-empty read CREATES the
  canonical owner** instead of returning. That second bug broke same-account
  "Use the account's tasks", which deletes every profile and then calls bindOwner:
  the account was left with no owner and every task orphaned. Covered by a test
  that fails when the fix is reverted.
- **Cap preflight now resolves each id to its FINAL state before counting.** Two
  separate passes over `changes` and `deletes` meant an id in BOTH arrays was
  counted by whichever pass ran last, not by which write wins — so a task created
  and then tombstoned in one request was counted live and 409'd a request that
  would have stored nothing. Ties against a server row now match the upserts'
  strict `>`; ties within one request go to the delete. Same fix for profiles.
- **Paywall fallback no longer hides Restore Purchases.** RevenueCat's paywall is
  the ONLY place in the app that offers restore, so replacing it stranded anyone
  who had already paid — and Apple requires a restore path. Every fallback state
  now carries one. A transient fetch error is also distinguished from "nothing is
  on sale yet" and offers **Try again**.

**Test/tooling fixes:**
- The task-cap test seeded ONE task against a ceiling of 200 — the broken
  implementation passed it too. Now seeds **200** and tests: swap at the ceiling,
  refusal past it, a stale update to a tombstoned task, create-then-delete, and a
  same-timestamp tie.
- The deletion-race tests no longer copy SQL into the test or rely on
  `Promise.all` timing. One **deterministic** test drives the production handler
  with a body stream it controls: the handler authenticates, waits on the body,
  the session is deleted, the body completes, and the write executes with a dead
  session. **Mutation-tested** — neutralising the `WHERE EXISTS` guard fails it.
- `engines.node >= 22` and `.nvmrc` added; the stack cannot run on the machine's
  default Node 20.6.
- `isolatedStorage` / `singleWorker` removed from `vitest.config.js` — not current
  pool options, silently doing nothing.

**Verification:** Release build succeeds (one benign AppIntents warning) ·
**237/237** iOS unit · **5/5** iOS UI · **21/21** Worker helper · **26/26** Worker
route · `npm audit --omit=dev` 0 vulnerabilities · dry-run clean.

> On the previous pass's "236/236": that run did complete here, but the reviewer's
> stalled. Either way the number above is the current one.

---

## Paywall + UI-test pass (2026-08-11, latest)

- **RevenueCat "Error 23" no longer reaches the user.** See decision #1 at the top
  of this file: `PaywallView` resolves the offering itself and falls back to a
  "coming soon" screen. Verified on the simulator with a screenshot.
- **`Tadah.storekit` + a shared `Tadah.xcscheme`** — the project had no shared
  scheme at all (Xcode was auto-generating one), so there was nowhere to attach a
  StoreKit configuration. Both are now committed, which also makes the build
  reproducible for anyone else who opens the project.
- **The UI suite is green again — all 4 tests + launch tests.** Both pre-existing
  failures were stale selectors, not app bugs:
  - `testTabsNavigate` looked for a *static text* "To-Do"; that's a tab-bar
    **button**, and the masthead has read "To-Dos & Reminders" since the clarity
    pass. It was failing on its very first assertion.
  - `testGuideFlowAddsItemToInbox` looked for a *static text* row title; inbox rows
    became **buttons** when swipe-to-complete landed. The item was on screen the
    whole time — the hierarchy dump showed `label: 'Prepare to file taxes'` and
    "1 active" — the lookup just couldn't see it.
  - `setUpWithError` now pins **portrait**; the tests otherwise inherit whatever
    rotation the simulator was left in, which changes layout.
- New UI test: **UPGRADE never surfaces a raw store error** (asserts the sheet
  actually opened first, so it can't pass vacuously, and attaches a screenshot).

**Verification:** Release build succeeds (one benign AppIntents warning) ·
**236/236** iOS unit · **4/4 + launch** iOS UI · **21/21** Worker helper ·
**23/23** Worker route · dry-run clean.

---

## Eighth review pass (2026-08-11, later)

- **Byte-paged pulls reported `more: false` when truncated.** The SQL stops at the
  last row that FITS, so "bytes spent >= budget" was never true and truncation
  looked like completion — 41 of 50 rows returned, the other 9 stranded until some
  later lifecycle sync, so a first sign-in could settle with an incomplete
  account. `more` now comes from an existence probe past the last returned row.
- **A failed reconciliation still lost the question.** The alert's dismissal
  binding cleared `pendingReconciliation` the moment a button was tapped, so by
  the time the async work failed there was nothing to re-ask with. Presentation
  state (`isShowingReconciliation`) is now separate from the question, and a
  failure puts the alert back.
- **`bindOwner` still swallowed its first read.** It called the non-throwing
  `reload`, which keeps its last-good list — with an empty cache that failure
  looked like "no profiles at all", so bindOwner fell through its `guard` and
  reported success having bound nothing. It now uses a throwing fetch; last-good
  behaviour stays where it belongs, on UI reloads.
- **The task ceiling repeated the cap/LWW bug class** — it ignored winning deletes
  in the same request and counted stale updates to tombstoned rows. Now computed
  on the final LWW state. It is also **named and documented for what it is**: a
  per-account STORAGE ceiling (200/2000), not tier enforcement. The commercial
  limits are 20/100 **per profile** and live in the app; the server can't see
  profile membership, so an account-wide 20 would break a legitimate family.
- `MAX_PAYLOAD` is a byte budget and now uses `byteLength`, not `String.length`.

**Test-quality fixes (the criticism was right):**
- The old "deletion race" test only exercised the 401 gate. There are now three:
  the conditional write itself (live session → row lands; session gone → no-op), a
  genuinely **concurrent** sync-vs-deletion via `Promise.all` asserting the
  invariant, and the 401 case.
- The profile-migration test ran with RevenueCat unknown, i.e. the **Plus** cap of
  8 — so the old wrong count of 2 passed it. `vitest.config.js` now stubs
  RevenueCat via miniflare's `outboundService` to a subscriber with no
  entitlements, pinning the **free** tier where the caps actually bite.
- Added route tests for byte-paged pulls (two pages, 41 + 9, no loss, no dupes)
  and for cap/LWW arithmetic.
- **Each fix was mutation-tested**: reverting the profile-cap subtraction, the
  stale-tombstone LWW check, and the `more` probe each fails exactly one test.

**Verification:** Release build succeeds (one benign AppIntents metadata warning)
· **236/236** iOS · **21/21** Worker helper · **23/23** Worker route ·
`npm audit --omit=dev` 0 vulnerabilities · dry-run clean.

---

## Seventh review pass (2026-08-11)

- **The isolated sync context couldn't see unsaved edits.** Making sync private
  fixed rollback but introduced a worse bug: a private context sees only what is
  PERSISTED, and the create/edit/delete paths nudge a sync without saving. The
  pass looked at an empty store, pushed nothing, then advanced the watermark past
  the edit it never saw. Sync now flushes the main context first.
- **"Start fresh" was destructively non-atomic.** It cleared the prompt, cancelled
  reminders and started deleting while later fetches could still throw — leaving a
  half-wiped device, disarmed alarms, and no way back to the question. Now it's
  four phases: read everything → mutate and commit → cancel reminders → clear
  state. On failure it rolls back and the prompt returns (`reconciliationFailed`),
  instead of the UI swallowing the error.
- **The pull's memory bound was applied too late.** Truncating in JS still let D1
  materialise ~100 MB first. The budget now lives IN the SQL (a running
  `SUM(LENGTH(CAST(payload AS BLOB)))` window), so only rows that fit are ever
  serialised — verified: 50 rows × 100 KB in the table → 41 returned under a 4 MB
  budget. Byte counts use `TextEncoder`, not `String.length`.
- **The profile cap could wedge a client permanently.** It read only LIVE rows, so
  a stale update for a server-tombstoned profile counted as new even though its
  upsert would lose LWW — a free account could then never get past a 409. The cap
  is now computed on the final LWW state, using live *and* deleted rows.
- **Owner-migration errors were swallowed.** All three `bindOwner` calls used
  `try?`, and bindOwner mutates profiles before its child fetch can throw — so
  sign-in continued and SYNCED a half-migrated identity. They now roll back and
  propagate (`SignInOutcome.failed`, surfaced on the sign-in screen).
- `ProfileStore.reload` keeps its last good list instead of turning a storage error
  into "this account has no profiles" (which reads as "no owner" and invites a
  duplicate).
- **Server-side task ceilings** added (`FREE_TASKS` / `PLUS_TASKS`), so a modified
  client can't store unbounded rows — the volume needed to threaten pull memory.

**Route-level Worker tests added** — `@cloudflare/vitest-pool-workers`, real
workerd + real D1, isolated per-test storage: **18 tests** covering routing, the
auth gate, revoked sessions, LWW, id validation, batch limits, cross-account
scoping, the **deletion race**, the **owner-migration cap case**, AI-proxy guards
and metrics idempotency. `npm test` now runs helpers **and** routes.

**Verification:** Release build succeeds · **236/236** iOS unit · **21/21** Worker
helper · **18/18** Worker route · `npm audit --omit=dev` 0 vulnerabilities ·
dry-run clean · schema applies twice.

> **Two corrections to earlier claims in this file.**
> 1. "No warnings" was wrong. The Release build emits one benign
>    `appintentsmetadataprocessor` warning ("No AppIntents.framework dependency
>    found"). I had been filtering it out of my own grep, which is how it went
>    unnoticed. There are no warnings in app *source*, but the build is not
>    literally warning-free.
> 2. The "wired to the RevenueCat **test store**" note at the top of this file was
>    stale — the production `appl_…` key is in place. Corrected there.

---

## Sixth review pass (2026-08-10, final)

- **Paged pushes could skip records sharing a timestamp.** Same class of bug the
  pull cursor had, now on the push side: 26 records stamped T → send 25, mark = T,
  next pass filters `> T` and record 26 is gone forever. The push watermark is now
  **composite (timestamp, id)**, the page is sorted in that same order, and a
  partial page lands the mark exactly on the last record sent. Pinned by a test.
- **Rollback could erase the user's own edits.** Sync shared the main context, so a
  failed apply discarded everything pending — including whatever the user typed
  while the request was in flight. Their edits are not ours to throw away. Sync now
  takes the **container** and works in its own `ModelContext` with autosave off, so
  rollback is confined to sync's changes; SwiftData still propagates the save to
  the UI.
- **Reminder CANCELLATION also happened before commit.** Rollback restores the
  store but cannot un-cancel a notification, so a failed pass silently disarmed
  alarms for to-dos that still exist. Cancellations are collected and executed
  only after the save, alongside the reschedules.
- **Profile cap didn't model last-write-wins.** Every submitted tombstone was
  subtracted before checking whether it could actually delete the server row — so
  a stale tombstone bought room for a new profile and bypassed the free cap. It
  now subtracts only deletions that will genuinely win.
- **Account deletion raced an in-flight sync.** A sync validated its session,
  deletion erased every row, and the sync then recreated the tasks — deletion
  returning success with the account resurrected behind it. All four sync writes
  are now conditional on the session still being live (`WHERE EXISTS (… sessions
  …)`), verified against sqlite: live session → row lands; session deleted → the
  write is a no-op.
- **Pull responses could exceed Worker memory.** 1,000 rows × 100 KB payloads is
  100 MB against a 128 MB ceiling. Responses are now capped by **bytes** as well as
  rows, the cursor advances to the last row actually *taken*, and `more` accounts
  for size-truncation so nothing dropped is skipped.
- Remaining destructive `try? … ?? []` paths are throwing: removing a family member
  (a failed child read used to delete the profile and strand their to-dos), "use
  account tasks", and the reconciliation count — where a swallowed error would have
  read as "this device is empty" and skipped the cross-account prompt entirely.

**Verification:** clean **Release** build, no warnings · **236/236** unit ·
**21/21** Worker · dry-run clean · schema applies twice.

**Known gap, stated plainly:** the Worker tests are still helper-level. Route-level
coverage (auth, D1 transactions, profile caps, the deletion race, full sync) needs
`@cloudflare/vitest-pool-workers`. Three of this pass's blockers lived in exactly
that untested layer.

---

## Fifth review pass (2026-08-10, later still)

- **Owner migration still hit the free profile cap.** The Worker counted the old
  profile and the new canonical one *before* applying the tombstone in the same
  request, so a free account measured 2 against a cap of 1 and got a 409 — the
  migration could never complete on exactly the accounts that need it. Deletes in
  the batch are now subtracted before the count.
- **The request-size limit was bypassable** — confirmed by reproduction: an
  80,008-byte body was accepted as "40,008" because `String.length` counts UTF-16
  units, not bytes, and the whole body was buffered before the check anyway.
  `readJSON` now reads the stream chunk by chunk, counts real bytes, and cancels
  the moment the ceiling is crossed.
- **Batch sizes exceeded D1 Free's 50-queries-per-invocation limit.** 500
  records/events could never be stored, so the write failed, the cursor never
  advanced, and the same doomed request retried forever — a backup that silently
  never happened. Server limits are now 25, the **client pages its pushes**
  (`SyncService.maxRecordsPerPush`) with a watermark that only advances past what
  was actually accepted, and metrics upload in chunks.
- **Pulled changes weren't transactional.** Partial mutations sat in the
  ModelContext after a mid-apply failure and could be persisted by any later save.
  The whole apply stage now rolls back as a unit, and **reminders are scheduled
  only after the save commits** (previously a rolled-back pass could still leave
  iOS holding alarms for items that never landed).
- **Owner migration could orphan tasks** — its item fetch was `try? … ?? []`, so a
  failed read looked like "no children" and the profile was deleted anyway. Now
  throwing.
- **Cross-account data was transformed before consent.** `bindOwner` ran before
  the move/start-fresh decision. Worse, re-keying carried the existing profile's
  NAME onto the new account's owner id — signing in as B on A's phone produced an
  owner for B literally called "Ana". Binding now runs only after consent, and a
  foreign owner is **demoted and left under its own id** while a fresh owner is
  created. The old test passed trivially (it only checked *some* profile named Ana
  existed); it now asserts B's owner is not wearing A's name.
- RevenueCat configuration is verified **before** Apple revocation begins, so a
  misconfigured Worker can't produce an avoidable partial deletion.
- Timestamps are **normalized** to one canonical ISO-8601 form before storage —
  `…Z`, `…+00:00` and `…-04:00` of the same instant compared differently under the
  lexical ordering the cursor and LWW upserts rely on.
- Analytics salt generation now checks `SecRandomCopyBytes` and falls back rather
  than silently using an all-zero key.
- Legal copy: retries are described as **safe to repeat**, not "never repeats
  completed work" — Apple revocation is deliberately repeated on retry.

**Verification (this pass):** clean **Release** build, no warnings in app code ·
**234/234** unit · **21/21** Worker · `wrangler deploy --dry-run` clean · byte-limit
bypass re-tested and now returns 413.

**Still open, explicitly:** route-level Worker tests (auth, deletion retries, D1
rollback, profile caps, quotas) — the 21 tests cover pure helpers only. Closing
this needs `@cloudflare/vitest-pool-workers` and real bindings. And App Attest,
as before.

---

## Fourth review pass (2026-08-10, later)

Six more blockers, all fixed:

- **Profile deletion discarded newer task edits.** Reassigning a survivor called
  `touch()`, which made the local copy newer than the very DTO about to be
  applied — so the incoming edit from another device was skipped. The apply stage
  is now explicitly ordered: **profile changes → tasks → profile deletions**, so
  the cascade sees each task's final state and never has to guess. The old test
  only asserted the task *survived*; it now asserts the **edited title** survives,
  which is what the previous version silently lost.
- **Owner migration couldn't sync.** Re-keying the owner locally left the old
  random-id profile on the server, so a free account looked like it had two
  profiles and the canonical owner was rejected with a 409. Migration now writes a
  **ProfileTombstone** for the old id, adopts a canonical owner that already
  arrived from another device instead of inserting a duplicate, and duplicate
  resolution prefers the **canonical** id rather than merely the oldest (which
  could demote the canonical owner and flip-flop forever).
- **Deletion retries left a live Apple grant.** The app re-authorizes on every
  retry, creating a new grant, but the Worker skipped the code once
  `progress.apple` was set — so the fresh grant was never revoked. Any submitted
  code is now always revoked.
- **Missing `REVENUECAT_SECRET` counted as a successful deletion.** The app
  configures RevenueCat with its own public key, so subscriber records exist
  whether or not the Worker secret is set. It now **fails closed** with a 501.
- **The final delete wasn't atomic.** The progress row was removed *after* the
  batch that drops `sessions` — if that statement failed, the user could no longer
  authenticate to retry their own deletion. It's now in the same D1 batch.
- **Public routes parsed unbounded bodies.** Every route now goes through one
  `readJSON()` that enforces both the declared `Content-Length` and the bytes
  actually read (a chunked request can omit or lie about the header).

Also: all apply-stage SwiftData fetches are throwing; `wrangler.toml` moved to the
**stable `[[ratelimits]]`** binding (the experimental-`unsafe` warning is gone);
Worker tests grew to **21** and now cover the bounded reader.

**Verification (this pass):** clean **Release** build, no warnings in app code ·
**234/234** unit tests · **21/21** Worker tests · `wrangler deploy --dry-run`
clean, no warnings · schema applies.

> **Correction to earlier entries in this file.** Previous passes recorded
> "216/216" and "223/223"; those counts were accurate when written but are
> superseded — the current number is 234/234. Earlier wording also promised
> deletion was all-or-nothing; that was never achievable once Apple's revocation
> is involved, and the copy now describes resumable partial completion instead.

**Still deferred:** App Attest (see below), and route-level Worker tests against
real bindings (the current 21 cover pure logic only; auth, deletion retries, D1
rollback, profile caps and quotas are verified by live probes, not automated).

---

## Third review pass (2026-08-10)

A deeper review of `54ae0e3` confirmed the earlier fixes landed but found eight
more. Seven are fixed here; the eighth (App Attest) is deferred — see below.

- **Analytics were still re-identifiable.** Events uploaded the raw
  `ActionItem.id`, and the *same* UUID is stored as `tasks.item_id` beside
  `tasks.user_id` **in the same D1 database** — one JOIN attached every
  "anonymous" event to a named Apple account. The upload now sends
  `HMAC(per-install salt, itemID)` instead: stable within an install (the
  confirm→complete funnel is unchanged) and unjoinable with anything, because the
  salt never leaves the device. Fixing the install-id linkage last round was only
  half of it, and the manifest/policy claimed "not linked" on that basis.
- **Owner profiles could duplicate or transfer between accounts.** The owner is
  created before any sign-in, with a random id — so every device pushed its own
  "owner", and account A's leftover owner could be pushed into account B under A's
  name. The owner id is now **derived from the Apple user id**
  (`Profile.ownerID`), so all devices converge on one and a different account
  computes a different one. Sign-in re-keys and de-duplicates (`bindOwner`),
  pulled duplicates are demoted rather than deleted, reconciliation counts a
  foreign owner profile, and `hasServerData` now considers profiles as well as
  tasks.
- **Deletion could revoke the wrong Apple account's grant.** The Worker exchanged
  the authorization code without checking who it belonged to, so a session for A
  could revoke B's grant. The returned `id_token` is now fully verified and its
  `sub` must equal the session's user.
- **Deletion reported success when RevenueCat failed.** The result is now checked
  (200/404 = done, anything else = failure). Because Apple's revocation is
  irreversible the sequence genuinely cannot be atomic, so deletion is now
  **resumable**: each completed step is recorded in `account_deletions` and a
  retry picks up where it stopped. The legal copy says this plainly instead of
  promising "if any step fails, nothing is deleted".
- **Sync could skip data after a local storage failure.** Fetches were
  `try? … ?? []`, so a read failure looked like "nothing to push" and the
  watermark advanced past unsent edits. They now throw. The cursor/watermark are
  also written **after** an explicit `context.save()`, not before.
- **Profile deletion could corrupt task relationships.** It now sees the incoming
  task page, so a task newer than the removal survives instead of being deleted
  and immediately re-created pointing at a missing profile — and survivors are
  `touch()`ed so the reassignment actually syncs.
- **A 401 could leave the UI falsely signed in.** `run()` took an optional
  `AccountStore` and the sign-in paths passed none, so `account?.signOut()` did
  nothing. It's now required.

**Deferred: App Attest (AI quota identity).** Rate-limit and quota keys still come
from caller-supplied headers, which is inherent to an anonymous endpoint whose
token ships in the app. The real fix is App Attest or a server-minted credential.
For a 10-person beta the OpenAI spending cap is the actual money backstop; this is
tracked, not done.

**Verification:** clean **Release** build, no warnings in app code;
**231/231** unit tests; **15/15** Worker tests; schema applies clean.

> Note on the reviewer's "test runner hung for 17,576s": not reproducible. Both a
> full run and targeted runs complete in normal time here.

---

## Second review pass (2026-08-09)

The first pass fixed the account/sync blockers; a follow-up review found more.
Fixed here:

- **Account deletion no longer lies.** A 401 was being treated as success, so an
  expired session reported "deleted" while the server still held everything.
  Deletion now also **revokes the Sign-in-with-Apple grant** (Apple TN3194 — new
  `/auth/revoke` exchange in the Worker, needs the Apple key secrets below) and
  **deletes the RevenueCat subscriber**. It asks the user to re-authorize with
  Apple first, which supplies the authorization code and doubles as confirmation.
  If any step fails, nothing is deleted and the app says which step failed.
- **Deleting an account no longer arms the next leak.** It used to release the
  local-data ownership claim while leaving the to-dos on the phone, so the next
  account to sign in saw them as unclaimed guest data and uploaded them. The
  claim now stays.
- **Reconciliation covers family profiles.** It counted only tasks, and "use the
  account's tasks" left profiles and profile tombstones behind — so one account's
  family members could reach another account.
- **A sync in flight can't mix accounts.** Passes are bound to a userID and
  re-check the session identity before touching the store.
- **Outbound encode failures abort the pass** instead of dropping the record while
  the watermark advanced past it (silent loss of a user's edit).
- **Inbound is now genuinely all-or-nothing** — everything is decoded before
  anything is applied. Previously a malformed *profile* left task mutations
  already written with the cursor unmoved.
- **Profile deletion respects per-task timestamps** and can never delete the owner
  profile. A removal used to cascade over every child task unconditionally.
- **"Everyone" to-dos survive relaunch.** `profileID == nil` now means "for the
  family", but the pre-profiles backfill still ran on *every* launch and
  reassigned them all to the owner. It is now a one-time migration.
- **Sign-in says "backed up" only after a sync round trip actually completes**, and
  "Try again" re-runs the Apple authorization — replaying the stored token could
  never work, since the server burns each nonce.
- **Analytics are genuinely unlinked.** `Install.id` was sent both as the metrics
  `installID` and as the auth `deviceId`, which the Worker stores beside the Apple
  user id — so the two tables could be joined and every "anonymous" event tied to
  a named account. There are now two independent random ids (`Install.id` for
  metrics, `Device.id` for sessions).
- **AI proxy input is bounded.** 128 KB request cap, max 12 messages, 40 K chars
  each, text-only (no image/multimodal content), and the upstream body is rebuilt
  from an allow-list instead of forwarding the caller's object — `n`, `stream`,
  tools and any future billable parameter are no longer reachable. The quota also
  fails closed when D1 is unbound.
- **Profile cap is per tier** (free = 1) and enforced server-side; the sync batch
  limit now counts profile records too.
- **Worker tests exist** — `cd Tadah/cloudflare-worker && npm test` (15 tests,
  Node's built-in runner, no new dependencies). Config: compatibility date
  refreshed and observability enabled.

**Verification:** clean **Release** build, no warnings in app code;
**223/223** unit tests pass; **15/15** Worker tests pass; `wrangler deploy
--dry-run` succeeds; `npm audit --omit=dev` reports 0 vulnerabilities.

> The reviewed snapshot failed to compile because `AssigneeRow.swift` was
> untracked — it was committed in `33f3917` and the Release build passes.
> The four family strings reported missing (`Everyone`, `Just mine`, `For`,
> `Who is this for?`) are present with es/zh-Hans translations.

**Still open (in-progress feature work, deliberately not touched):** a
reassignment control on DetailView, and the paywall/purchase decision below.

---

## Build-4 review fixes (2026-08-08)

An external review found the account/sync system could leak tasks between
accounts, keep "deleted" account data, and lose newer edits. All of the
**already-built** parts are now fixed (family sharing and the Plus paywall were
still in progress and were deliberately left alone):

- **Account deletion is real.** New Worker `POST /account/delete` erases the
  account's tasks, profiles and sessions; the app calls it and, if it fails, says
  the account was *not* deleted instead of falsely confirming. (Apple requires
  in-app deletion of the account and its data.)
- **Sign-out revokes the session server-side** (`POST /auth/logout`), so the
  privacy policy's "signing out ends the session" is now true.
- **A stale server tombstone can no longer erase a newer local edit** — deletions
  carry `deletedAt` and obey last-writer-wins like any other write.
- **Malformed server data is no longer skipped forever** — a page that fails to
  decode now fails as a whole and is retried; the Worker *rejects* oversized
  payloads instead of truncating JSON mid-value.
- **A new account can no longer upload the previous user's to-dos.** Local data
  now carries an owner marker; signing in as someone else prompts instead of
  auto-seeding.
- **⚠️ The build-2 → build-4 migration was genuinely BROKEN, not just untested.**
  `TadahSchemaV1`/`V2` pointed at the live `ActionItem`, so a real build-2 store
  matched no declared version and failed to open (`loadIssueModelContainer`) —
  every existing tester would have hit it. V1/V2 now nest frozen copies of their
  models, and `SchemaVersioningTests` writes a true build-2 store and reopens it.
- **An unopenable store is never deleted.** The old fallback wiped it; now the
  file is kept, the session runs in memory, and the user gets an explanatory alert.
- **Sign-in distinguishes local Apple auth from confirmed backup**, with a retry.
- **RevenueCat** `logIn` is awaited before the tier check, existing users are
  identified at launch, and `logOut()` runs on sign-out/delete.
- **Worker hardening**: install header required + quota fails closed (the AI cost
  cap was bypassable by omitting a header), `APPLE_AUDIENCE` mandatory, single-use
  sign-in nonces, session expiry, composite `(updated_at, id)` pull cursor
  (the old one silently dropped rows sharing a timestamp), UUID/timestamp
  validation, retention sweeps, and rate-limiting keyed on session/install before IP.
- Privacy manifest now declares user content, user id, name, email and purchases
  as **linked to identity**; anonymous analytics stay unlinked.
- `.wrangler/` untracked and gitignored; stale Profile UI-test assertion fixed.

**Verification:** clean Release-config build, no warnings in app code;
**216/216 unit tests pass** (was 170/194 with a stalled runner).

**Not touched (still in progress, per instruction):** family-sharing UI and its
Plus benefit copy, the paywall/purchase decision below, Dynamic Type, contrast,
dark mode, iPad/landscape, and new end-to-end UI tests.

> The Spanish "days overdue" / "Due in … days" gap the review reported is **not
> present** — all four deadline strings have translated `es` plural variations.

---

## Checklist

1. ☐ **Deploy the Worker** — now REQUIRED for more than the entitlement id:
   account deletion, logout, the tombstone/cursor fixes and the quota fix all live
   there. The RevenueCat entitlement id fix (`PLUS_ENTITLEMENT = "Tadah Pro"`,
   was `plus`) still applies too.
   `cd Tadah/cloudflare-worker && npx wrangler deploy`
   *(Node 22 needed: `export PATH="/usr/local/opt/node@22/bin:$PATH"`.)*
   - ☐ **Set `APPLE_AUDIENCE` first** — `npx wrangler secret put APPLE_AUDIENCE`
     with the bundle id `com.ruiqiwang.cuevi`. It is no longer optional:
     without it `/auth/apple` returns 503 and **nobody can sign in**. Deploying
     without setting it will break sign-in for everyone.
   - ☐ **Set the three Apple revocation secrets** — account deletion has to revoke
     the Sign-in-with-Apple grant, and Apple requires that of any app offering
     account creation. Without them `/account/delete` returns 501 and the app
     tells people to contact support:
     `npx wrangler secret put APPLE_TEAM_ID` (10-char Team ID),
     `npx wrangler secret put APPLE_KEY_ID` (Key ID of a Sign in with Apple key),
     `npx wrangler secret put APPLE_PRIVATE_KEY` (paste the whole `.p8` contents).
     Create the key at developer.apple.com → Certificates, Identifiers & Profiles
     → Keys → **+** → enable "Sign in with Apple". **This is required for App
     Store review**, not optional polish.
   - ☐ Re-run `npx wrangler d1 execute cuevi-metrics --remote --file=schema.sql`
     (adds `used_nonces`, `account_deletions` and `sessions.plus_checked_at`; the
     Worker also creates them lazily).
   - ☐ **Purge the historical analytics item ids.** Rows already in `events`
     contain RAW task UUIDs, which are joinable against `tasks.item_id` →
     `tasks.user_id`. New uploads send a salted HMAC instead, but the old rows are
     still re-identifiable and should not be kept:
     `npx wrangler d1 execute cuevi-metrics --remote --command "UPDATE events SET item_id = NULL;"`
     This blanks the funnel for pre-build-4 events (the counts survive; only the
     per-item matching is lost). Do it before the privacy label goes in.
   - ☐ **Also clear legacy session device ids.** Before the split, `Install.id` was
     sent BOTH as the metrics `install_id` and as the auth `deviceId`, so any
     session row created by a pre-fix build can still be joined to `events`:
     `npx wrangler d1 execute cuevi-metrics --remote --command "UPDATE sessions SET device_id = '';"`
     Harmless — `device_id` is only used to recognise a returning device, and the
     worst case is one extra sign-in. Until this is run, "analytics cannot be
     linked to an account" is only true for NEW data. (Accounts have never shipped
     to testers, so in practice this should only affect your own test sign-ins —
     but run it rather than assume.)
   - ☐ Old app builds (build 2/3) will fail sign-in against the new Worker
     because they don't send a nonce. That's intended — build 2 has no accounts
     at all, so no shipped build is affected.
2. ☐ **Publish the updated legal pages** — privacy policy + terms were rewritten
   for accounts/sync (Last updated **August 7, 2026**). `docs/privacy.html` and
   `docs/terms.html` are regenerated and must go live BEFORE submission:
   `npx wrangler pages deploy docs --project-name cuevi-legal`
   Then confirm https://cuevi-legal.pages.dev/privacy shows the new date.
3. ☐ **Update the App Privacy label** (App Store Connect → App Privacy) using the
   revised `legal/app-store-privacy-label.md`. **This changed materially:** with
   accounts, data is now **Linked to You** (User ID, user content, Purchases).
   The old "nothing is linked to identity" answers are no longer accurate.
4. ☐ **Decide #1 and #2 above**, then archive and upload:
   Xcode → Product ▸ Archive → Organizer → Distribute App ▸ App Store Connect.
   Wait for processing, add build 4 to the tester group, paste the notes below.
5. ☐ **Confirm the OpenAI spending cap** is still set (platform.openai.com →
   Settings → Limits) — the model moved to `gpt-5-mini` and `MAX_TOKENS` is now
   4000, so cost per scan changed.
6. ☐ **Sanity-test sync on two real devices** before shipping: sign in on the
   phone, add a task, background the app; sign in on a second device / simulator
   and confirm it appears. Then sign in on a *third* to confirm the free
   one-device rule signs the first one out.

## Verified from the repo (2026-08-07)

- App builds clean; sync unit tests pass (LWW both directions, delete
  propagation, photo preserved, per-user cursors).
- Worker `/auth/apple` + `/sync` deployed and probed live: bad Apple token → 401,
  no session → 401, missing proxy token → 401, unknown route → 404.
- Sync protocol verified end-to-end against the live Worker with simulated
  clients: push→pull across devices, stale write rejected, newer write wins,
  delete propagates, revoked session → 401 while the other device stays 200.
  (Test rows were deleted; D1 left clean.)
- "Sign in with Apple" capability **is** present in `Tadah.entitlements`.
- No `sk-` key material in the app; secrets live in the Worker.

---

## What to Test (paste into TestFlight)

**English**

Big update — thank you for testing! Two brand-new things: **accounts** and
**backup/sync**.

- **Sign in (new).** Profile → Create a free account → Sign in with Apple. Your
  to-dos are now backed up to your account automatically, so they survive a
  reinstall or a new phone — there's nothing to press. Did signing in feel
  clear and quick?
- **Two devices (new).** If you have an iPad or a second iPhone, sign in there
  too. A **free account works on one device at a time** — signing in on the
  second should sign the first out with a message. Did that work clearly?
- **If you had to-dos before signing in** and they were made under a *different*
  account, we ask before touching them: **"Move them to this account"** or
  **"Not now — sign out"**. Was that question clear? (Nothing is ever deleted —
  "Not now" just signs you back out and leaves your to-dos exactly as they are.)
  If the to-dos already belong to the account you're signing into, there's no
  question at all — they just reconnect.
- **Please note the free limits:** 10 scans/guides a day, 20 per 30 days, and 20
  to-dos at a time. Tell us if you hit them while testing and they got in the way.
- Scan a real bill or letter (Add → Scan). Are the amount, date, and steps right?
  Tap Edit on the review screen — do your edits stick and sync?
- Life guides: Moving or Renting asks your ZIP and names local utility companies.
  Right companies for your area?
- Reminders: set **My Settings → Default reminder time** and check reminders
  arrive then (they used to always be 9am).
- 中文/Español: set your language in My Settings and scan — is the explanation
  clear? Please flag any English text that should have been translated.

**中文**

重大更新——感谢测试！两个全新功能：**账户** 和 **备份/同步**。

- **登录（新）**：我的 → 创建免费账户 → 通过 Apple 登录。你的待办事项会自动备份到账户，
  重装或换新手机都不会丢——无需任何手动操作。登录过程清楚、顺畅吗？
- **两台设备（新）**：如果你有 iPad 或第二台 iPhone，也在那里登录试试。
  **免费账户一次只能在一台设备上使用**——在第二台登录后，第一台应会退出登录并给出提示。
  这个提示清楚吗？
- **如果你在登录前已有待办事项**，而且它们属于*另一个*账户，我们会先询问：
  **"移到这个账户"** 还是 **"暂不——退出登录"**。这个问题清楚吗？
  （绝不会删除任何内容——选"暂不"只是退出登录，你的待办事项原样保留。）
  如果这些待办事项本来就属于你正在登录的账户，则不会有任何询问，会直接重新连接。
- **请注意免费额度**：每天 10 次扫描/指南，每 30 天 20 次，最多 20 条待办事项。
  如果测试时遇到额度不够、影响使用，请告诉我们。
- 扫描一张真实的账单或信件（添加 → 扫描）。金额、日期、步骤对吗？在确认页点"编辑"
  改一改——保存后有没有生效并同步？
- 生活指南："搬家"或"租房"会问邮编并列出你所在地区的水电网公司。公司对吗？
- 提醒：在 我的设置 → 默认提醒时间 设置一个时间，看提醒是否按时到达（以前固定早上 9 点）。
- 请把任何"本该翻译成中文却显示英文"的地方告诉我们。
