# Tadah — what's next

> Updated 2026-09-06. How the app is built → `how_tadah_is_built.md`.
> Getting build 5 through App Review → `release_1.0_checklist.md`.

## The idea

Tadah's promise: **"let me do that for you."** V1 (1.0, in App Review)
understands the letter and says what to do. V2 starts now: Tadah does the
next step.

**Understand → decide the next step → offer to do it → report back.**

| | | Ships as |
|---|---|---|
| **V1 Understand** | scan → explain → to-do | 1.0 (in review) |
| **V2 Act by phone** | production fixes + Calls | 1.0.1 – 1.2 |
| **V3 Act online** | fill forms, upload documents, check status, prepare renewals | 2.0 |
| **V4+ Complete life admin** | email / mail / fax, payment confirmation, multi-step | later |

Nothing else goes into V2. Any new idea must fit the shape: "call the
office", "fill the renewal form", "check my claim", "pay the bill" fit.
"Chat with your documents" does not.

## Order

| | What |
|---|---|
| **V2 · 1.0.1** | Worker only: verify login throttle · logging · lower AI circuit breaker · check retention sweep |
| **V2 · 1.1** | email verification · password blocklist · `pw_iterations` · sync test |
| **V2 · 1.2** | **Calls** on CALL-E: everything CALL-E can do, offered on the **Review** card, Plus + verified email, one confirmed call at a time, 10 a month then credits. **Hackathon build due Sep 14**, gated; public release after 1.1. |
| **1.3** | photo sync · bilingual term toggle · usage readout · server-side quota + App Attest · guides on demand |
| **V3 · 2.0** | browser actions: status checks → prefill public forms → logged-in portals · Tadah finds official numbers |
| **V4+** | payments prepared, human confirms · email / mail / fax · multi-step · push |

Nothing is advertised until it is built (Apple 3.1.2).

---

## 1.0.1 — Production fixes (Worker only)

**Verify the login throttle.** Deployed 2026-09-01 (version `4e544827`),
never tested on production. 10 wrong passwords for one email in 15 min →
15-min cooldown. Test: the 11th attempt returns 429 `too_many_attempts`; a
correct login after 15 min works.

**Add logging.** The Worker has three `console.error` calls and nothing
else, so auth / sync / RevenueCat failures are invisible. One
`log(level, route, code)` helper on every non-2xx and caught error. Never
log bodies, emails, tokens, task content.

**Lower `GLOBAL_DAY_LIMIT` 3000 → ~500.** At 3000 the OpenAI spending cap
trips first and users see a raw error. One constant.

**Check the retention sweep, late September.** Cron `12 4 * * *` deletes
tombstones at 180 days, revoked sessions at 30, usage rows at 60. It has
never had anything to delete yet. Look at the cron log the first morning it
should.

---

## 1.1 — Accounts safe enough to act for people

Once Tadah spends money and talks to businesses for someone, account
ownership matters. This comes before Calls goes public.

**Email verification.** `verified_at` is written NULL and never read.
Anyone can claim an address they don't own.
- On register, email a 6-digit code via Resend. Same shape as
  `password_resets`: hashed, 15-min expiry, 5 attempts.
- Unverified accounts can scan and keep to-dos. Password reset, sync and
  every action need a verified email. "Verify your email" row on Profile
  with resend.
- Existing accounts: mark verified at upgrade.
- Worker + `SignInView` + one Profile row. ~2 days.

**Common-password blocklist.** Minimum stays 8 (longer means written
down). Top-1,000 list in the Worker, checked on register and reset.

**`pw_iterations` is stored but never read.** The client hashes at a fixed
600k. Raising it later locks everyone out. Either read the stored value at
login, or write down that 600k is frozen. Decide before touching it.

**Sign-out wording.** Sign-out now pushes first and refuses offline. Check
`/auth/logout` can't fail silently after that. If it can, queue the revoke
or soften "ends straight away" in `LegalContent.swift`.

**End-to-end test for `SyncService.sync()`.** `SyncServiceTests` covers the
apply helpers; the round trip (paging, envelope authority, save-then-
advance) has no test, and two real bugs lived there. Calls writes results
through it. Stub `URLProtocol`, script responses. ~1 day.

---

## 1.2 — Calls

An AI agent phones a business for the user and puts the result on the
to-do. Plus + verified email. Server-side; the user is never on the line.

**Two tracks, one codebase.**
- **Hackathon build now.** CALL-E's *Your Code Is Calling* closes
  **Sep 14, 11:45 pm Singapore = 11:45 am New York.** Built on CALL-E's
  API, gated to TestFlight and Rachel's account. Not a public release, so
  the 1.1 rule holds.
- **Public release** after 1.1. Same code, flip the gate.

**Scope: whatever CALL-E can do.** Ask a question, confirm coverage, book
or cancel or move an appointment, get a reference number, navigate an IVR
menu, leave a message. The one limit is money and identity: the agent never
gives payment details, SSN or date of birth, and never agrees to a charge.
Anything it may commit the user to is written on the confirm screen first.

**Where it appears: the Review screen, decided 2026-09-09.**
Not Detail — there is no guarantee anyone opens a to-do again. Review is the
moment attention is highest: the user has just scanned a letter and Tadah is
explaining it. The card sits between the steps card and the notes card, so it
reads in order: what this is → what to do → *and I can do this one for you*.
Guides route through Review too, so guide steps get the offer for free.

**The MODEL picks the number, decided 2026-09-10.** The scan now returns a
`phone` field — the one number the document prints to ring. This replaced a
pattern-matching approach that failed on the first real document tested: a
water bill's account number `4160250001` was offered as the number to call,
because any bare ten-digit run looks like a phone number to `NSDataDetector`.
The model reads the whole page and can see that "Customer Service:
(516) 466-4416" is a phone line and "Account Number: …" is not. Cost: about
+195 tokens on the scan prompt (2,978 → ~3,170).

The client still refuses to dial the undialable, whoever chose it — NANP
validity (a US exchange cannot start 0 or 1, which is what makes `416-025-0001`
impossible) and a check against the document's own identifiers. A text scan of
the steps survives as a FALLBACK only, for to-dos scanned before the field
existed. The goal still comes from `StepDetail.script`, which the prompt has
always produced.

**One card, three states, in place.** It morphs; it is not a screen that comes
and goes:

1. **Offer** — "Tadah can make this call", the business and number, the
   suggested goal, `[ Yes, call for me ]`.
2. **Calling** — "Calling Con Edison…", elapsed time, and "You can close this
   — the answer lands on this to-do."
3. **Result** — "Call ended", what was said, what was agreed.

Only the **confirm** step is a separate page, opened by "Yes, call for me".

**Yes = save.** On Review the to-do does not exist yet, so a call would have
nowhere to put its answer. Confirming saves the to-do on the spot, by the same
path as Add to inbox. If you are asking Tadah to phone someone about this
letter, you are keeping the letter — and closing the app mid-call then loses
nothing. The user never taps Add to inbox separately; the call is the
commitment.

**The card travels with the task.** Once saved, the card and whatever state it
holds belong to the to-do, so the result is there later on Detail. This is not
an offer in Detail — a to-do that never had a call never grows a call card.
Scope, decided 2026-09-09: **new scans and newly added items only.** Nothing
retrofits calling onto to-dos added before this shipped.

**The confirm page.** Short; the backend carries the rules.

> **Tadah will call**
> Con Edison · (800) 752-6633
>
> **Ask**
> [editable] Why did the bill go up, and can the late fee be waived?
>
> **May agree to**
> [Nothing ▾]
>
> ☐ Share my account number (···5512)
>
> Tadah won't give out personal information or agree to any charge.
> 1 of 10 calls this month.
>
> **Call now** · How calls work

"May agree to" is the user's authorisation and the only thing the agent may
commit them to; it defaults to "Nothing", which makes a plain question the safe
default. The account-number checkbox is **off by default** and appears only
when the item has one — a billing call genuinely needs it, but it is the user's
data going to a third party, so it is an explicit, visible choice. Card, bank
and SSN numbers are refused server-side regardless of any checkbox. "How calls
work" holds the long version: AI disclosure, the four-minute rule, hold, what
is stored. Screenshot the confirm page for App Review and the video.

**Language — the point of the whole feature.** The card, the goal and the
result are in the user's language; the call happens in **English**. The task
text tells the agent to conduct the call in English, and the result schema asks
for `detail` back in the user's language — CALL-E passes field descriptions to
its extraction model, so there is no extra translation call and no prompt
change. Someone who cannot make an English phone call is exactly who this is
for.

**Where the answer lands.** A note on the to-do — "Tadah called Con Edison,
Sep 9" plus the summary, what was agreed, and the next step. `notes: [String]`
already exists, so there is **no SwiftData migration**, and it syncs to other
devices for free. `needs_user_action: yes` leaves the to-do active. The
in-flight action id lives in UserDefaults keyed by item id, so closing the app
mid-call still finds the result.

**Decisions**

| | Choice | Why |
|---|---|---|
| Provider | **CALL-E**, plain `fetch` from the Worker | required by the hackathon. It plans, dials, handles IVR / hold / voicemail, returns a structured result. |
| Call state | CALL-E holds it | a free Worker has 10 ms CPU per request |
| Result delivery | CALL-E webhook → Worker re-fetches `GET /v1/calls/{id}` and trusts that | the webhook has a `CALL-E-Event-Id` for de-dupe but **no signature**. Secret in the webhook path; treat it as a doorbell. |
| Where the result lives | on the task, server-side | the app doesn't need to be open |
| Live screen | polls `GET /actions/:id` every 5 s | CALL-E suggests first poll at ~60 s, then every 5–10 s |
| Who can call | Plus + verified email (hackathon: Rachel only) | each call costs money |
| Recording | transcript only, 30 days | two-party-consent law. Ask support@heycall-e.com whether audio is kept; turn it off. |
| Language | English, `region: US`, `locale: en-US` | |

**Flow.** App `POST /actions` → Worker checks session, verified email,
Plus, quota (fail closed), inserts `actions` row → `POST
https://api.heycall-e.com/v1/calls` with `Authorization: Bearer` and
`Idempotency-Key: <action id>` (a retry returns the same call, never dials
twice) → CALL-E dials → terminal webhook to `/actions/webhook/<secret>` →
Worker re-fetches, writes `result_json` → app polls while open, else picks
it up on the next `/sync`.

Request body (CALL-E OpenAPI v0.7.0). `task` is built from the goal, the
"may agree to" line, and the fixed rules:

```json
{
  "task": "You are an AI assistant calling on behalf of Maria. Open by saying so. Goal: book the earliest new-patient appointment after Sep 20, mornings only. You may agree to an appointment date and time and nothing else. If asked for insurance details, say Maria will bring her card. Never give any personal numbers. Never agree to any charge. If on hold more than a minute, say you will call back and end the call. End the call after four minutes.",
  "recipients": [{ "phones": ["+12125550100"], "region": "US", "locale": "en-US" }],
  "result_schema": {
    "type": "object", "additionalProperties": false,
    "required": ["outcome", "needs_user_action"],
    "properties": {
      "outcome": { "type": "string", "enum": ["done", "partially", "not_done", "unknown"] },
      "detail": { "type": "string", "description": "One sentence a person can act on." },
      "agreed": { "type": "string", "description": "Exactly what was agreed: date, time, reference number. Empty if nothing." },
      "needs_user_action": { "type": "string", "enum": ["yes", "no", "unknown"] },
      "next_step": { "type": "string" }
    }
  },
  "metadata": { "action_id": "…", "user_hash": "…" },
  "webhook_url": "https://cuevi-ai.ruiqiwang.workers.dev/actions/webhook/<secret>"
}
```

CALL-E returns `summary`, `structured_result`, `task_completed`,
`completion_confidence {score, label}`, `evidence[]`, `transcript_turns[]`.
No model call of ours afterwards. Statuses `queued → in_progress →
completed | failed | canceled`. Show, never retry: `insufficient_balance`,
`unsupported_region`, `recipient_blocked`, `policy_violation`,
`invalid_phone`, `rate_limit_exceeded`, `provider_unavailable`.

**Schema.** Named `actions`, not `calls`, so the next kind slots in. No
more generality than the names until a second action exists.
- `actions (id, user_id, item_id, kind, status, input_json, result_json,
  transcript, provider_call_id, created_at, ended_at)`
- `action_events (id, action_id, kind, payload, at)` — stores every
  `CALL-E-Event-Id`; duplicates are no-ops.
- `action_usage` with a `*global*` row, same shape as `ai_usage`.

`result_json` = CALL-E's `structured_result` + `summary` + `evidence` +
`task_completed` + `completion_confidence`. `agreed` and `next_step` go on
the task as a note or step; an agreed date becomes a reminder.
`needs_user_action: yes` turns the task amber. Transcript kept 30 days.

**Guardrails**
- 10 calls per user per month included, checked before dialling, then paid
  credits (above). Billing is per call, so every cap is a count.
- **No max-duration field, no cancel endpoint.** Length is controlled only
  by the `task` text and CALL-E's dashboard kill switch + rate limit. Set
  both on day one. Check on the first real call that the time rule is
  obeyed.
- One live call per user. Global monthly ceiling, fails closed.
- **No retries, ever.** A failed call surfaces to the user.
- Businesses only, by provenance not number type. Mobile and VoIP numbers
  are fine (clinics, contractors, landlords use them). The number must
  come from the document, a guide, or an explicit user correction. US
  only. Block 911 and other emergency numbers, premium-rate 900, short
  codes. CALL-E's `recipient_blocked` is the second line.
- Agent says it is an AI in the first sentence. In `task`; verify it is
  spoken.
- Never states a card number, bank details, SSN, date of birth, password.
  Also scan the goal server-side for card / SSN patterns and refuse.
- Commits the user only to what the confirm screen's "May agree to" line
  says. Never a charge. Anything outside the line → "I'll call back."
- One call, now, human-confirmed. No queues, scheduling, or batch (CALL-E
  offers both; don't use them).

**Cost.** $0.05 per call, early pricing. 20 free calls per new account, more
on request. 10 calls/month = $0.50 per Plus subscriber against $6.99.

**Money model, decided 2026-09-09: an included allowance, then paid credits.**
Plus includes **10 calls a month**; past that the user buys a credit pack
rather than being cut off. Calling is the one feature with a real per-use cost,
so an unlimited tier would be a bet against the heaviest user — and a hard stop
at 10 switches the best feature off exactly when someone is finding it useful.

- Credits are **consumable in-app purchases**, a product type Tadah has never
  shipped (Plus is a subscription). New product IDs in App Store Connect, and
  RevenueCat treats consumables differently from entitlements: it holds no
  balance, so **the Worker is the ledger**.
- `action_credits (user_id, balance, updated_at)`. The create route spends the
  monthly allowance first, then a credit. A purchase is posted to the Worker
  and validated against RevenueCat before it adds to the balance — never
  trusted from the client.
- Credits never expire and never fold into the monthly allowance: the allowance
  resets on the 1st, credits do not.
- Pricing undecided. A starting point to react to: **10 calls $2.99 / 25 calls
  $5.99** — healthy margin at $0.05 a call, and under the line where a one-off
  top-up needs thinking about.
- ⚠️ **Not in the hackathon build.** The allowance and the ledger's shape land
  now; the consumable IAP itself is App Store Connect work plus a purchase
  flow, and it is not what the last days before Sep 14 are for. Until it ships
  the cap simply stops at 10.

**The metric.** New event kinds `action_offered`, `action_accepted`,
`action_completed`. Funnel: offered → accepted → done. If nobody taps "do
that for me", that is the most important thing to learn. Add the kinds to
`VALID_KINDS` in `worker.js` or they are dropped silently (as `opened`
was). Query goes in `how_to_view_tester_data.md`.

**Done when** a Plus user opens a scanned letter, sees the offer on the
right step, confirms one screen, and reads on the to-do what a real person
said or agreed to, and the maximum monthly cost can be stated from the
code.

### CALL-E hackathon — rules and the eight days

$10,000 pool: Most Practical $4,000, Most Innovative $3,000, two honourable
mentions $1,000, five feedback prizes $200. Judged equally on real-world
impact, idea, technical implementation, product experience + demo.

**Rules**
- Must import and invoke CALL-E at runtime (API, SDK, MCP or Skill).
- New or significantly updated between Jul 23 and Sep 14. Adding Calls
  qualifies.
- Pull request to `CALLE-AI/awesome-phone-call-agents` under
  `apps/typescript/<name>/`: README (setup, usage, side effects, credential
  handling, cancellation), dry-run by default, tests, no secrets, masked
  numbers, English only, branch `feat/<kebab-name>`, run
  `python3 scripts/validate_repository.py`. Tadah's repo is private, so the
  Worker's action module is what gets published.
- Video under 3 minutes on YouTube or Vimeo.
- Text description, CALL-E account email, testing access (TestFlight public
  link + dry-run Worker).
- 18+. New York resident is eligible.

**Eight days.** Deadline is the morning of the 14th, New York time. Treat
the 13th as the last day. App Review for 1.0 runs in parallel.
- **Sep 6.** Sign up at heycall-e.com, **start KYC** (calling is off until
  it clears; duration unknown). API key. Dashboard kill switch + rate
  limit. One real call by curl to a number you own: confirm the disclosure
  is spoken and the four-minute rule holds. Email support about audio
  retention.
- **Sep 7–8.** Worker: `POST /actions`, `GET /actions/:id`,
  `/actions/webhook/<secret>`, the three tables, quota, `CALLE_DRY_RUN`
  mode returning a canned result. Route tests.
- **Sep 9–10.** iOS: the Review card (offer → calling → result), the confirm
  page, the result written onto the to-do. Behind a flag.
- **Sep 11.** Guardrails, metric events. Three real end-to-end calls on a
  phone, one of them a booking.
- **Sep 12.** The PR: action module as a small standalone app with README,
  dry-run, tests. TestFlight build with public link.
- **Sep 13.** Video, one take: real letter, real phone, result on the
  to-do. Submit. Tag `calle-submission`.

---

## 1.3 — Deeper core product

**Photo sync.** A second device shows the to-do but not the photo.
Additive; nothing breaks. Becomes a hard dependency only if 2.0 runs
server-side.
- First, because it gates submission: rewrite the six "photos stay on your
  device" passages in `LegalContent.swift`, run `legal/make_legal_pages.py`,
  deploy with `--branch main`. Privacy label: User Content → Photos, Linked
  to You. Profile → Privacy copy. Tell users before it lands.
- Backend: R2 bucket + binding. `PUT`/`GET /photos/:itemId`, key
  `${user_id}/${item_id}` from the **session**, never from the item id
  alone. ~2 MB cap, JPEG only. Delete with the task; purge `${user_id}/` on
  account deletion. Per-tier storage cap like `ai_usage`.
- Client: `PhotoStash` becomes the not-yet-uploaded holding area. Upload
  after the task push, retryable, never blocking sync. Download lazily on
  Detail open. ~1600 px, JPEG 0.6.
- Cost: R2 free tier is 10 GB, egress free. ~33,000 photos before paying.
- Open: on by default or opt-in. Rachel leans on by default.

**Bilingual term toggle.** The explanation says 确认码; the website asks for
"Confirmation code". Tap a translated label to see the English. Extraction
carries an `english` variant on each label / `DocID`.

**Usage readout on Profile.** "12 of 50 scans · 8 of 20 to-dos · 4 of 10
calls this month." Reads `ScanQuota` and `TaskLimit` against the tier caps.
Also a soft Plus nudge.

**Server-side scan quota + App Attest.** `ScanQuota` counts per device, so
one account on three phones gets 3×, and `/chat`'s quota key is a header an
attacker can rotate. Key `ai_usage` on the user id when a session exists;
the app trusts the Worker's 429. App Attest for guests. Before any launch
where AI cost isn't bounded by tester count. (`/actions` is session-keyed
already.)

**More guides.** 14 now. Only from user requests; each is content +
translation + link check.

**Explain language separate from app language.** Only if asked.

---

## 2.0 — Act online

The documents ask for it constantly: "complete this form online", "upload
proof of address", "check your case status". Tadah offers *"I can fill this
out for you"*, opens the official site, fills what it knows, attaches the
document, and **stops at "Ready to submit"**. The user submits. Same shape:
offer on a step → confirm → result on the task.

**In this order**
1. **Status checks, no login.** USCIS case status, DMV, claim lookup. Read
   a public page, put the answer on the task.
2. **Prefill a public form, stop before submit.** User reviews every field
   on the real page.
3. **Logged-in portals.** Renewals, uploads, account changes. Only after 1
   and 2 work; this is where credentials come in.

**First decision: where the browser runs.**
- On the phone (`WKWebView`, user already logged in): no portal password
  reaches Tadah's servers, the photo is right there, no photo sync needed.
  Phone must stay open.
- Server-side (Cloudflare Browser Rendering): runs while the app is closed,
  but Tadah holds credentials and needs photo sync first.

Lean on-device for 1 and 2. Decide again before 3.

**Also: Tadah finds the number itself.** "Call NYU Langone billing" resolves
to the official number, shows the source, user confirms.

**Never:** bypass a CAPTCHA · store a card number or portal password ·
submit (the human does) · run on a schedule · touch anything but official
government and biller sites.

---

## Later — complete life admin

- **Payments, prepared not made.** Tadah reaches the biller's payment page
  with the amount filled in and stops at **Ready to pay: Con Edison,
  $83.17, Visa •••• 1234 → Confirm**. The human authorises. Tadah never
  holds the card. A bill is a service outside the app, so Apple IAP rules
  don't apply.
- **Email, mail, fax.** Draft → confirm → send.
- **Multi-step.** Call, then fill the form the call asked for, then check
  status a week later. Only once single actions are boring.
- **Push.** Reminders already fire on every device, so nobody misses a
  deadline without it. Worth it once actions finish while the app is
  closed. ~1–1.5 weeks: capability + entitlement, APNs `.p8` as a Worker
  secret, `UIApplicationDelegateAdaptor`, `device_tokens` table, ES256 send
  path. Must respect "Hide details in notifications". Two real devices.
  Background App Refresh was tried and rejected: iOS picks the timing,
  never after a force-quit, off in Low Power Mode.

---

## Debt — when touching that code

- **Storage-ceiling race in `/sync`.** Row count is read outside the D1
  batch; two concurrent syncs can overshoot 200 / 2000 by a row or two.
  Leave it until D1 has interactive transactions.

## Not doing

- **Separate logins per family member.** Doubles the backend (invites,
  permissions, cross-account sharing). Shared account chosen 2026-08-07.
- **Apple Family Sharing for the subscription.** Can't be turned off once
  on; one purchase would cover 6 Apple IDs.
- **Renaming `cuevi-metrics`, the Worker, or the bundle id.** Live
  contracts.
