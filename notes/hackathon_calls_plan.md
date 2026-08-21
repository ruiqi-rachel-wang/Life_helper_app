# Part 6 — Tadah Calls (CALL-E hackathon)

> Created 2026-08-20. An AI agent that phones a business on the user's behalf
> and reports back. Submitted to the **CALL-E** hackathon, but scoped as a real
> Tadah feature — the submission and the build are the same thing.
>
> **Status: not started.** Gated on build 4 (see Phase 0).

---

## Why this feature, and not a throwaway demo

Life admin *is* phone calls. The dentist, the insurer, the gym you cannot cancel
online, the clinic that will not say online whether it takes your plan. It is
the part of life admin an app has never been able to take off you.

It also fits Tadah specifically, which matters more than fitting the theme:

- **The Worker already exists.** An iOS app cannot place these calls itself; the
  call has to be orchestrated server-side. Tadah already has a Cloudflare Worker
  with D1, sessions, and a spend-cap pattern. Most rivals at the hackathon will
  build that plumbing from scratch. It is already built.
- **The scan pipeline is the moat.** Nobody else has "photograph a letter → the
  app extracts who to call and what to ask → it calls them." That chain is the
  demo, and it is unique to Tadah.
- **It justifies Plus far better than quotas do.** "60 scans a month" is a
  limit. "Tadah will make the call for you" is a reason to pay $6.99.

---

## Phase 0 — Gate: close out build 4 *(do not skip)*

Do not start Phase 1 until these are done. Reasons, in order of seriousness:

1. **The App Privacy label is currently wrong** (accounts + email = Linked to
   You). Shipping a *calling* feature on top of an inaccurate privacy label is
   how you get a review rejection that costs weeks.
2. **Two data purges are still pending** — 39 `events` rows with raw task UUIDs,
   11 `sessions` rows with joinable `device_id`. `testflight_build4_notes.md`
   says do these *before* the label goes in.
3. **Six device smoke tests** are unproven by the suite (password reset through
   live Resend, two-device sync, family removal, one-device rule).

Full list: `testflight_build4_notes.md`, "Two decisions needed BEFORE uploading"
and the smoke-test section.

---

## Phase 1 — One demo, one spike *(~1 day)*

**Pick exactly one call type.** The recommended one, because it shows the moat:

> Scan a letter or bill → Tadah pulls out the phone number and the question →
> "Call them and ask whether this is still owed after my appeal" → the call
> happens → the answer lands on the to-do.

**Then place one real call before writing any app code.** A `curl` against the
voice provider, to your own mobile. No Swift, no Worker. You are proving the
provider works and hearing what the agent actually sounds like, which is the
thing most likely to change your mind about the design.

### Choosing the provider

If CALL-E is sponsored by a specific voice API, **use the sponsor's** — these
hackathons weight that heavily in judging. Otherwise:

| Option | Trade-off |
| --- | --- |
| **Vapi** *(recommended)* | One API does STT → LLM → TTS → telephony, with webhook events. Fastest to a working call. ~$0.05–0.10/min all-in. |
| Bland | Similar shape, also purpose-built for outbound. |
| Twilio + OpenAI Realtime | Most control, most work. You wire the media stream yourself. Not a hackathon-week choice. |

**Cost reality:** a 4-minute call is roughly $0.20–0.40. That is small per call
and ruinous if a loop retries it. Phase 4 is not optional.

---

## Phase 2 — Worker routes + D1 *(~2–3 days)*

All of this is TypeScript in `Tadah/cloudflare-worker/`, on infrastructure you
already run. No new cloud, no new language.

**New D1 tables**

- `calls` — `id`, `user_id`, `item_id`, `to_number`, `goal`, `status`,
  `started_at`, `ended_at`, `seconds`, `outcome`, `transcript`
- `call_events` — raw provider webhooks, for debugging when a call goes strange

**New routes** (session auth, exactly like the existing ones)

- `POST /call` — validate, check quota, create the row, ask the provider to dial
- `POST /call/webhook` — provider events: ringing, answered, ended, transcript.
  **Verify the provider's signature**; this endpoint is public.
- `GET /call/:id` — status + outcome for the app to poll

**Follow the patterns already in `worker.js`** — the same session check, the same
fail-closed posture on missing secrets, the same cap structure as the OpenAI
spend guard. Route tests go in `routes.test.js` (59 there now, all passing).

---

## Phase 3 — The iOS surface *(~2–3 days)*

Deliberately small. Four states, no more:

1. **Compose** — from a to-do: number (prefilled from the scan), the goal in one
   sentence, and any constraint ("any weekday after 4pm"). One **Call** button.
2. **Confirm** — restate exactly what Tadah will say and to whom. The user taps
   once more. This screen is doing double duty as consent; do not skip it.
3. **In progress** — poll `GET /call/:id`. Show ringing → talking → done.
4. **Outcome** — the answer in one line, transcript underneath, and a button to
   turn the result into a to-do or a reminder.

The user is **not on the line**. The call happens server-side and reports back.
That is the whole product promise, and it also means no microphone permission
and no CallKit.

---

## Phase 4 — Guardrails *(~1 day, genuinely required)*

**Money** — reuse the pattern you already built for OpenAI:

- Plus-only. Free tier does not get calls at all.
- Per-user cap (suggest **10 minutes/month** on Plus) checked *before* dialling.
- **Hard duration cutoff** — 5 minutes, enforced provider-side, not by trusting
  the agent to hang up.
- Global monthly spend cap that **fails closed**, same as `MAX_TOKENS`.
- No automatic retries. A failed call surfaces to the user; it never redials
  itself.

**Safety and law** — the part that decides whether this survives App Review:

- **Businesses only.** Never a private individual's number.
- **The agent discloses itself** in its opening line: an AI assistant calling on
  behalf of [user's first name]. Some states require this; do it everywhere.
- **Do not store audio.** Keep the text transcript only. Two-party-consent
  recording law is the sharpest edge here, and you avoid most of it by never
  retaining a recording. Confirm what the *provider* retains on their side.
- **Hard blocklist in the system prompt**: never state a card number, SSN, date
  of birth, or password, even if asked directly. Add a server-side check on the
  outbound goal text too — the prompt is not the only line of defence.
- One call at a time per user. No queues, no bulk.

---

## Phase 5 — Submit *(~1 day)*

- **The video is the submission.** Real letter, real phone, real audio of the
  agent talking to a real business, answer landing back on the to-do. One take,
  under three minutes, no slides.
- Write down what it costs per call and what the caps are. Judges ask, and
  having a real answer separates a product from a demo.
- Push a branch and tag it, so the submitted state is recoverable.

---

## Explicitly NOT in scope

Inbound calls · call scheduling for later · multi-turn negotiation past one
stated goal · audio playback UI · languages other than English · anything on the
free tier.

---

## Rough shape

Phase 0 is the unknown — it is portal paperwork and device testing, not code.
Phases 1–5 are about **8–10 working days**, and Phase 2 is the one most likely
to overrun, because webhook signature verification always takes longer than it
looks.
