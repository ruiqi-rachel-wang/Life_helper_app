# Tadah — Later ideas (the "not now" pile)

> Created 2026-08-07. **`future_features.md` is the CURRENT plan** — what's being
> built now. This file is everything deliberately pushed past that: decided-but-
> deferred work, and ideas we like but aren't committing to.
>
> Rule for this file: nothing here is promised to a user. Anything advertised on the
> paywall, the App Store page, or in the app must live in the current plan and be
> BUILT before it ships (Apple review guideline 3.1.2 — an in-app purchase has to
> deliver what it describes).

---

## 1. Instant push notifications (APNs) — *deferred 2026-08-07*

"Your phone buzzes the moment Mom completes a task, even with Tadah closed."

**Why deferred:** the valuable half already works without it. Once family profiles
sync, the **existing reminder system** schedules "Electric bill due in 3 days" on
every device that has the item — so *nobody misses a deadline* with no new
infrastructure. What push adds is only the immediate social nudge ("Mom just added
something"), which is nice but isn't the promise of the product.

**What it would take** (~1–1.5 weeks):
- Push Notifications capability (`aps-environment` in `Tadah.entitlements`)
- An APNs Auth Key (.p8) → `wrangler secret put APNS_KEY` (+ key id, team id)
- A `UIApplicationDelegateAdaptor` (the app has none), `registerForRemoteNotifications`,
  and posting the device token to the Worker
- A `device_tokens` table + an APNs send path in `worker.js`, signing an ES256 JWT
  via WebCrypto (the same primitive `verifyAppleToken` already uses)
- **Two real devices to test** — simulators cannot receive APNs
- Must respect the existing **"Hide details in notifications"** toggle
  (`ReminderScheduler.discreetKey`), or a bill's title lands on a lock screen the
  user asked to keep quiet

**Interim behaviour instead:** a catch-up banner when the app opens and syncs
("2 updates from your family") plus a dot on the changed profile's avatar.

### Rejected: Background App Refresh
Tempting middle ground — iOS wakes the app periodically, it syncs, it raises a local
notification. **Don't build this.** iOS decides the timing from usage habits (minutes
to hours), it never runs after a force-quit, and it's off in Low Power Mode. It works
in testing and quietly fails for real users, which is worse than not having it.

---

## 2. Photo backup to the account — *optional, deferred*

Photos are the one thing not synced, so on a second device a task shows no document
image. Rachel wants this **available but never framed as a privacy guarantee either
way** (2026-08-06 decision: stop selling "on-device" as a feature).

- Cloudflare **R2** (same account, egress-free), keyed by item id, behind a Settings
  toggle that is **off by default**, reusing the existing session auth.
- Cost is negligible: task caps bound it (Free 20 items ≈ 40 MB, Plus 100 ≈ 200 MB
  per user). R2's 10 GB free tier covers ~250 free users; beyond that
  $0.015/GB-month — roughly **$0.45/month at 1,000 users**.
- Needs an R2 bucket + a `wrangler.toml` binding.
- ⚠️ The privacy policy already says photos are not uploaded. Turning this on means
  another policy pass **before** it ships.

---

## 3. Usage display on Profile

A small "X of N scans/guides used this month · Y of Z to-dos" readout, so people see
where they stand before they hit a wall — and it doubles as a soft Plus nudge for
free users. Reads `ScanQuota.usedLast30Days` / `usedToday` + `TaskLimit.count`
against the tier caps. Cheap; mostly a design question of where it sits.

---

## 4. Server-side scan quota

`ScanQuota` counts in per-device UserDefaults. Once one account is signed in on
several devices, a family gets **N× the scan allowance** — and the OpenAI bill is the
real cost centre. The Worker already tracks `ai_usage` keyed by install id; extend it
to the account and have the app trust the server's answer.

*Fold this into whichever build first ships multi-device to real users.*

---

## 5. Google + email sign-in

> **⚠️ SUPERSEDED 2026-08-15 — this is no longer a "later idea".** Rachel decided
> to **drop Sign in with Apple entirely and use email + password**, because Apple
> sign-in is bound to the *device's* Apple ID: a family member on their own iPhone
> can only ever create their own separate account, never reach the shared one. That
> made "one account, several people" unbuildable on Apple auth. Email delivery via
> **Resend**. The full plan is in `future_features.md` Part 3 — read that, not the
> scoping notes below, which are kept only as the original reasoning.


Apple-only today. Google needs the GoogleSignIn SPM package; email needs password
handling and a reset flow we'd have to run. Currently shown in-app as "coming soon"
text rather than dead buttons.

**PROMOTED 2026-08-13 — Rachel wants email sign-in, scheduled for after build 4
ships.** No longer "only if testers ask": it's wanted. Scope, so it doesn't get
started casually — every one of these is security-sensitive and lives in the
Worker, not the app:

- `POST /auth/email/register` + `/login` — Argon2id or scrypt password hashing
  (never SHA), per-account salt, and rate limiting on both routes.
- Email verification and password reset — needs an actual sending service
  (Resend / Postmark / SES). Single-use, expiring, constant-time-compared tokens.
- Account linking: the same person signing in with Apple *and* email must land on
  ONE account, or they get two accounts and their to-dos split in half. Apple's
  private-relay addresses make matching on email alone unreliable.
- The existing session/`ReconciliationGate` flow has to treat an email session
  exactly like an Apple one, including sign-out and `/account/delete`.

⚠️ Adding **Google** later would then oblige us to keep Sign in with Apple on the
same screen — App Store Review Guideline 4.8. Email/password alone does not
trigger that.

---

## 6. Separate logins per family member

The bigger version of family sharing: Mom signs in with **her own** Apple ID and is
invited into the family, rather than sharing the owner's account. Real privacy
between members, and Mom keeps her data if she leaves.

**Not chosen** (2026-08-07) — it needs an invite/accept flow, a permissions model,
and cross-account sharing rules, roughly doubling the backend. The shared-account
model was picked instead. Revisit only if sharing one login turns out to bother
people.

---

## 7. Small things

- **A deleted family profile's to-dos** — today's plan deletes them with the profile.
  Consider a 30-day recoverable window instead.
- **Apple Family Sharing for the subscription** — deliberately left **OFF**, and it
  can never be turned off once enabled. It's a different thing from Tadah's in-app
  family profiles: it would let one purchase cover 6 Apple IDs, undercutting
  per-account pricing. Revisit only as a deliberate pricing decision.
- **Domain name** for a landing page (~$12/year).
- **Launch language default** (EN / 中文 / ES) — a Settings picker already exists.

---

## 8. Engineering debt from the build-4 review passes — *added 2026-08-13*

Found across fifteen review passes of the accounts/sync/family work. **None of
these block build 4** — they are the deliberate "not now" residue, recorded here
so they aren't rediscovered from scratch. Roughly in the order they'd pay off.

### 8a. End-to-end tests for `SyncService.sync()` — *the biggest real gap*

Every sync guarantee is tested at the **helper** level (`apply`, watermarks,
cursors, the profile cascade), and the Worker has route tests against real
workerd + D1. What has **no automated coverage** is the full client round trip:
`sync()` itself — paging, the envelope-authority rule, the clamp, the ordered
apply stages, and the save-then-advance sequence. Two of the bugs the later
passes found lived exactly there and were caught by reading, not by a test.

Needs `URLProtocol` stubbing (register a fake protocol on a `URLSession`
configuration, hand `sync()` scripted responses). ~a day. Worth doing before the
next change to sync, not after.

### 8b. App Attest for the AI quota — *cost protection, deferred since 2026-08-10*

`/chat`'s rate-limit and quota keys come from caller-supplied headers
(`X-Cuevi-Install`), which an attacker can rotate to get a fresh allowance each
time. Inherent to an anonymous endpoint whose token ships inside the app. The
real fix is **App Attest** or a server-minted credential.

For a 10-person beta the **OpenAI spending cap is the actual backstop** — this is
tracked, not urgent, but it must be closed before any public launch where the AI
cost is unbounded by tester count.

### 8c. The storage-ceiling preflight race

`/sync` counts existing rows in a read *outside* the D1 batch, so two concurrent
syncs for one account can each see a free slot and both insert, overshooting the
200/2000 ceiling by roughly the number of concurrent requests. Folding the count
into the upsert was **tried and rejected** — SQLite won't take a subquery over the
target table in an upsert, and it broke every sync write. Fixing it properly needs
a real transaction around read-then-write, which D1 doesn't offer outside a batch.

Deliberately left: this is a **storage safety net, not a billing boundary** (the
commercial limits are enforced in the app), and overshooting by a row or two costs
nothing. Revisit only if D1 gains interactive transactions.

### 8d. Dead code — *DONE 2026-08-13, kept here as the record*

`TaskBackup.swift` and `SyncService.suppressPush`/`resetCursor` were deleted once
reconciliation became non-destructive: nothing in the app deletes a user's to-dos
on their behalf any more, so there was no destructive step left for a local backup
to guard, and no reason to keep helpers whose only job was discarding local state.

### 8g. Email-auth hardening — BEFORE PUBLIC LAUNCH *(2026-08-15)*

Raised by review, verified real, deliberately not done for a ~10-person beta.
**All three must close before the App Store**, not before TestFlight.

- **Email verification isn't implemented.** `verified_at` is written NULL and
  never read: registration issues a session immediately. So anyone can claim an
  address they don't own, and a typo becomes a live account nobody can reach.
  Deferring it was a deliberate call (agreed 2026-08-15 — reset matters more, and
  reset is built), but "deliberate" stops being a defence once strangers can sign
  up.
- **No PER-ACCOUNT throttle on register / login / reset.** The only limiter is
  the global one, keyed on session → install id → IP — all caller-controlled, so
  rotating `X-Cuevi-Install` walks straight past it, and it vanishes entirely if
  the binding is missing. Wants a D1-backed attempt counter per email, which is
  also what OWASP asks for on reset specifically.
- **Password minimum is 8 with no blocklist.** Current NIST guidance suggests 15
  for single-factor. Deliberately not raised: this app is for people managing a
  parent's paperwork, and 15 characters pushes them to write it down. A
  **common-password blocklist** buys far more than raw length here — do that
  instead, and only revisit the length if it proves insufficient.

Also noted, lower severity: `pw_iterations` is stored per account but never read
at login, so RAISING the client iteration count later would silently change every
derived credential and lock everyone out. Either read it and derive per-account,
or treat the constant as frozen forever — decide before it's ever changed.

### 8f. From the external review — confirmed real, deferred *(2026-08-13)*

Verified in code, not fixed before build 4 because each is a design change rather
than a patch. Ordered by how likely a tester is to hit it.

- ~~**A failed sign-in can leave a dead-end local account.**~~ **CLOSED
  2026-08-15** by the move to email auth: there is no local half any more —
  either the Worker returned an account or nothing happened — so the state that
  produced the dead end can't exist. Regression tests cover it.
- ~~**The owner profile can read "Unnamed" for one launch.**~~ **CLOSED** — an
  owner with no name now displays "You", which is true by definition.
- **Removing a person deletes their to-dos with no undo.** Matches the written
  plan, but it's the most destructive action in the app and it's two taps from a
  long-press. Consider a 30-day recoverable window (see §7) before this reaches
  people managing a parent's paperwork.
- **Worker has no structured operational logging** despite observability being
  enabled, so auth/sync/RevenueCat failures are hard to diagnose in production.
  Add leveled, non-PII logging (never payloads) before real user volume.
- **Logout revocation is best-effort.** `signOutEverywhere` calls the server, but
  ignores failure and clears the local session regardless — right for the user
  (tapping log out must log you out) but it means an offline logout can leave the
  backend token valid until its 90-day inactivity expiry, while the policy says
  the session ends "straight away". Either soften the policy wording or add a
  retry queue that revokes on next connectivity. **Pick one before launch** — the
  current pairing is a promise the code doesn't keep.
- **The owner profile can read "Unnamed" for one launch.** `ensureOwnerProfile`
  runs at startup with whatever name the account has *then*, which on a first
  sign-in is nothing; the repair lands next launch (and now propagates, since it
  stamps `touch()`). Fixing the timing means running identity work right after
  reconciliation clears instead of at startup — safe, but it moves a mutation that
  the reconciliation gate deliberately fences, so it wants its own careful pass.
**Already DONE, listed here only so the record doesn't read as still-open:**
stale profile caching (now reloads after every successful sync pass), the
editable local-only email (now read-only and conditional), JWKS
refresh-on-unknown-kid (now refetches once, throttled to one forced refresh a
minute — `kid` is attacker-controlled, so an unthrottled version would have been
a JWKS amplifier), and **reassigning a to-do to another person** (2026-08-14 —
`AssigneeRow` now sits in `DetailView`'s head card, in read mode as well as edit,
because moving a letter to Mum is a correction rather than an editing session).

### 8e. Smaller follow-ups

- **A "last backed up" indicator, if testers ask for one.** The Profile Backup row
  was removed 2026-08-13 (backup should be invisible), but `SyncCoordinator` still
  publishes `isSyncing` / `lastSyncedAt` / `lastError` — only the view went. If
  someone asks "is it actually saving?", the answer is a *reassurance*, not a
  status light with a manual sync button.
- **Sync failures are silent to the user by design.** A failed pass retries on the
  next foreground and nothing is lost, but there is no path that ever says "your
  last week of to-dos never reached the account". Worth a quiet banner **only** if
  `lastError` persists across several passes — not per failure.
- **Reminder rescheduling after a pulled change is unbatched** — one
  `UNUserNotificationCenter` call per changed item. Fine at 25 records a page;
  revisit if the page size ever grows.
- **`ProfileStore.reload` keeps its last-good list on a read failure** (right for
  UI), which means a persistent storage fault shows a stale family silently.
  Acceptable; noted so it isn't mistaken for a sync bug.
