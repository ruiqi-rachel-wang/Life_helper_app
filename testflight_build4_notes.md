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
     (adds `used_nonces` and `sessions.plus_checked_at`; the Worker also creates
     them lazily).
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
