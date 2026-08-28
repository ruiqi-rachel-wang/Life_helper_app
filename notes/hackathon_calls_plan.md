# Part 6 — Tadah Calls (CALL-E hackathon)

> Created 2026-08-20. An AI agent that phones a business on the user's behalf
> and puts the answer back on the to-do. Submitted to **CALL-E**, but scoped as
> a real Tadah feature — the entry and the build are the same thing.
>
> **Status: not started. Gated on build 4 being RELEASED** (Rachel's decision,
> 2026-08-20 — ship build 4 to testers first, then start this).

---

## 1. Why this feature

Life admin *is* phone calls. The dentist, the insurer, the gym that will not let
you cancel online, the clinic that will not say on its website whether it takes
your plan. It is the part of life admin no app has ever taken off you.

Three reasons it fits **Tadah** specifically, which matters more than fitting the
hackathon theme:

- **The backend already exists.** An iOS app cannot place these calls itself —
  it has to be orchestrated server-side. `Tadah/cloudflare-worker/worker.js`
  already has sessions, D1, a rate limiter, fail-closed spend caps and a
  RevenueCat entitlement check. Most entrants will build that from nothing. You
  are adding one route family to something already in production.
- **The scan pipeline is the moat.** "Photograph a letter → the app works out who
  to call and what to ask → it calls them" is a chain nobody else at that
  hackathon can build in a weekend. It is the demo.
- **It justifies Plus.** "60 scans a month" is a limit. "Tadah will make the call
  for you" is a reason to pay $6.99.

---

## 2. Phase 0 — the gate (build 4 released)

Do not start Day 1 until build 4 is **live with testers**. Not archived — released.

- ☐ App Privacy label updated in App Store Connect *(currently inaccurate: with
  accounts, data is Linked to You and you now collect an email address)*
- ☐ The two D1 purges — 39 `events` rows with raw task UUIDs, 11 `sessions` rows
  with joinable `device_id`. **Both before the label goes in.**
- ☐ Six device smoke tests (password reset via live Resend, two-device sync,
  family removal, one-device rule)
- ☐ Build 4 actually released to the tester group

Full detail: `archive/testflight_build4_notes.md`.

**Why this is a hard gate, not caution:** a calling feature draws far more App
Review attention than a notes app does. Walking into that review with a privacy
label you already know is wrong is how a two-week feature becomes a six-week one.

---

## 3. Decisions to make before Day 1

| Decision | Recommendation | Why |
| --- | --- | --- |
| **Voice provider** | Whatever CALL-E's sponsor is. Failing that, **Vapi**. | Sponsored hackathons weight sponsor-API use heavily in judging. Vapi otherwise: one API does STT → LLM → TTS → telephony with webhook events, so you write orchestration, not a media pipeline. |
| **Who holds call state** | **The provider.** | Critical for you: a Cloudflare Worker on the free plan gets **10 ms of CPU per request** (the same limit that pushed PBKDF2 onto the phone). A Worker cannot sit on a 3-minute call. The provider holds the call and posts events; your Worker only writes rows. **No Durable Objects needed.** |
| **App learns the result by** | **Polling `GET /call/:id`** every 2 s while a call is live. | APNs is deferred (`later_ideas.md` §1). A call is under 5 minutes and the user is staring at the screen. Polling is correct here, not a compromise. |
| **Who can call** | **Plus only**, from day one. | The per-minute cost is real money. Free tier gets the compose screen and a paywall. |
| **Recording** | **Do not retain audio. Transcript text only.** | Two-party-consent recording law is the sharpest legal edge in this feature, and you sidestep most of it by never storing a recording. Check what the *provider* retains server-side and turn it off. |
| **Languages** | English only for v1. | The agent's disclosure line and refusal rules need per-language review you do not have time for. |

---

## 4. Architecture

```
iOS app                Cloudflare Worker            Vapi (or sponsor)        PSTN
───────                ─────────────────            ─────────────────        ────
CallComposeView
  │ POST /call ────────►  resolveSession(token)
  │                       checkPlus(userID)
  │                       quota check (fail closed)
  │                       INSERT INTO calls
  │                       ──────────────────────────►  create call ──────────► ☎️
  │ ◄──── { callId }
  │
  │ GET /call/:id  ────►  SELECT … WHERE id AND user_id
  │ (poll, 2s)                    ▲
  │                               │ INSERT call_events
  │                       POST /call/webhook ◄────────  ringing / answered /
  │                       (verify signature!)           ended / transcript
  │ ◄──── outcome + transcript
```

**The key property:** your Worker never holds a connection open. Every
interaction is a short request that writes a row. That is what makes this
buildable on the free plan.

---

## 5. Day-by-day

Roughly **8 working days**. Day 2–4 is the block most likely to overrun.

### Day 1 — Spike. One real call, no app code.

- ☐ Create the provider account, get an API key, buy/assign a phone number
- ☐ Place a call **to your own mobile** with `curl`. Hear the agent talk.
- ☐ Point a webhook at a throwaway endpoint and capture **one real payload of
  every event type** — save them into `notes/` verbatim. These become your test
  fixtures on Day 4, and guessing the shape is the classic way to lose a day.
- ☐ Note the actual per-minute charge on your first invoice line

**Done when:** your phone rang, an AI talked to you, and you have real webhook
JSON saved. Zero Swift written.

> **Do this first, before any design.** Hearing what the agent actually sounds
> like will change your mind about the prompt, and probably about the scope.

### Day 2–3 — D1 + the two write routes

- ☐ Add `calls` and `call_events` to `schema.sql` (§6). Keep the heavy comment
  style already in that file — it is the honest description of the database.
- ☐ Apply: `npx wrangler d1 execute cuevi-metrics --remote --file=schema.sql`
- ☐ `handleCallCreate(request, env)` in `worker.js` — mirror `handleSync`:
  `readJSON()` → `resolveSession(db, token)` → `checkPlus(userID, env)` → quota →
  insert → provider `fetch` → `json({ callId }, 200)`
- ☐ Register `POST /call` in the dispatch block at `worker.js:212`
- ☐ `handleCallStatus` for `GET /call/:id` — **scope the SELECT by `user_id`**,
  never by id alone, or one user can read another's transcript
- ☐ Add `CALL_API_KEY` + `CALL_WEBHOOK_SECRET` via `wrangler secret put`

**Done when:** a `curl` with a real session token starts a real call and the row
lands in D1.

### Day 4 — The webhook (budget the whole day)

- ☐ `handleCallWebhook` — **this endpoint is public and unauthenticated by
  session.** Verify the provider's signature with WebCrypto HMAC and a
  **constant-time compare** before trusting one byte of the body.
- ☐ Reject unsigned/mis-signed with 401 and log nothing from the body
- ☐ Make it **idempotent** — providers retry. Key `call_events` on the provider's
  event id and `INSERT OR IGNORE`, the same trick `events` uses for re-sends.
- ☐ On `ended`: write `seconds`, `outcome`, `transcript`; flip `status`
- ☐ Tests in `routes.test.js` using Day 1's real payloads: happy path, bad
  signature, replayed event, call that ends with nobody answering

**Done when:** `npx vitest` is green and the 59 existing route tests still pass.
Remember `export PATH="/usr/local/opt/node@22/bin:$PATH"`.

### Day 5–6 — iOS, four screens

New folder `Tadah/Tadah/Calls/`, following `Sync/`'s shape (a service + a store,
views under `Screens/`).

- ☐ `Calls/CallService.swift` — POST/poll against `AI/BackendConfig.swift`'s base
  URL, session header exactly as `Sync/SyncService.swift` does it
- ☐ `Calls/CallStore.swift` — `@Observable`, owns poll timer and state machine
- ☐ `Screens/CallComposeView.swift` — number (prefilled from the scan), the goal
  in one sentence, one optional constraint ("any weekday after 4pm")
- ☐ `Screens/CallConfirmView.swift` — restate **verbatim** what Tadah will say
  and to whom; one more tap. This screen *is* the consent record. Do not skip it.
- ☐ `Screens/CallLiveView.swift` — ringing → talking → done, with a Cancel
- ☐ `Screens/CallOutcomeView.swift` — one-line answer, transcript below, and a
  button turning the result into a to-do or a reminder
- ☐ Entry point: a "Have Tadah call for them" row in `Screens/DetailView.swift`,
  gated on `PlusStore.isPlus` → `PaywallView` when false
- ☐ New strings into `Localizable.xcstrings` **additively** (English literal =
  catalog key, per the guide-content convention)

**Done when:** you complete a real call end to end in the Simulator against the
live Worker.

### Day 7 — Guardrails (§7). Not optional, not "after the demo".

### Day 8 — Demo + submit

- ☐ Record the video: real letter, real phone, real audio, answer landing on the
  to-do. **One take, under three minutes, no slides.**
- ☐ Write down cost-per-call and every cap — judges ask, and a real answer is
  what separates a product from a demo
- ☐ Branch + tag the submitted state so it is recoverable
- ☐ Update `build_plan.md` and this file with what actually shipped

---

## 6. Schema

```sql
-- ── Tadah Calls (Part 6) ─────────────────────────────────────────────────────
-- One row per outbound call placed on a signed-in user's behalf. The PROVIDER
-- holds the live call; this table is the record, not the state machine. Nothing
-- here is ever written from the client: user_id comes from the session and every
-- other column comes from a signature-verified webhook.
--
-- ⚠️ NO AUDIO IS EVER STORED — `transcript` is text only, deliberately (see the
-- recording decision in hackathon_calls_plan.md §3).
CREATE TABLE IF NOT EXISTS calls (
  id           TEXT PRIMARY KEY,   -- our UUID, generated Worker-side
  user_id      TEXT NOT NULL,      -- account id from the session (never the client)
  item_id      TEXT,               -- the ActionItem this call is about, or NULL
  provider_id  TEXT,               -- the provider's call id, for webhook matching
  to_number    TEXT NOT NULL,      -- E.164. Businesses only — see §7.
  goal         TEXT NOT NULL,      -- one sentence, clamped, shown to the user first
  status       TEXT NOT NULL,      -- queued|ringing|talking|done|failed|cancelled
  outcome      TEXT,               -- the one-line answer, on 'done'
  transcript   TEXT,               -- full text, no audio
  seconds      INTEGER,            -- billed duration, for the cap
  created_at   TEXT NOT NULL,
  ended_at     TEXT
);

CREATE INDEX IF NOT EXISTS idx_calls_user     ON calls(user_id);
CREATE INDEX IF NOT EXISTS idx_calls_provider ON calls(provider_id);

-- Raw provider webhooks, kept for debugging a call that went strange.
-- event_id is the PROVIDER's id and is the PRIMARY KEY, so retried deliveries
-- INSERT OR IGNORE into a no-op — the same idempotency trick `events` uses.
CREATE TABLE IF NOT EXISTS call_events (
  event_id    TEXT PRIMARY KEY,
  call_id     TEXT NOT NULL,
  kind        TEXT NOT NULL,
  payload     TEXT,               -- raw JSON, clamped
  received_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);
```

Add `call_events` and `calls` to `sweepRetention(db)` — 30 days is plenty, and
transcripts are the most sensitive rows in the database.

---

## 7. Guardrails

### Money — reuse the fail-closed pattern already in `worker.js`

| Guard | Value | Note |
| --- | --- | --- |
| Tier | **Plus only** | Checked with the existing `checkPlus(userID, env)` |
| Per-user | **10 min / month** | Checked **before** dialling, from `SUM(seconds)` |
| Per-call hard cutoff | **5 min** | Set **provider-side**. Never trust the agent to hang up. |
| Concurrency | **1 live call per user** | `SELECT` for a live row before creating |
| Global circuit breaker | monthly ceiling, **fails closed** | Same shape as the `*global*` row in `ai_usage` |
| Retries | **none, ever** | A failed call surfaces to the user. It never redials itself. A retry loop on a paid phone call is the one bug that can cost real money overnight. |

> ⚠️ Size the per-user cap off **Plus**, and enforce it against the **session**,
> not an install header. The `ai_usage` comment block explains why the anonymous
> install-keyed cap had to be sized for the highest legitimate user — the call
> routes are session-authenticated, so they do not have that problem. Do not copy
> the install-id pattern here.

### Safety and law — what decides whether this survives App Review

- ☐ **Businesses only.** Never a private individual's number. Validate against a
  blocklist and reject mobile prefixes where you can.
- ☐ **The agent discloses itself in its opening line**, every call, no setting to
  turn it off. Some states require it; do it everywhere.
- ☐ **No stored audio.** Transcript only, and confirm the provider is not
  retaining recordings on their side either.
- ☐ **Hard refusal list in the system prompt**: never state a card number, bank
  details, SSN, date of birth, or password — even when asked directly, even when
  the human insists.
- ☐ **Server-side check on `goal` too.** The prompt is not the only line of
  defence; scan the user's goal text for card/SSN patterns and reject before
  dialling. A user pasting their card number into "the goal" is the likely
  incident, not a jailbreak.
- ☐ **No queues, no bulk, no scheduling.** One call, now, that a human just
  confirmed. This is the line between an assistant and a robocaller, and it is
  the line App Review cares about.

### Draft system prompt

```
You are an assistant making a phone call on behalf of {first_name}.

Open with exactly: "Hi, I'm an AI assistant calling on behalf of
{first_name}. Is now an okay time to ask a quick question?"

Your only goal: {goal}
{constraint_line}

Rules:
- Never state a card number, bank details, SSN, date of birth, or password.
  If asked, say you don't have that and {first_name} will follow up directly.
- If asked whether you are a recording or a robot, say plainly that you are an
  AI assistant calling for a real person.
- If you are asked to hold beyond a minute, or transferred to a queue, say you
  will call back and end the call.
- If the goal is achieved, or clearly cannot be, thank them and end the call.
- Do not negotiate, agree to charges, or commit {first_name} to anything.
```

That last rule matters more than it looks: an agent that "agrees" to a $40 fee on
someone's behalf is a problem no disclaimer covers.

---

## 8. Cost

Estimate at roughly **$0.07–0.13/min** all-in (platform + telephony + model +
TTS) — **verify against your own first invoice on Day 1**, do not trust this
number. A 4-minute call is then about **$0.30–0.50**.

At 10 min/month/user that is a **~$1/month ceiling per Plus subscriber** against
$6.99 revenue. Comfortable — *provided* the retry rule holds. The failure mode
that hurts is not many users; it is one loop redialling all night.

---

## 9. Risks

| Risk | Mitigation |
| --- | --- |
| Webhook signature verification eats a day | Capture real payloads on Day 1; treat Day 4 as a full day, not an afternoon |
| Provider retains recordings by default | Check and disable on Day 1, before you build anything on top |
| App Review rejects the calling feature | Disclosure line + per-call human confirm + businesses-only + no scheduling. Screenshot the confirm screen in the review notes. |
| Demo call fails live on video | Record the real take early; keep a known-good number that always answers |
| Build 4 close-out overruns into the hackathon | It is portal paperwork and device testing, not code — start it now and do not interleave |

---

## 10. Out of scope

Inbound calls · scheduling a call for later · multi-turn negotiation past one
stated goal · audio playback · any language but English · anything on the free
tier · calling individuals.

---

## 11. Definition of done

The feature is done — hackathon or not — when a Plus user can open a scanned
letter, tap one row, confirm one screen, and two minutes later read a one-line
answer from a real human at a real business on their to-do; and when you can
state, from the code, the maximum it can cost you in a month.
