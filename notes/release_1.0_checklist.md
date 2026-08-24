# Release 1.0 to the App Store — step by step

> Written 2026-08-24. Supersedes the upload checklist in `testflight_build4_notes.md`,
> which was written for a TestFlight beta, not a public release.
> Work top to bottom. Each phase depends on the one before it.

---

## Decision made first: ship **build 5**, not build 4

Build 4 is stale in a way that matters. The production Worker was already
redeployed on 2026-08-20 with two changes made *for app code that is still
uncommitted*:

- `MAX_TOKENS` 4000 → **6000**, for the per-step scan detail (`stepDetails`)
- `VALID_KINDS` gained **`opened`**, the retention event

Build 4 contains neither app-side half. Submitting it would ship the old scan
prompt against a backend built for the new one, and D1/D7/D30 retention would
stay empty forever. There are 579 uncommitted insertions across 18 files.

**So: commit, test, bump to build 5, re-verify, submit that.**

---

## Phase 1 — get the tree clean and committed

- ☐ **1.1 Review the diff.** 18 files, ~579 insertions. Confirm it is all
      intended and nothing half-finished is in there:
      `git diff --stat && git diff`
- ☐ **1.2 Commit in coherent batches** (not one giant commit — see the
      commit-cadence convention). Suggested grouping:
      1. Scan depth: `ScanPrompt.swift`, `OpenAIClient.swift`,
         `ExtractionResult.swift`, `ReviewView.swift` + their tests
      2. Retention metrics: `Metrics.swift`, `worker.js`, `schema.sql`,
         `routes.test.js`
      3. Privacy/legal: `LegalContent.swift`, `legal/privacy-policy.md`,
         `docs/privacy.html`
      4. Paywall diagnostics: `TadahApp.swift`, `PaywallView.swift`,
         `Tadah (Real Store).xcscheme` (new file — `git add` it)
      5. Notes: `testflight_build4_notes.md`, `how_to_view_tester_data.md`,
         this file
- ☐ **1.3 Full test suite must be green before archiving.**
      ```
      cd Tadah
      DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
        -project Tadah.xcodeproj -scheme Tadah \
        -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
        -derivedDataPath DerivedData -only-testing:TadahTests
      ```
      Expect ~281+ passing. A run often exceeds 10 minutes — that is normal.
      ⚠️ Before believing a failure, look for a `✘` line naming a real test; the
      "test runner hung" and `mkstemp` errors are environmental.
- ☐ **1.4 Worker tests** (the Worker is already deployed, this confirms the
      committed source matches production):
      ```
      export PATH="/usr/local/opt/node@22/bin:$PATH"
      cd Tadah/cloudflare-worker && npm test
      ```
      Expect 31/31 helper + 59/59 route.
- ☐ **1.5 Bump the build number to 5.** `CURRENT_PROJECT_VERSION` in
      `project.pbxproj`, both Debug and Release. Leave `MARKETING_VERSION` at
      `1.0`.

---

## Phase 2 — things that must be true before you archive

### 2.1 Fix the paywall's legal links ⚠️ REJECTION RISK

The RevenueCat paywall currently links to **RevenueCat's own** legal pages —
verified in the live offering JSON on 2026-08-23:

```
https://revenuecat.com/terms      ← wrong
https://revenuecat.com/privacy    ← wrong
```

Apple requires a subscription paywall to link to **your** Terms of Use (EULA)
and **your** Privacy Policy. This is one of the most common subscription
rejections under Guideline 3.1.2.

- ☐ RevenueCat → Paywalls → the `default` offering's paywall → find the Terms
      and Privacy components → repoint them at:
      - `https://cuevi-legal.pages.dev/terms`
      - `https://cuevi-legal.pages.dev/privacy`
- ☐ Do it for **all three locales** (en, es, zh-Hans) — they are separate strings.
- ☐ Verify with no dashboard clicking:
      ```
      curl -s -H 'Authorization: Bearer appl_NkpoJAXKXycQKzzekTUOmXaxedM' \
        -H 'X-Platform: iOS' \
        https://api.revenuecat.com/v1/subscribers/check/offerings \
        | grep -o 'https://[^"]*' | sort -u
      ```
      Expect `cuevi-legal.pages.dev` links and **no** `revenuecat.com` ones.

This is dashboard-side. No app release needed, and it takes effect immediately
on build 4 and build 5 alike.

### 2.2 The two D1 privacy purges — do these BEFORE the privacy label

Both are still pending and both must run by hand (the assistant's permission
layer blocks remote D1 writes).

- ☐ **39 `events` rows carry raw task UUIDs**, joinable to `tasks.user_id`:
      ```
      cd Tadah/cloudflare-worker
      npx wrangler d1 execute cuevi-metrics --remote \
        --command "UPDATE events SET item_id = NULL;"
      ```
- ☐ **11 `sessions` rows carry a joinable `device_id`**:
      ```
      npx wrangler d1 execute cuevi-metrics --remote \
        --command "UPDATE sessions SET device_id = '';"
      ```
      Harmless — worst case is one extra sign-in.

Reason for the ordering: the App Privacy label is a statement about what you
hold. Make it true before you sign it.

### 2.3 Legal pages live and current

- ☐ Regenerate if `LegalContent.swift` changed (never edit the HTML by hand):
      `python3 legal/make_legal_pages.py`
- ☐ Deploy **from the repo root, with the branch flag** — without `--branch main`
      it silently lands on a preview alias, which has bitten this project three
      times:
      ```
      cd "/Users/rachelwang/Project!/notie_life_helper_app"
      npx wrangler pages deploy docs --project-name cuevi-legal \
        --branch main --commit-dirty=true
      ```
- ☐ Confirm it actually replaced the live copy:
      ```
      curl -s https://cuevi-legal.pages.dev/privacy | grep -o 'Last updated:</strong> [A-Za-z0-9, ]*'
      curl -s https://cuevi-legal.pages.dev/privacy | grep -ci 'sign in with apple'
      ```
      Expect a current date and **0**.

### 2.4 Cost guard

- ☐ **OpenAI spending cap** (platform.openai.com → Settings → Limits). The model
      is `gpt-5-mini` and `MAX_TOKENS` is now **6000**, so cost per scan is higher
      than when you last set this. A public launch means strangers scanning, not
      ten testers.

---

## Phase 3 — archive build 5 and verify it on a real device

- ☐ **3.1 Archive.** Xcode → scheme **Tadah** → destination **Any iOS Device** →
      Product ▸ Archive. (The `Tadah.storekit` reference only affects Run, never
      Archive.)
- ☐ **3.2 Distribute** → App Store Connect → Upload. Wait for processing.
- ☐ **3.3 Put it on TestFlight first** and install it on your phone. Do not
      submit a build you have not run.

### The six smoke tests — none of these are covered by the unit suite

Every one crosses a boundary the tests stub out (Keychain, live Resend, two
devices, StoreKit). 281/281 green says nothing about them.

- ☐ **Register → log out → log back in.** To-dos still there.
- ☐ **Password reset end to end** through live Resend and real DNS: request a
      code, receive the email, set a new password, sign in with it. Confirm the
      old password fails and other devices were signed out.
- ☐ **Sync between two devices**: add an item on one, confirm it appears on the
      other; change a reminder time and confirm the *notification* moves, not
      just the displayed time.
- ☐ **Family profiles**: add, rename, reassign a to-do, remove a profile.
      Removing takes that person's to-dos with them.
- ☐ **Free one-device rule**: sign in on a third device, confirm the first is
      signed out with a clear message.
- ☐ **Scan a real document** and check the timezone on the due date — the one
      round-1 tester bug (#10) never verified on a live scan.

### The paywall, now that the Paid Apps Agreement is Active (2026-08-23)

- ☐ **Confirm Apple is serving the products.** Scheme **Tadah (Real Store)** →
      your iPhone → ⌘R → Profile ▸ UPGRADE → console shows
      `[Paywall] StoreKit returned 2/2`. `0/2` means still propagating.
- ☐ **Sandbox purchase**: Settings ▸ App Store ▸ Sandbox Account, sign in as a
      sandbox tester, buy Monthly through the paywall. Confirm the `Tadah Pro`
      entitlement flips and limits actually rise (60 scans/day, 100 tasks) — not
      just that the sheet dismissed.
- ☐ **Restore purchases** on a second device / after a delete-reinstall.
- ☐ **Screenshot the real paywall** while it is on screen. App Store Connect
      requires this for each subscription's Review Information and rejects
      placeholders. You cannot get it any other way.

---

## Phase 4 — App Store Connect metadata

Nothing here can be automated; it is all portal work.

### 4.1 Screenshots — currently 0 of 10, and required

Your slot is **iPhone 6.5" (1284×2778)**. You have no simulator that size —
create one:

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun simctl create "iPhone 14 Plus" com.apple.CoreSimulator.SimDeviceType.iPhone-14-Plus
```

Then run the app on it and ⌘S in the Simulator to save each capture at native
size. At least **3** (the first 3 appear on install sheets), up to 10.

- ☐ Suggested set: the empty-state home, a scanned document's Review screen, a
      to-do with a reminder, a guide step, the family profiles screen.
- ☐ Do **not** screenshot the paywall as an App Store screenshot — Apple
      dislikes store pages that lead with a price. That capture is for the
      subscription Review Information only.

### 4.2 App Privacy label ⚠️ REJECTION RISK

Currently **inaccurate**. Source of truth: `legal/app-store-privacy-label.md`.

- ☐ Update from that file. What changed materially: with accounts, data is now
      **Linked to You** (User ID, user content, Purchases), and you collect an
      **email address**. The old "nothing is linked to identity" answers are wrong.
- ☐ Apple cross-checks the label against the shipped privacy manifest, so a
      mismatch is a rejection, not a warning.

### 4.3 App Review Information ⚠️ REJECTION RISK

- ☐ **Demo account**: create a real account in the app and put the email +
      password in the Sign-In Information fields. App Review cannot reach sync,
      family profiles, or account deletion without one, and "we couldn't log in"
      is a near-automatic rejection.
- ☐ **Notes**: explain that the core app works with no account, that an account
      adds sync and backup, and how to reach the paywall (Profile ▸ UPGRADE).
- ☐ Contact phone + email.

### 4.4 The rest of the version page

- ☐ Description, keywords, promotional text, support URL, marketing URL
- ☐ **Age rating** questionnaire
- ☐ **Content rights** — declare whether the app contains third-party content
- ☐ **Export compliance** — HTTPS only, so the standard exemption applies
- ☐ **Category** and pricing (app itself free)

### 4.5 Subscription Review Information — both products

From `tadah_plus_setup.md` §A6; the review notes text is already written there.

- ☐ Attach the paywall screenshot from Phase 3 to **both** Monthly and Yearly
- ☐ Paste the review notes into both
- ☐ Confirm both still read **Ready for Review** and sit in the Draft Submission

---

## Phase 5 — submit

- ☐ **5.1** Attach **build 5** to version 1.0
- ☐ **5.2** Confirm the Draft Submission contains **both** the app version *and*
      the two subscriptions. They must go together — subscriptions submitted
      alone, or an app submitted without them, gets you a second review round.
- ☐ **5.3** Choose the release option. **Manual release** is recommended for a
      first launch: you decide the moment it goes live rather than it appearing
      the instant review passes.
- ☐ **5.4** Add for Review → Submit.
- ☐ **5.5** Expect 24–48h typically. Watch email for "Developer Action Needed".

### After approval

- ☐ Release manually when you're ready
- ☐ Verify a **real** purchase with a real Apple ID (sandbox ≠ production)
- ☐ Watch the D1 metrics for the first real installs
- ☐ Keep the TestFlight group — it is how build 6 gets tested

---

## Known rejection risks for this app, ranked

1. **Paywall linking to RevenueCat's legal pages** instead of yours (§2.1) — the
   single most likely rejection, and it is currently live
2. **Privacy label not matching the manifest** (§4.2) — currently inaccurate
3. **No demo account** for review (§4.3)
4. **Subscription review screenshot missing or a placeholder** (§4.5)
5. **Guideline 3.1.1** — the paywall must clearly state price, period, and what
   Plus adds, and Restore must be reachable. `PaywallView` keeps Restore in
   every state, so this is about the RevenueCat paywall's copy.
6. **Guideline 4.2 "minimum functionality"** — unlikely; the app does a lot
   without an account.

---

## Not gates — do whenever

- ☐ Delete the three unused Apple secrets (`APPLE_TEAM_ID`, `APPLE_KEY_ID`,
      `APPLE_PRIVATE_KEY`). Read the `.p8`-downloads-once warning in
      `testflight_build4_notes.md` first.
- ☐ Re-run `schema.sql` against D1 (the Worker also creates tables lazily).
- ☐ Restore the `Tadah.storekit` scheme reference if it ever goes missing again;
      `Tadah (Real Store)` is the scheme for testing the real store instead.
