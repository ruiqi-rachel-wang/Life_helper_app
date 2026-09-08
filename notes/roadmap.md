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
| **V2 · 1.2** | **Calls** on CALL-E: everything CALL-E can do, Plus + verified email, one confirmed call at a time. **Hackathon build due Sep 14**, gated; public release after 1.1. |
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

**Tadah offers; the user doesn't hunt for a button.** The extraction gets
an optional per-step action `{kind: "call", phone, goal}`, filled when the
document gives a number and the step is something a call can finish.
Detail shows on that step: *"You need to call the benefits office to
confirm coverage. Want Tadah to do that?"* Guides can carry the same offer.
In V2 the number must come from the document or a guide; the user can
correct it. (In 2.0 Tadah finds official numbers itself. Permanent rule:
the user sees and confirms the exact recipient.)

**Confirmation screen.** Short. The backend carries the rules.

> **Tadah will call**
> NYU Langone Billing · (212) 555-0100
>
> **Goal**
> Book the earliest new-patient appointment after Sep 20, mornings only.
>
> **May agree to**
> An appointment date and time. Nothing else.
>
> Tadah won't give out personal information or agree to any charge.
> 1 of 10 calls this month.
>
> **Call now** · How calls work

The "May agree to" line is the user's authorisation. For a plain question
it reads "Nothing". "How calls work" holds the long version: AI
disclosure, four-minute rule, hold, what is stored. Screenshot the confirm
screen for App Review and the video.

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
- 10 calls per user per month, checked before dialling. Billing is per
  call, so the cap is a count.
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

**Cost.** $0.05 per call, early pricing. 20 free calls per new account,
more on request. 10 calls/month = $0.50 per Plus subscriber against $6.99.

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
- **Sep 9–10.** iOS: per-step offer, confirm screen, live status, result on
  the task. Behind a flag.
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
