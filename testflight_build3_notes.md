# TestFlight build 3 — upload checklist & What to Test

> Prepared 2026-07-08 (pre-ship review + Part 1 close-out). Build number is
> already **3**; version 1.0. Everything below was verified from the repo —
> the four ☐ steps need Rachel (Apple/Cloudflare accounts).

## Verified ✅ (2026-07-08)

- Hosted policy pages live at cuevi-legal.pages.dev and byte-identical to
  `docs/` — the privacy page ALREADY discloses the anonymous usage stats
  (Last updated June 23, 2026), matching the in-app policy.
- Terms §6 clarification (any scan sends its text; sensitive guides stay
  on-device) now synced across `legal/terms-of-service.md`, in-app
  `LegalContent.swift`, and `docs/terms.html` — all "Last updated July 8, 2026".
  ☐ needs one `pages deploy` (below) to go live.
- USCIS + guide source links load (200) in a browser context: i-90, n-400,
  i-765, file-online, usa.gov DMV, consumerfinance. (egov case-status blocks
  bots with 403, but no step links to it — it's plain text in the app.)
- Release build contains **no `sk-` key material** and points at the Worker.
- Worker deployed 2026-07-08 with rate limit + per-install quota; guard
  responses verified live (405/401/400).

## Rachel's steps, in order

1. ✅ **Terms page published & verified** (2026-07-08, from this machine):
   live https://cuevi-legal.pages.dev/terms shows "Last updated: July 8, 2026"
   with a working /privacy link.
2. ☐ **Update the App Privacy label in App Store Connect** (App → App Privacy):
   answers changed since build 2 — add **Product Interaction** and **User ID**
   (Analytics, not linked, no tracking) per `legal/app-store-privacy-label.md`.
   Confirm the privacy policy URL field is `https://cuevi-legal.pages.dev/privacy`.
3. ☐ **Upload the archive (already built & staged 2026-07-08):** the signed
   1.0 (3) archive sits in Xcode's Organizer. Xcode → Window ▸ Organizer ▸
   Archives → select "Tadah-build3" → **Distribute App ▸ App Store Connect ▸
   Upload** (sign in if asked). Wait for processing (~10–30 min), then in
   TestFlight add build 3 to the tester group and paste the notes below.
   (CLI upload was attempted — blocked on Apple ID auth, which only Xcode has.)
4. ☐ **OpenAI spending cap** (platform.openai.com → Settings → Limits) if not
   already set — the final $ ceiling behind the Worker's limits.

## What to Test (paste into TestFlight)

**English**

This build is a big update — thank you for testing!
- Look around first: tab pages now have clearer titles, bigger text, and the
  Add page explains the three ways to add something.
- Scan a real bill or letter (Add → Scan). Are the amount, date, and steps
  right? Tap Edit on the review screen and fix anything — did your edits stick?
- Try a life guide: Moving or Renting now asks your ZIP and names your local
  utility companies. Are they the right companies for your area?
- Reminders: change the reminder times on an item; check you get the 9am
  nudges. New: My Settings → Privacy → "Hide details in notifications".
- 中文/Español users: set your language in My Settings and scan — is the
  explanation clear?
- New: the app now sends anonymous usage counts (never your documents or any
  text) so we can see if Tadah helps. You can turn this off in My Settings →
  Privacy.

**中文**

这个版本更新很大——感谢测试！
- 先四处看看：各页面标题更清楚、字体更大，"添加"页会说明三种添加方式。
- 扫描一张真实的账单或信件（添加 → 扫描）。金额、日期、步骤对吗？在确认页点"编辑"改一改——保存后有没有生效？
- 试试生活指南："搬家"或"租房"现在会问你的邮编，并列出你所在地区的水电网公司。列出的公司对吗？
- 提醒：改一改某个事项的提醒时间；看看早上 9 点的提醒有没有来。新功能：我的设置 → 隐私 → "通知中隐藏内容"。
- 在"我的设置"里把语言设为中文再扫描——解释清楚吗？
- 新说明：应用现在会发送匿名使用统计（绝不包含你的文件或任何文字），帮助我们了解 Tadah 是否有用。可在 我的设置 → 隐私 里关闭。
