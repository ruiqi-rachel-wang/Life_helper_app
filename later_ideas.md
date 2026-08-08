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

Apple-only today. Google needs the GoogleSignIn SPM package; email needs password
handling and a reset flow we'd have to run. Currently shown in-app as "coming soon"
text rather than dead buttons. Only worth it if testers actually ask.

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
