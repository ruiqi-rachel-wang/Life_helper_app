# Release 1.0 to the App Store — your checklist

> Written 2026-08-24. Everything here is something **you** do: App Store Connect,
> the RevenueCat dashboard, production D1, your phone. Code, tests, and version
> bumps are handled separately and are not listed.
>
> Shipping **build 5**, not build 4 — build 4 predates the per-step scan detail
> and the retention event, and the production Worker was already redeployed for
> both. Work top to bottom.

---

## 1 · Before the build is archived

### 1.1 Paywall legal links — ☑ DONE 2026-08-24

Was pointing at `revenuecat.com/terms` and `/privacy` (template defaults), which
is a Guideline 3.1.2 rejection. Now `tadah-legal.pages.dev/terms` and `/privacy`
in all three locales — verified against the API at paywall revision 36, with no
`revenuecat.com` left anywhere in the paywall.

> The label and the destination are separate components: the Text child holds
> "Terms", the parent **Button** holds the Action URL. Editing the visible words
> does not change where the link goes. Same trap if this ever needs redoing.

### 1.2 The two D1 privacy purges

Both still pending. Do them **before** you fill in the App Privacy label — the
label is a statement about what you hold, so make it true before you sign it.

- ☐ 39 `events` rows carry raw task UUIDs joinable to a user:
      ```
      cd Tadah/cloudflare-worker
      npx wrangler d1 execute cuevi-metrics --remote --command "UPDATE events SET item_id = NULL;"
      ```
- ☐ 11 `sessions` rows carry a joinable `device_id` (worst case: one extra sign-in):
      ```
      npx wrangler d1 execute cuevi-metrics --remote --command "UPDATE sessions SET device_id = '';"
      ```

### 1.3 Raise or confirm the OpenAI spending cap

- ☐ platform.openai.com → Settings → **Limits**. Cost per scan went from
      ~$0.003 to ~$0.005 with per-step detail, and a public launch means
      strangers scanning, not ten testers.

---

## 2 · Build 5 on your phone

- ☐ **2.1** Xcode → scheme **Tadah** → destination **Any iOS Device** →
      Product ▸ Archive → Distribute App ▸ App Store Connect ▸ Upload
- ☐ **2.2** Add it to TestFlight and install it on your phone. Don't submit a
      build you haven't run.

### The six smoke tests — nothing here is covered by the test suite

Each crosses a boundary the tests stub out (Keychain, live Resend, two devices,
StoreKit). All tests passing says nothing about these.

- ☐ **Register → log out → log back in.** To-dos still there.
- ☐ **Password reset end to end** through live Resend and real DNS: request a
      code, get the email, set a new password, sign in. Old password fails,
      other devices signed out.
- ☐ **Sync between two devices**: add an item on one, see it on the other;
      change a reminder time and confirm the *notification* moves, not just the
      displayed time.
- ☐ **Family profiles**: add, rename, reassign a to-do, remove a profile.
      Removing takes that person's to-dos with them.
- ☐ **Free one-device rule**: sign in on a third device, first is signed out
      with a clear message.
- ☐ **Scan a real document** and check the due date's timezone — round-1 tester
      bug #10, fixed in code but never verified on a live scan.

### The paywall, now that the agreement is Active

- ☐ **Confirm Apple is serving the products**: scheme **Tadah (Real Store)** →
      your iPhone → ⌘R → Profile ▸ UPGRADE → console shows
      `[Paywall] StoreKit returned 2/2`. `0/2` means still propagating; wait.
- ☐ **Sandbox purchase**: Settings ▸ App Store ▸ Sandbox Account, sign in as a
      sandbox tester, buy Monthly. Confirm limits actually rise (60 scans/day,
      100 tasks) — not just that the sheet closed.
- ☐ **Restore purchases** after a delete-and-reinstall.
- ☐ **Screenshot the real paywall while it's open.** App Store Connect requires
      it for both subscriptions and rejects placeholders. There is no other way
      to get it.

---

## 3 · App Store Connect

### 3.1 Screenshots — 0 of 10 today, and required

Your slot is **iPhone 6.5" (1284×2778)**. You have no simulator that size; ask
me and I'll create an iPhone 14 Plus one, which is exactly that.

- ☐ At least **3** (the first 3 show on install sheets), up to 10. ⌘S in the
      Simulator saves at native size.
- ☐ Suggested: empty-state home, a scanned document's Review screen, a to-do
      with a reminder, a guide step, family profiles.
- ☐ **Don't** use the paywall as a store screenshot — Apple dislikes store
      pages that lead with a price. That capture is for §3.4 only.

### 3.2 App Privacy label ⚠️ currently inaccurate

- ☐ Update from `legal/app-store-privacy-label.md`. What changed: with accounts,
      data is now **Linked to You** (User ID, user content, Purchases) and you
      collect an **email address**. The old "nothing is linked to identity"
      answers are wrong, and Apple cross-checks the label against the shipped
      privacy manifest — a mismatch is a rejection, not a warning.

### 3.3 App Review Information ⚠️ common rejection

- ☐ **Demo account**: make a real account in the app, put the email + password
      in the Sign-In Information fields. Review can't reach sync, family
      profiles, or account deletion without one.
- ☐ **Notes**: the core app works with no account; an account adds sync and
      backup; the paywall is at Profile ▸ UPGRADE.
- ☐ Contact phone + email.

### 3.4 Subscription Review Information — both products

- ☐ Attach the paywall screenshot from §2 to **both** Monthly and Yearly
- ☐ Paste the review notes already written in `tadah_plus_setup.md` §A6
- ☐ Both should read **Ready for Review** and sit in the Draft Submission

### 3.5 The rest of the version page

- ☐ **Privacy Policy URL → `https://tadah-legal.pages.dev/privacy`** (App
      Information). It currently points at the old cuevi-legal host.
- ☐ Description, keywords, promotional text, support URL, marketing URL
- ☐ Age rating questionnaire
- ☐ Content rights (third-party content?)
- ☐ Export compliance — HTTPS only, so the standard exemption applies
- ☐ Category and pricing (app itself free)

---

## 4 · Submit

- ☐ **4.1** Attach **build 5** to version 1.0
- ☐ **4.2** Confirm the Draft Submission holds **both** the app version *and*
      the two subscriptions. Sent separately, you get a second review round.
- ☐ **4.3** Choose **manual release** — you decide when it goes live, rather
      than it appearing the moment review passes.
- ☐ **4.4** Add for Review → Submit. Typically 24–48h. Watch email for
      "Developer Action Needed".

### After approval

- ☐ Release it when you're ready
- ☐ Buy Plus once with a **real** Apple ID — sandbox is not production
- ☐ Watch D1 for the first real installs, and for `opened` rows arriving
- ☐ Keep the TestFlight group; it's how build 6 gets tested

---

## Most likely rejections for this app, ranked

1. **Paywall linking to RevenueCat's legal pages** (§1.1) — live right now
2. **Privacy label not matching the manifest** (§3.2) — currently inaccurate
3. **No demo account** (§3.3)
4. **Subscription review screenshot missing or a placeholder** (§3.4)
5. **Guideline 3.1.1** — paywall must state price, period, and what Plus adds,
   with Restore reachable. The app keeps Restore in every state, so this is
   about the RevenueCat paywall's own copy.

## Not gates — whenever you feel like it

- ☐ Delete three unused Apple secrets (`APPLE_TEAM_ID`, `APPLE_KEY_ID`,
      `APPLE_PRIVATE_KEY`). Read the `.p8`-downloads-once warning in
      `testflight_build4_notes.md` first.
      ```
      cd Tadah/cloudflare-worker
      for s in APPLE_TEAM_ID APPLE_KEY_ID APPLE_PRIVATE_KEY; do npx wrangler secret delete "$s"; done
      ```
- ☐ Re-run `npx wrangler d1 execute cuevi-metrics --remote --file=schema.sql`
      (the Worker also creates tables lazily)

## Already done — don't redo

- ☑ Paid Apps Agreement, banking, W-9 — **Active 2026-08-23**
- ☑ Legal pages live and current (August 20, 2026), retention disclosure
      included, verified byte-identical to `docs/` on 2026-08-24
- ☑ Legal pages moved to **tadah-legal.pages.dev** on 2026-08-24 — the old
      `cuevi-legal.pages.dev` is deliberately left running (build 4 testers and
      the current App Store Connect field still point at it) but is no longer
      updated. Deploy target is now `--project-name tadah-legal`.
- ☑ Worker deployed with `MAX_TOKENS` 6000 and the `opened` event kind
- ☑ RevenueCat offering `default` Current, both products, en/es/zh-Hans
- ☑ Subscriptions created, priced $6.99 / $59.99, Ready for Review
