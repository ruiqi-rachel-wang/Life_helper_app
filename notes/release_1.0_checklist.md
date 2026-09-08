# Release 1.0 — your checklist

> Updated 2026-09-01. Only things **you** do: App Store Connect, RevenueCat,
> production D1, your phone. Code and tests are handled separately.
> Shipping **build 6** — build 5 was rejected twice (Terms of Use link, then 5.1.1; see the bottom of this file).

## Done — don't redo

☑ Paid Apps Agreement, banking, W-9 — Active 2026-08-23
☑ Paywall legal links → `tadah-legal.pages.dev` (all 3 locales, verified)
☑ D1 privacy purges — 39 → 0 raw task ids, 11 → 0 device ids
☑ OpenAI spending cap
☑ Legal pages live and Tadah-branded
☑ Subscriptions created, $6.99 / $59.99, Ready for Review
☑ `main` + `build-4` tag pushed to GitHub
☑ Scan speed: `reasoning_effort` reaches OpenAI again (was dropped by the proxy
   allow-list since 2026-08-09). 38.0s → 18.5s median. Worker live + verified.
☑ Scan prompt rewritten and cut to 2,978 tokens (10ba282). Ships with build 5.
☑ Legal URLs re-checked 2026-09-02: `/privacy` and `/terms` return 200. Use those,
   NOT the `.html` variants, which 308-redirect.
☑ Version numbers correct for build 6: MARKETING_VERSION 1.0, CURRENT_PROJECT_VERSION 6 (bumped 2026-09-07 for the 5.1.1 fix).

---

## 1 · Archive

- ☐ **Tag first:** `git tag -a build-6 -m "Build 6 as submitted" && git push origin build-6`
      *(Build 4's archive commit is unrecoverable because nobody tagged it.)*
- ☐ Xcode → scheme **Tadah** → Any iOS Device → Archive → Distribute → App Store Connect
- ☐ Add to TestFlight, install on your phone

## 2 · Account lifecycle — test this FIRST

All new in build 5, none of it has run on a device, and it deletes user data.
**If anything here misbehaves, stop.**

- ☐ Sign in → add a to-do **with a photo** → sign out
- ☐ Phone is now empty, and Profile shows the guest MEMBERSHIP card — plan,
      Restore, and an UPGRADE row. ⚠️ Changed in build 6: it used to say "Sign in
      to see your membership", and that string is gone. Seeing the card is CORRECT
      now, not a bug — hiding it is what Apple rejected under 5.1.1.
- ☐ Sign back in → the to-do **and its photo** return
- ☐ Sign out with **airplane mode on** → must REFUSE, say why, stay signed in
- ☐ Register a 2nd account on the same phone → must not inherit the 1st's to-dos

## 3 · Scans — the only check on the rewritten prompt

Prompt is 44% smaller; no test covers its output. Changed again on 2026-09-01
(padding rules, no per-step explanation, no `fields`) and the model now runs at
`reasoning_effort: low` — a scan went 38s → ~16-19s.

Checked on 2026-09-01 against three SYNTHETIC documents sent straight to the
Worker (parking ticket, USCIS "within 90 days", flight itinerary): amount, due
date, summons/receipt number and category all correct, and the flight kept its
`-04:00` offset and clock time. That is NOT the same as a real photo through
OCR, and the rows below still stand.

☑ Rachel scanned real documents on device 2026-09-02. Prompt then changed again
      that night: `miniChecklist` and `needed` were redefined (a checklist must
      transcribe a sequence the DOCUMENT gives; `needed` is noun phrases, max 4),
      `otherIDs` no longer duplicates `accountNumber`, and the whole prompt was cut
      3,847 → 2,978 tokens. Verified against a real NYS DTF-948 letter, but by
      posting OCR TEXT to the Worker — never through Vision OCR on a photo.

- ☐ Re-scan 2–3 real documents on the FINAL build, incl. the **home-warranty letter**
- ☐ Notes ≤ 3 short lines · no fee/waiver advice on an offer · steps under ~12
      words · due-date **year and timezone** correct (tester bug #10)

## 4 · Paywall

☑ Real Store scheme on iPhone: paywall shows real prices ($6.99 / $59.99) — 2026-09-02.
      (The plain **Tadah** scheme has a `.storekit` test file in its Run action and
      shows "test mode"; Archive ignores it and nothing ships. Use Real Store to test.)
☑ Sandbox purchase went through — Apple's own Edit Subscription sheet showed it.
☑ Cancel in App Store Settings → Profile says "Cancelled" without relaunch.
☑ Real paywall screenshot taken (Chinese locale, real prices) — for subscription review.
- ☐ Restore after delete-and-reinstall — not exercised; purchase + cancel were the
      risky paths and both work. Non-blocking.
- ☑ RevenueCat → restore behaviour stays at the DEFAULT, **Transfer to new App User ID**.
      The earlier plan to set "stay with original account" is WITHDRAWN: a guest
      who buys Plus and then signs in to an existing account is carried across by
      a restore under the account id, and "keep with original" makes that restore
      fail (see Rejection 2 below). Don't touch the setting.

☑ **Auto-renewal sentence — FIXED IN CODE 2026-09-07, ships in build 6.** It was
a known accepted gap (decided 2026-09-02) until the audit below confirmed against
the live dashboard paywall that nothing rendered it. `PaywallView` now pins the
disclosure under RevenueCat's paywall with `safeAreaInset`, in en/es/zh. Doing it
in the app rather than the RevenueCat editor means a dashboard redesign cannot
silently drop it again.

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
- ☐ **Subscription review info** — paywall screenshot + these notes on **both** products:
      > Tadah Plus is an optional subscription. Free accounts can save up to 20
      > to-dos and run 20 AI scans/guides a day, up to 50 per rolling 30 days, on one
      > device at a time. Tadah Plus raises these to 100 to-dos per profile and 60 a
      > day / 300 per 30 days, and allows multiple devices. No account or purchase is
      > required to use the app's core features. To test: open the Profile tab and
      > tap UPGRADE — no account or sign-in is needed to purchase.
- ☐ Description, keywords, subtitle, promo, support URL — all in `app_store_listing.md`, paste as-is
- ☐ Privacy Policy URL → `https://tadah-legal.pages.dev/privacy`
- ☐ Age rating (all None → 4+; **web access = No**) · Export compliance (encryption Yes, exempt Yes) · Content rights No · Productivity / Utilities

## 9 · Submit

- ☐ Attach build 6
- ☐ Draft Submission holds the app **and both subscriptions** — separately = two review rounds
- ☐ **Manual release**
- ☐ Add for Review → Submit. 24–48h. Watch for "Developer Action Needed".

## After approval

- ☐ Release · buy Plus once with a **real** Apple ID · move `main` to build 6 and tag `v1.0`

---

## ⚠️ Login throttle — DEPLOYED 2026-09-01, not yet verified

☑ Deployed. **It rode along with the scan-performance fix**, not as a separate
decision: a Worker deploy ships the whole of `worker.js`, and the throttle
(ae764ed, 2026-08-28) was already committed there. Version `4e544827` is live.

- ☐ Still confirm on production: 10 wrong passwords for one email → the 11th
      returns 429. This is now testing LIVE auth behaviour, not a staging build.

Ten wrong guesses in 15 minutes puts that **email** in a 15-minute cooldown. A
cooldown, not a lockout — a permanent lock would let anyone freeze a real user
out of their own account by guessing wrong on purpose. The table is created
lazily, so no migration step.

## Likely rejections, ranked

1. Privacy label ≠ shipped manifest (§8)
2. No demo account (§8)
3. Subscription review screenshot missing or a placeholder (§8)
4. 3.1.1 — paywall must state price, period, what Plus adds; Restore reachable

Already hit, already fixed: Terms of Use link missing from the listing (build 5,
2026-09-03) · 5.1.1 sign-in required to buy Plus (build 5, 2026-09-07 — below).

## Not gates

- ☐ Delete unused Apple secrets (`APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`) — read the `.p8`-downloads-once warning first
- ☐ Lower Worker `GLOBAL_DAY_LIMIT` 3000 → ~500 so the graceful error fires before the OpenAI cap
- ☐ Photo sync → `roadmap.md` (1.3; needs the policy rewrite first)

---

## ⚠️ Rejection 2 — 2026-09-07, guideline 5.1.1(v): sign-in required to buy Plus

Build 5, reviewed on an iPad Air 11-inch (M3). Apple's finding, with two
screenshots: tapping UPGRADE opened the sign-in sheet first, and the guest
Profile said "Sign in to see your membership" with no way to buy at all. Their
rule: a subscription that isn't tied to an account may not require
registration. An account may only be OFFERED — as the way to use the purchase
on other devices — and must be available to create at any time.

**Fixed in code the same day. Ships as build 6.** What changed:

- `CreateView` — the "See Tadah Plus" buttons on the scan-limit and list-full
  alerts open the paywall directly; the sign-in-first sheet is gone.
- `ProfileView` (guest) — the "Sign in to see your membership" card is replaced
  by the full `MembershipCard` (plan, renewal date, Manage, Restore) with an
  UPGRADE row that says no account is needed and what an account adds. A guest
  who is already Plus sees "Create a free account to use Tadah Plus on your
  other devices and add family members" on the No-account card.
- `Components/PlusUpgradeRow.swift` — the UPGRADE row, shared by the signed-in
  account card and the guest membership card, so the review-notes instruction
  "open the Profile tab and tap UPGRADE" holds either way.
- `PaywallView` — after a guest purchase, one screen: "You're on Tadah Plus …
  Create a free account whenever you like …" with **Create a free account** /
  **Not now**. Signed-in purchases still just close the sheet.
- `PlusStore.identify(as:)` — sign-in now goes through this. It logs the account
  id in to RevenueCat and, if the phone was Plus as a guest but the account
  isn't, restores the receipt under the account id. Needed because RevenueCat
  only auto-merges an anonymous purchase into a BRAND-NEW account; an existing
  account (which always already has an anonymous alias) gets no merge.
- `CURRENT_PROJECT_VERSION` 5 → 6. Four new strings in the catalog (en/es/zh).

**Verified in the Simulator 2026-09-08** (iPhone 17 Pro, fresh install, signed out,
via temporary `-shotProfile` / `-shotPaywall` launch hooks that were removed again):

- ☑ Guest Profile shows the MEMBERSHIP card: "Free plan", a **UPGRADE** row, and
      Restore purchases. This is the exact screen App Review could not find.
- ☑ The paywall now carries everything 3.1.2 asks for, in one view: title, four
      benefit bullets, $59.99/yr and $6.99/mo with per-month equivalents, Restore,
      Terms, Privacy, AND the new auto-renewal sentence, unclipped and below the
      buy button rather than covering it.

Still UNVERIFIED, and only a device can do it: the purchase transaction itself and
the guest-buys-then-signs-in handover.

**Before resubmitting:**

- ☐ Archive + upload build 6 (Xcode → Product → Archive; the `.storekit` file is ignored by Archive)
- ☐ On a device, signed OUT of Tadah, sandbox Apple ID: Profile → UPGRADE →
      buy → "You're on Tadah Plus" → **Not now** → Profile shows "Tadah Plus ·
      Monthly", Manage, Restore. Scan-limit alert no longer offers sign-in.
- ☐ **In that same signed-out-but-paid state, check the top card's headline.**
      It must read "Use Plus on your other devices", NOT "No account" (changed
      2026-09-08 so a paying guest isn't told they have nothing). This is the one
      screen state the Simulator cannot reach without a real purchase, so it has
      never been seen rendered — check the wrapping in 中文 too, it is the longest.
- ☐ Then Profile → Create a free account → still Plus after sign-in, Family row appears
- ☐ Log out → guest card → Restore purchases → Plus is back on the phone
- ☐ Sign in to an account made EARLIER on another device, after buying as a
      guest → Plus follows (this is the restore path in `identify`)
- ☐ **Know this before you test with two accounts.** One Apple purchase = ONE
      account holding it at a time (RevenueCat "Transfer to new App User ID").
      Sign out of account 1, sign into account 2, tap Restore → account 2 GAINS
      Plus and account 1 LOSES it, on every device account 1 is signed in to,
      within a refresh. That is correct, not a bug. Signing in alone never does
      this — `forgetSignedOutUser` clears `isPlus` at sign-out, so the auto-restore
      inside `identify` cannot fire for the next account. Only a deliberate
      Restore tap moves it.
- ☐ **Open question, answer it while you're there:** right after you log out of
      an account that holds Plus, does the guest Profile say "Tadah Plus" or
      "Free plan"? If it says Tadah Plus, RevenueCat re-posted the receipt to the
      signed-out anonymous user, which means logging out on THIS phone quietly
      takes Plus away from that account on OTHER devices. Worth knowing either
      way; not established as of 2026-09-08.
- ☐ RevenueCat → Project settings → Restore behavior = **Transfer to new App
      User ID** (default). Confirm, don't change.
- ☐ App Store Connect → the submission → iOS App 1.0 → Edit → attach build 6 →
      reply in the thread (below) → Resubmit. Keep both subscriptions in the same
      submission.

**Reply to Apple** (paste into the review thread):

> Thank you for the review. We have removed the registration requirement.
> In build 6, Tadah Plus can be purchased without an account: the UPGRADE row
> on the Profile tab, and the upgrade prompts on the Add tab, open the App Store
> purchase directly, and the Profile tab shows the membership, Manage
> Subscription and Restore Purchases options while signed out. After a purchase
> the app explains that creating a free account is optional and is only needed
> to use Tadah Plus on additional devices and to add family profiles; the
> option to create one stays available at any time on the Profile tab.

---

## Guideline audit — 2026-09-07, everything except 5.1.1

Checked against the live guidelines and the actual code/dashboard, not from
memory. Only the items where something was verified are listed.

**Verified compliant.** Don't re-litigate these without new evidence:

| Guideline | Why it passes | Evidence |
|---|---|---|
| 5.1.1(v) account deletion | In-app, password-confirmed, deletes D1 rows + the RevenueCat subscriber, retries safely, honest that the phone's own copy stays | `AccountDetailsView.deleteCard` |
| 5.1.1(v) forced registration | Fixed today — guests buy, see and restore Plus | build 6 |
| 5.1.1(ii) purpose strings | Camera string is specific. Photos needs none: `PhotosPicker` runs out of process | pbxproj `INFOPLIST_KEY_NSCameraUsageDescription` |
| Privacy manifest | Present and unusually thorough. Declares UserDefaults reason `CA92.1`, 10 data types, tracking false | `Tadah/PrivacyInfo.xcprivacy` |
| 4.8 Sign in with Apple | NOT triggered. It applies only to apps using a *third-party* login. Tadah uses its own email/password, which is the guideline's stated exception | `SignInView` |
| 3.1.1 Restore | Reachable on the paywall and on Profile, signed in or out | today's change |
| 3.1.2 what you get | Paywall states price, per-month equivalent, billing period, and the feature list, in en/es/zh | live RevenueCat offering |
| 3.1.2 no false trial | Two "after free trial" strings exist but sit behind an `intro_offer` condition, and BOTH products have `introductoryOffer: null`, so they never render. Not a misleading-terms problem | `Tadah.storekit` + paywall components |
| 1.4.1 / 2.3.1 disclaimers | "Informational only, not legal/tax/immigration/financial/medical advice" on Profile, plus Terms §2 and §3 on AI mistakes | `LegalContent.swift` |
| EULA | Terms §10 references Apple's standard EULA — the build-5 rejection #1 fix | `LegalContent.swift` |

**Open, ranked by how likely they are to be cited next:**

1. ☑ **3.1.2 auto-renewal sentence — FIXED IN CODE.** Confirmed missing on the
   live paywall, then added to `PaywallView` as a bottom inset so it renders
   under RevenueCat's own layout in all three languages. Verify it looks right
   on device when you test the purchase; it is the one change that alters a
   screen designed in the dashboard.
2. ☐ **Privacy label must match the manifest.** Apple cross-checks, and this is
   still a form to fill in by hand. ⚠️ `legal/app-store-privacy-label.md` was
   CORRECTED on 2026-09-07: its §2 told you to answer "not linked" for User
   Content, Contact Info, Health, Financial and Sensitive Info, while the
   shipped `PrivacyInfo.xcprivacy` declares all five **Linked**. Entering the
   old answers would have produced exactly the mismatch ranked #1 here. Use the
   corrected doc, and answer **Linked** for those five.
3. ☐ **Demo account.** 2.1 requires it whenever the app has a login, even now
   that the purchase needs none. Real, working credentials in Sign-In Information.
4. **iPad.** `TARGETED_DEVICE_FAMILY = "1,2"`, which is why review tested on an
   iPad Air. You already supplied iPad screenshots or you could not have
   submitted; just confirm they are genuine iPad captures, not stretched iPhone
   ones (2.3.3).
5. **5.1.1(ix), low risk, no action.** Apps providing services in highly
   regulated fields should come from a legal entity, not an individual
   developer. Tadah gives information about paperwork, it does not provide
   banking, healthcare or legal services, and the disclaimer says so. Noted so
   nobody is surprised if it ever comes up.
