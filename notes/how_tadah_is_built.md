# How Tadah is built

> Rewritten 2026-09-04 from the old 1,000-line `build_plan.md` (history in
> git). Calls and email verification added 2026-09-16. Describes what is true
> today. Forward plan → `roadmap.md`.

## What it is

Tadah reads a letter, bill or notice (photo → on-device OCR → AI) and tells
you what it is, why you got it, and what to do, in English, Español or 中文.
It turns that into a to-do with reminders. Guides cover the recurring
life-admin jobs (moving, taxes, USCIS forms, …). Built for immigrants and ESL
families managing their own or a parent's paperwork. With Tadah Plus it can
also make the phone call a to-do needs (Tadah Calls).

1.0 (build 6) is live on the App Store. 1.1 adds Calls and email verification.
iOS 17+, iPhone. Swift + SwiftUI only.

## Stack

| Piece | What | Why |
|---|---|---|
| OCR | Apple Vision, on device | free and private; text leaves the phone only for the AI step |
| Extraction | `gpt-5-mini`, `reasoning_effort: low`, via the Worker | needs real reasoning (root cause, conditional steps); ~16–19 s a scan |
| Guide polish | `gpt-4o-mini` | only rewords, keep it cheap |
| Backend | one Cloudflare Worker `cuevi-ai` + one D1 database `cuevi-metrics` | free tier; holds the OpenAI key so it never ships in the app |
| Local data | SwiftData (`TadahSchema` V1, migratable) | the on-device store; sync is a copy, not the source |
| Reminders | `UNUserNotificationCenter`, local | no server needed; overdue = one repeating daily nudge |
| Payments | RevenueCat over StoreKit, entitlement **`Tadah Pro`** | entitlements, restore, paywall editor; free under $2.5k/mo |
| Email | Resend, from `mytadah.com` | password-reset and email-verification codes |
| Calls | CALL-E (AIRUDDER Pte Ltd, Singapore), REST from the Worker | an AI agent phones the business in English; no SDK |
| Translation | Apple Translation framework, iOS 18+ | on device, overlaid on the photo; no cloud fallback by design |

## The app (`Tadah/Tadah/`)

| Folder | Holds |
|---|---|
| `App/` | `TadahApp` entry, `RootTabView` (Inbox · Guides · Add · Profile), `AppRouter`, `AppLanguage` (whole-app language switch, live), `TourGuide` (first-run coach marks), `LegalContent` (privacy + terms text, the single source) |
| `Screens/` | one view per screen: Inbox, Detail, Review, Create, Guides, StepDetail, Profile, SignIn, PasswordReset, VerifyEmail, FamilySharing, Paywall, DocumentTranslation, the first-run sheets; `CallCard` (offer, live status, result) and `CallConfirmView` |
| `Model/` | UI-free data + logic: `ActionItem` (the to-do, a SwiftData `@Model`), `Recurrence`, `Guide` (14 guides), `Profile` / `ProfileStore`, `Account`, `ScanQuota`, `TaskLimit`, `PlusStore`, `Metrics`, `Glossary`, `CallOffer` (which number, what to ask, `PendingCall`, `CallHistory`) |
| `Scanning/` | `VisionOCR`, `RuleBasedParser` (regex first pass), `CameraPicker` |
| `AI/` | `OpenAIClient`, `ScanPrompt`, `GuidePrompt`, `ExtractionService` (merges parser + model), `BackendConfig` (Worker URL + token) |
| `Sync/` | `AuthService`, `PasswordCrypto`, `SessionStore` (one Keychain record), `ReconciliationGate`, `SyncService`, `SyncCoordinator`, `PhotoStash`, `TaskDTO`, `ActionsService` (the call routes), `CallCenter` (owns every call) |
| `Notifications/` | `ReminderScheduler` (fits iOS's 64-pending cap, soonest first), `NotificationDelegate` |
| `Components/`, `Theme/` | shared views; colour + type tokens |

`Model/` never imports SwiftUI. That is the part that would port to Android.
Strings live in one `Localizable.xcstrings` (en / es / zh-Hans, ~1,280 keys);
the English literal is the key.

## The backend (`Tadah/cloudflare-worker/`)

`worker.js` (~2,200 lines), `actions.js` (Calls), `schema.sql`, tests in
`worker.test.js` + `actions.test.js` (helpers) and `routes.test.js` (real
workerd + D1). Every route needs `X-Cuevi-Token` except the CALL-E webhook,
whose only key is the secret in its path.

| Route | Does |
|---|---|
| `POST /` (also `/v1/chat/completions`) | AI proxy → OpenAI. Caps `max_tokens` at 6000; per-install quota; global circuit breaker `GLOBAL_DAY_LIMIT` |
| `POST /events` | anonymous usage events: `confirmed` / `completed` / `opened`, and Calls' `action_offered` / `action_accepted` / `action_completed` |
| `POST /auth/email/register`, `/login` | accounts; login throttled per email (10 failures / 15 min → 15-min cooldown) |
| `POST /auth/email/reset/request`, `/confirm` | 6-digit emailed code: 15 min, single use, 5 attempts, every session revoked on success |
| `POST /auth/email/verify/request`, `/confirm` | 6-digit code to the address on the account: session-authenticated, 30 min, 5 attempts, 60 s resend cooldown |
| `POST /auth/logout` | revokes the session |
| `POST /account/delete` | cascades tasks, profiles, sessions |
| `POST /sync` | push then pull, tasks + profiles, tombstones for deletes |
| `POST /actions` | place a call: session, verified email, live Plus check, phone and goal safety, one live call, monthly allowance charged before dialling |
| `POST /actions/status` | one call, scoped to its owner; refreshes from CALL-E at most every 3 s |
| `POST /actions/webhook/<secret>` | CALL-E's "a call finished" doorbell; de-duplicated, and the result is always re-read from CALL-E |

D1 tables: `accounts`, `sessions`, `tasks`, `profiles`, `password_resets`,
`email_verifications`, `login_attempts`, `account_deletions`, `ai_usage`,
`events`, and for Calls `actions`, `action_events`, `action_usage`. `used_nonces`
is a dead Sign-in-with-Apple leftover; drop it when convenient.

Secrets (`wrangler secret put`): `OPENAI_API_KEY`, `PROXY_TOKEN`,
`REVENUECAT_SECRET`, `PASSWORD_PEPPER` (never rotate: it invalidates every
password), `RESEND_KEY`, `EMAIL_FROM`, `CALLE_API_KEY`,
`CALLE_WEBHOOK_SECRET`. Each fails closed if missing. Plain vars in
`wrangler.toml`: `CALLE_WEBHOOK_BASE`, and `CALLE_DRY_RUN` (`"0"` = real
calls, live since 2026-09-11; `"1"` dials nothing).

Cron `12 4 * * *`: tombstones out at 180 days, revoked sessions at 30, usage
rows at 60, call transcripts at 30. Rate limit 60 req/min, keyed session →
install id → IP.

## How the important parts work

**Passwords.** The phone runs PBKDF2-HMAC-SHA256 at 600k iterations and
sends only the derived key (a free Worker gets 10 ms of CPU per request).
The Worker stores `HMAC(pepper, salt ‖ derivedKey)`; the pepper is a secret,
not a column, so a stolen table can't be attacked offline. Sign in with Apple
was removed 2026-08-15: it authenticates the *device's* Apple ID, so a family
member on their own phone could never reach the shared account.

**Sync.** One round trip: push then pull, last-writer-wins on `updatedAt`,
tombstones for deletes, pages of 25 with a (timestamp, id) watermark kept
per stream. Runs in a private ModelContext so a rollback never discards the
user's in-flight edits. To-dos belong to the **account**: sign-out pushes
first (and refuses offline), then clears the device; sign-in pulls the whole
set. A different account's local data → the app asks "move them to this
account" or "sign out". Nothing ever deletes on the user's behalf.

**Reconciliation gate.** A durable per-user "may not sync yet" flag in
UserDefaults, raised before the session reaches the Keychain, cleared last.
An in-memory flag once let one account's data upload into another's.

**Family.** One account, up to 8 named profiles switched in-app. The owner
profile's id derives from the user id so every device converges on one
owner. Each person can have their own reminder time. Removing a person
removes their to-dos (undo is on the roadmap).

**Plus.** Bought through StoreKit via RevenueCat, on the install's anonymous
RevenueCat id — **no Tadah account needed**. (App Review rejected build 5
under 5.1.1 on 2026-09-07 for requiring sign-in first; registration may only
be offered, never required, for a purchase that isn't account-based.) The
entitlement lives on the Apple ID's App Store receipt, so Restore works signed
out and a guest's Profile shows the full membership card with UPGRADE. An
account is the optional second route: sign-in calls `PlusStore.identify`,
which logs the account id in to RevenueCat and, if the phone was Plus as a
guest but the account isn't, restores the receipt under the account id. That
hand-over needs RevenueCat's restore behaviour left at the default, *Transfer
to new App User ID*. The Worker's `checkPlus` asks RevenueCat about the
account id; a guest never hits a tier-gated route (scans are anonymous and
sized for Plus).

**Calls.** Review offers a call when the scan found a number to ring: the
model returns `phone`, and `CallOffer` still refuses anything undialable or
equal to one of the document's own reference numbers. "Yes, call for me"
checks sign-in, Plus and a verified email first, then opens the confirm page
(who, the number, what to ask, what Tadah may agree to, whether to share the
account number). "Call now" saves the to-do, hands the call to `CallCenter`,
and opens that to-do, which shows the call live and then the answer.
`CallCenter` belongs to the app, not a screen: it places the call with extra
background time, keeps a `PendingCall` breadcrumb, polls every 5 s for ten
minutes then every 30 s, and picks unfinished calls up again at launch and on
return to the app. A failed poll is never a failed call, and nothing redials.
The answer is kept on the phone in `CallHistory`, beside the to-do rather than
inside it, and does not sync. The call is in English; the result comes back in
the user's language through CALL-E's result schema. The Worker is the
authority on everything that costs money; see `actions.js`.

**Email verification** exists for Calls only. Sign-in and register return
`verified`, the account screen offers a code, and a call refused as
`email_unverified` offers the same sheet.

**Photos** stay on the device in 1.0; the policy says so in six places.
`PhotoStash` keeps them across sign-out / sign-in on the same phone. Photo
sync is 1.1.

**Metrics** are opt-in, asked once on first launch. Only kind, day, source,
on-time, a salted item hash, install id and app version. Never text.
Queries → `how_to_view_tester_data.md`.

## Limits

| | Free | Plus |
|---|---|---|
| Scans + guides | 20 / day, 50 / 30 days | 60 / day, 300 / 30 days |
| To-dos | 20 | 100 per profile |
| Profiles / devices | 1 / 1 (a 3rd device signs the 1st out) | 8 / many |
| Calls | none | 5 a month, one at a time |

Enforced in the app (`ScanQuota`, `TaskLimit`, `PlusStore.isPlus`), except
Calls, which the Worker enforces (`CALL_MONTH_LIMIT`, plus a 300-a-month
circuit breaker across everyone). The
Worker's 200 / 2000 task-row ceilings are a storage safety net, not the
commercial limits. Don't print these numbers on the paywall or the App Store
page; Apple treats them as a promise.

## Never rename these

Bundle id `com.ruiqiwang.cuevi` · Worker `cuevi-ai` · D1 `cuevi-metrics` ·
headers `X-Cuevi-Token` / `X-Cuevi-Install` · RevenueCat entitlement
`Tadah Pro` (hardcoded in `PlusStore.swift` and `worker.js`) · product ids
`com.ruiqiwang.cuevi.plus.monthly` / `.yearly` (Apple never lets an id be
reused) · the `PASSWORD_PEPPER` secret.

## Legal pages

Edit `App/LegalContent.swift` only, then from the repo root:

```sh
python3 legal/make_legal_pages.py
npx wrangler pages deploy docs --project-name tadah-legal --branch main --commit-dirty=true
```

Live at `https://tadah-legal.pages.dev/privacy` and `/terms` (not the
`.html` variants, which redirect). Without `--branch main` the deploy lands
on a preview alias and the live page does not change.

## Build, test, deploy

```sh
# from Tadah/ — every xcodebuild call on this Mac needs the DEVELOPER_DIR override
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build-for-testing \
  -project Tadah.xcodeproj -scheme Tadah \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath DerivedData
# unit tests: add   -only-testing:TadahTests   (~280 tests, 24 suites, 10–20 min)

# Worker, from Tadah/cloudflare-worker/ — needs Node 22
export PATH="/usr/local/opt/node@22/bin:$PATH"
npm test              # 62 helper + 99 route tests
npx wrangler deploy   # ships the whole worker.js
```

Paywall testing: the **Tadah** scheme carries a `.storekit` file and shows
test prices. Use the **Real Store** scheme on a phone with a Sandbox Apple ID
to see real prices and buy.

## Costs

Apple Developer $99/yr · OpenAI well under the $20/mo cap at tester scale ·
Cloudflare $0 · Resend $0 · RevenueCat $0. Roughly $10 a month today, plus
CALL-E credits: a real call has cost about $1.56, which is why Plus includes 5.
