# Tadah — what's next

> Rewritten 2026-08-28, combining `future_features.md`, `later_ideas.md`,
> `photo_sync_plan.md` and `hackathon_calls_plan.md`. Long-form detail for each
> moved to `archive/`; this is the front door.
> Where the project *is* → `build_plan.md`. What's left to ship → `release_1.0_checklist.md`.

## Done

Part 1 metrics · Part 2 onboarding · Part 3 accounts, family, monetization
*(incl. 3b: email+password replaced Sign in with Apple, 2026-08-15)*

---

## ⚠️ Before the App Store — not before TestFlight

Raised 2026-08-15, **re-verified in code 2026-08-28, all three still open.**
Deliberately skipped for a 10-person beta; "deliberate" stops being a defence
once strangers can sign up.

1. **Email verification doesn't exist.** `verified_at` is written NULL and never
   read — registration issues a session immediately. Anyone can claim an address
   they don't own, and a typo becomes an unreachable live account.
2. **No per-account throttle on register / login / reset.** The only limiter keys
   on session → install id → IP, all caller-controlled, so rotating
   `X-Cuevi-Install` walks straight past it — and it vanishes entirely if
   `RATE_LIMITER` is unbound. Wants a D1 attempt counter per email.
3. **Password minimum 8, no blocklist.** Don't raise the length — this audience
   manages a parent's paperwork and 15 characters means writing it down. Add a
   **common-password blocklist** instead.

Also: `pw_iterations` is stored per account but never read at login, so raising
the client iteration count later would lock everyone out. Read it, or freeze the
constant forever.

---

## Next up, in order

**Part 7 — Photo sync (1.1).** A second device shows the to-do but not the
document image. Needs R2, plus a privacy-policy rewrite (it promises the opposite
in six places) and a privacy-label change. Purely additive.
→ `photo_sync_plan.md` *(kept — you'll use it next)*

**Part 4 — Reminders & personalization.** Smarter defaults per document type.

**Part 5 — Localization & content.** More guides; keep es/zh-Hans complete.

**Part 6 — Tadah Calls.** An AI agent that phones an agency for you. Gated on 1.0
shipping. 8-day plan, schema, guardrails and cost caps already written.
→ `archive/hackathon_calls_plan.md`

---

## Deferred — revisit when someone asks

- **Push notifications (APNs)** — "buzzes when Mom completes a task". Needs a
  server + device tokens. Background App Refresh was tried and rejected.
- **Usage display on Profile** — "12 of 50 scans this month". Doubles as a soft
  Plus nudge.
- **Server-side scan quota** — `ScanQuota` counts per device, so one account on
  three phones gets 3× the allowance, and OpenAI sends the bill.
- **Separate logins per family member** — Mom signs in as herself instead of
  sharing the owner's account.
- **Recoverable deletes** — a removed family profile takes their to-dos with it
  today; consider a 30-day window.

## Engineering debt

- **8a. End-to-end tests for `SyncService.sync()`** — the biggest real gap.
  Every guarantee is tested at helper level; the round trip isn't.
- **8b. App Attest for the AI quota** — `/chat` keys come from caller-supplied
  headers, so quota is honour-system. Cost protection.
- **8c. Storage-ceiling preflight race** — `/sync` counts rows outside the D1
  batch, so two concurrent writes can both pass.
- **8f. External review items** — design changes, not bugs.
- **8e. Smaller follow-ups** — e.g. a "last backed up" indicator.

→ full write-ups in `archive/later_ideas.md`
