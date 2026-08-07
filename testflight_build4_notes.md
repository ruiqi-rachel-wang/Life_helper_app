# TestFlight build 4 — upload checklist & What to Test

> Prepared 2026-08-07. Version 1.0, `CURRENT_PROJECT_VERSION = 4`.
> **Build 3 was never uploaded** — testers are still on **build 2**, so build 4
> carries *both* the build-3 work and everything since. Supersedes
> `testflight_build3_notes.md` (keep that file only for its history).

---

## ⚠️ Two decisions needed BEFORE uploading

### 1. Tadah Plus paywall is live in the UI but wired to the RevenueCat **test store**

`TadahApp.swift` still calls `Purchases.configure(withAPIKey: "test_…")`, and
Profile → **UPGRADE** opens the real `PaywallView`. A tester who taps it gets a
paywall that cannot make a genuine App Store purchase. Pick one:

- **(a) Hide it for build 4** *(recommended, smallest risk)* — point the UPGRADE
  row back at the existing "coming soon" alert (`showPlusComingSoon`) and leave
  the paywall code in place, unreachable. Ship the free tier only.
- **(b) Make it real** — needs, in order: Apple **Paid Apps Agreement** signed;
  subscription products created in App Store Connect; those products added to a
  RevenueCat **Offering** with the `Tadah Pro` entitlement; the app switched to
  the **public Apple key** (`appl_…`). Then test with a sandbox account.

### 2. The new free-tier limits will throttle your testers

Nobody has Plus, so **every tester is on the free tier**: 10 scans+guides/day,
**20 per rolling 30 days**, and **20 tasks total**. Testers are exactly the people
who scan a lot, and a tester who already has more than 20 items will be unable to
add anything. Options: raise the free numbers for the beta, treat testers as Plus,
or ship as-is and say so plainly in the notes (the draft below does).

---

## Checklist

1. ☐ **Deploy the Worker** — the RevenueCat entitlement id was fixed in
   `worker.js` (`PLUS_ENTITLEMENT = "Tadah Pro"`, was `plus`); without a deploy
   the backend treats **every** account as free and applies the one-device limit
   to Plus users.
   `cd Tadah/cloudflare-worker && npx wrangler deploy`
   *(Node 22 needed: `export PATH="/usr/local/opt/node@22/bin:$PATH"`.)*
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
  to-dos are now backed up to your account, so they survive a reinstall or a new
  phone. Check Profile → Backup shows "Backed up …".
- **Two devices (new).** If you have an iPad or a second iPhone, sign in there
  too. A **free account works on one device at a time** — signing in on the
  second should sign the first out with a message. Did that work clearly?
- **If you had to-dos before signing in**, we ask whether to add them to your
  account or use your account's copy. Was that question clear? (Nothing is
  deleted — a backup is always saved first.)
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

- **登录（新）**：我的 → 创建免费账户 → 通过 Apple 登录。你的待办事项会备份到账户，
  重装或换新手机都不会丢。可在 我的 → 备份 查看"已备份…"。
- **两台设备（新）**：如果你有 iPad 或第二台 iPhone，也在那里登录试试。
  **免费账户一次只能在一台设备上使用**——在第二台登录后，第一台应会退出登录并给出提示。
  这个提示清楚吗？
- **如果你在登录前已有待办事项**，我们会询问是把它们添加到账户，还是改用账户里的版本。
  这个问题清楚吗？（不会删除任何内容——系统都会先保存备份。）
- **请注意免费额度**：每天 10 次扫描/指南，每 30 天 20 次，最多 20 条待办事项。
  如果测试时遇到额度不够、影响使用，请告诉我们。
- 扫描一张真实的账单或信件（添加 → 扫描）。金额、日期、步骤对吗？在确认页点"编辑"
  改一改——保存后有没有生效并同步？
- 生活指南："搬家"或"租房"会问邮编并列出你所在地区的水电网公司。公司对吗？
- 提醒：在 我的设置 → 默认提醒时间 设置一个时间，看提醒是否按时到达（以前固定早上 9 点）。
- 请把任何"本该翻译成中文却显示英文"的地方告诉我们。
