# Release 1.0 — your checklist

> Updated 2026-08-28. Only things **you** do: App Store Connect, RevenueCat,
> production D1, your phone. Code and tests are handled separately.
> Shipping **build 5**.

## Done — don't redo

☑ Paid Apps Agreement, banking, W-9 — Active 2026-08-23
☑ Paywall legal links → `tadah-legal.pages.dev` (all 3 locales, verified)
☑ D1 privacy purges — 39 → 0 raw task ids, 11 → 0 device ids
☑ OpenAI spending cap
☑ Legal pages live and Tadah-branded
☑ Subscriptions created, $6.99 / $59.99, Ready for Review
☑ `main` + `build-4` tag pushed to GitHub

---

## 1 · Archive

- ☐ **Tag first:** `git tag -a build-5 -m "Build 5 as submitted" && git push origin build-5`
      *(Build 4's archive commit is unrecoverable because nobody tagged it.)*
- ☐ Xcode → scheme **Tadah** → Any iOS Device → Archive → Distribute → App Store Connect
- ☐ Add to TestFlight, install on your phone

## 2 · Account lifecycle — test this FIRST

All new in build 5, none of it has run on a device, and it deletes user data.
**If anything here misbehaves, stop.**

- ☐ Sign in → add a to-do **with a photo** → sign out
- ☐ Phone is now empty, and Profile shows only "Sign in to see your membership"
- ☐ Sign back in → the to-do **and its photo** return
- ☐ Sign out with **airplane mode on** → must REFUSE, say why, stay signed in
- ☐ Register a 2nd account on the same phone → must not inherit the 1st's to-dos

## 3 · Scans — the only check on the rewritten prompt

Prompt is 44% smaller; no test covers its output.

- ☐ Scan 2–3 real documents, incl. the **home-warranty letter**
- ☐ Notes ≤ 3 short lines · no fee/waiver advice on an offer · steps under ~12
      words · due-date **year and timezone** correct (tester bug #10)

## 4 · Paywall

- ☐ Scheme **Tadah (Real Store)** → your iPhone → console says `StoreKit returned 2/2`
- ☐ Sandbox purchase → limits actually rise (60/day, 100 tasks)
- ☐ Restore after delete-and-reinstall
- ☐ Cancel in App Store Settings → Profile says "Cancelled" **without relaunch**
- ☐ **Screenshot the real paywall** — required by ASC, rejects placeholders
- ☐ RevenueCat → transfer behaviour = **stay with original account**

## 5 · Auth lifecycle — the sequence that proves the schema

§2 covers the data side. This is the credential side, once, in order:

- ☐ Log in → sync → **log out** → old token stops working
- ☐ Log back in → data is there
- ☐ **Delete the account** → old token AND the synced rows are gone

## 6 · Clean the database before public launch

Not before TestFlight — 19 sessions against 2 accounts is just what repeated
install/login testing looks like. But production should start clean.

- ☐ Delete the test accounts (use the in-app Delete account — it exercises the
      real path and cascades to tasks, profiles and sessions)
- ☐ Confirm afterwards: `accounts`, `tasks`, `profiles`, `sessions` all 0
- ☐ Drop the dead Sign-in-with-Apple leftovers: `used_nonces`, `account_deletions`

Retention runs itself — cron `12 4 * * *` sweeps tombstones at 180 days, revoked
sessions at 30, usage rows at 60. Nothing has aged out yet, so it is unproven in
production; first real sweep is late September. Worth one look then.

**`cuevi-metrics` keeps its name.** Renaming a production database to match the
app's is not worth the risk, and the same reasoning already froze the bundle id.

## 7 · Remaining smoke tests

- ☐ Password reset end to end (live Resend + real DNS); old password fails
- ☐ Two-device sync — and the **notification** moves, not just the shown time
- ☐ Family profiles: add, rename, reassign, remove (removal takes their to-dos)
- ☐ Free one-device rule: 3rd device signs the 1st out

## 8 · App Store Connect

- ☐ **Screenshots** — 3 min, 10 max, 1284×2778. Simulator ready:
      `xcrun simctl create "iPhone 14 Plus" com.apple.CoreSimulator.SimDeviceType.iPhone-14-Plus`
      Not the paywall — Apple dislikes store pages leading with a price.
- ☐ **Privacy label** ⚠️ currently wrong — from `legal/app-store-privacy-label.md`.
      Now **Linked to You** (User ID, user content, Purchases) + email collected.
      Apple cross-checks against the shipped manifest.
- ☐ **Demo account** ⚠️ — real credentials in Sign-In Information, or rejection
- ☐ **Subscription review info** — paywall screenshot + notes (`tadah_plus_setup.md` §A6) on **both** products
- ☐ Description, keywords, subtitle, promo, support URL — all in `app_store_listing.md`, paste as-is
- ☐ Privacy Policy URL → `https://tadah-legal.pages.dev/privacy`
- ☐ Age rating (all None → 4+; **web access = No**) · Export compliance (encryption Yes, exempt Yes) · Content rights No · Productivity / Utilities

## 9 · Submit

- ☐ Attach build 5
- ☐ Draft Submission holds the app **and both subscriptions** — separately = two review rounds
- ☐ **Manual release**
- ☐ Add for Review → Submit. 24–48h. Watch for "Developer Action Needed".

## After approval

- ☐ Release · buy Plus once with a **real** Apple ID · move `main` to build 5 and tag `v1.0`

---

## ⚠️ Deploy the login throttle

Built and tested 2026-08-28 — **not deployed.** Worker-only, so it needs no app
release and can ship before or after 1.0.

- ☐ ```
      cd Tadah/cloudflare-worker
      export PATH="/usr/local/opt/node@22/bin:$PATH"
      npx wrangler deploy
      ```
- ☐ Then confirm: 10 wrong passwords for one email → the 11th returns 429

Ten wrong guesses in 15 minutes puts that **email** in a 15-minute cooldown. A
cooldown, not a lockout — a permanent lock would let anyone freeze a real user
out of their own account by guessing wrong on purpose. The table is created
lazily, so no migration step.

## Likely rejections, ranked

1. Privacy label ≠ shipped manifest (§8)
2. No demo account (§8)
3. Subscription review screenshot missing or a placeholder (§8)
4. 3.1.1 — paywall must state price, period, what Plus adds; Restore reachable

## Not gates

- ☐ Delete unused Apple secrets (`APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`) — read the `.p8`-downloads-once warning first
- ☐ Lower Worker `GLOBAL_DAY_LIMIT` 3000 → ~500 so the graceful error fires before the OpenAI cap
- ☐ Photo sync → `photo_sync_plan.md` (1.1; needs the policy rewrite first)
