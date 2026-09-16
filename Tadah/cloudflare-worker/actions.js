//  actions.js — Tadah Actions: things Tadah does for the user, not just tells
//  them to do. The first kind is `call`: an AI agent phones a business and puts
//  the result back on the to-do.
//
//  WHY THIS IS ITS OWN FILE, and why the handlers take their dependencies as an
//  argument instead of importing them:
//    • worker.js is already ~2,000 lines, and this is a self-contained feature.
//    • Importing resolveSession/checkPlus from worker.js while worker.js imports
//      this file is a circular import. It happens to work for hoisted function
//      declarations, but it is a trap for whoever edits it next.
//    • Injected deps mean this module can be published and run on its own with a
//      fake server and no phone line — which the hackathon repo requires of
//      anything that can place a call.
//
//  THE MONEY RULE. Every path that can dial fails CLOSED. If we cannot prove the
//  caller is entitled and under quota, we do not call. This is the opposite of
//  the tradeoff /sync makes (there, an unreachable RevenueCat must never sign
//  anyone out — being wrong costs the user their session). Here being wrong costs
//  real money on a phone line, so the default flips.

// ── Limits ──────────────────────────────────────────────────────────────────
// Calls are billed PER CALL by the provider, not per minute, so every cap here
// is a count. Sized against $6.99/month Plus at ~$0.05 a call.
export const CALL_MONTH_LIMIT = 10;          // per user, per calendar month
export const CALL_GLOBAL_MONTH_LIMIT = 300;  // circuit breaker across everybody
export const GLOBAL_SCOPE = "*global*";      // reserved scope key in action_usage

// The transcript is evidence, not the product. It is the most sensitive thing
// this feature stores — a recording of a stranger's voice, about someone's
// medical or immigration business — so it has the shortest life of anything in
// the database. The structured result stays; the words go.
export const TRANSCRIPT_TTL_DAYS = 30;

export const CALLE_BASE_URL = "https://api.heycall-e.com";

// How often a status read may ask the provider for a fresh answer. The app polls
// every ~5s while its screen is open; this bounds the provider traffic no matter
// how many devices are watching the same call at once.
export const POLL_REFRESH_MS = 3000;

// Provider errors that mean "this will never work". Surface them and stop. There
// is no retry anywhere in this file: a redial loop on a paid phone line is the
// one bug in this feature that can cost real money overnight while nobody is
// watching.
export const TERMINAL_PROVIDER_ERRORS = new Set([
  "insufficient_balance", "unsupported_region", "unsupported_language",
  "recipient_blocked", "policy_violation", "invalid_phone", "invalid_recipient",
  "no_recipients", "rate_limit_exceeded", "provider_unavailable",
]);

// ── Phone validation ────────────────────────────────────────────────────────
//
// "Businesses only" is enforced by PROVENANCE, not by number type: the number
// must have come from the scanned document or a guide, or be a correction the
// user typed while looking at the confirm screen. It is NOT enforced by guessing
// whether a number is a mobile — plenty of clinics, contractors, landlords and
// one-person offices answer on a mobile or a VoIP line, and rejecting those
// would refuse exactly the small businesses this feature exists to call.
//
// What IS rejected here is the set of numbers that are never a business you meant
// to ring: malformed ones, service codes, and premium-rate traps.

/** Normalize user/document input to E.164, US only. Returns null if it can't. */
export function normalizePhone(raw) {
  if (typeof raw !== "string") return null;
  // Strip everything a document or a human might decorate a number with:
  // "(212) 555-0100 ext. 4" → we keep the digits and drop the extension, because
  // we cannot dial an extension through the provider anyway.
  //
  // The marker is matched together with the digit that follows it. Anchoring on
  // \bx\b instead misses the common "555-0100 x229" — there is no word boundary
  // between "x" and "2" — and the extension digits then silently became part of
  // the number, which fails the length check and rejects a valid business line.
  const cut = raw.split(/(?:\bext(?:ension)?\b|\bx)\.?\s*\d/i)[0];
  const digits = cut.replace(/[^\d+]/g, "");
  let d = digits.startsWith("+") ? digits.slice(1) : digits;
  if (d.length === 10) d = "1" + d;              // bare US number
  if (d.length !== 11 || d[0] !== "1") return null;
  return "+" + d;
}

/**
 * Is this number one we are willing to dial?
 * Returns { ok: true } or { ok: false, reason } with a machine-readable reason.
 */
export function phoneIsCallable(e164) {
  if (typeof e164 !== "string" || !/^\+1\d{10}$/.test(e164)) {
    return { ok: false, reason: "invalid_phone" };
  }
  const npa = e164.slice(2, 5);   // area code
  const nxx = e164.slice(5, 8);   // exchange

  // NANP: area code and exchange both start 2-9. This alone removes 911, 411 and
  // every other 3-digit service code, which cannot survive the +1 + 10 digit
  // shape in the first place — kept explicit so the rule is readable rather than
  // an accident of the format check.
  if (npa[0] === "0" || npa[0] === "1") return { ok: false, reason: "invalid_phone" };
  if (nxx[0] === "0" || nxx[0] === "1") return { ok: false, reason: "invalid_phone" };

  // N11 (211/311/411/511/611/711/811/911) is never a valid area code.
  if (npa[1] === "1" && npa[2] === "1") return { ok: false, reason: "emergency_or_service" };

  // Premium rate: the caller pays by the minute. 900 as an area code, 976 as an
  // exchange. A wrong number here costs the user money on OUR initiative.
  if (npa === "900") return { ok: false, reason: "premium_rate" };
  if (nxx === "976") return { ok: false, reason: "premium_rate" };

  // Toll-free (800/888/877/866/855/844/833) is deliberately ALLOWED. It is what
  // most billers, insurers and government lines actually publish.
  return { ok: true };
}

// ── Goal safety ─────────────────────────────────────────────────────────────
//
// The system prompt tells the agent never to read out a card number. That is the
// second line of defence, not the first: the likely incident is not a jailbreak,
// it is a user pasting their own card number into the goal box because they think
// it will help. So the text is checked here, server-side, before anything dials.

/** Luhn check — the strong signal that a digit run is a payment card. */
export function looksLikeCardNumber(digits) {
  if (!/^\d{13,19}$/.test(digits)) return false;
  let sum = 0;
  let double = false;
  for (let i = digits.length - 1; i >= 0; i--) {
    let n = digits.charCodeAt(i) - 48;
    if (double) { n *= 2; if (n > 9) n -= 9; }
    sum += n;
    double = !double;
  }
  return sum % 10 === 0;
}

const UNSAFE_PHRASES = [
  [/\bssn\b|\bsocial security\b/i, "ssn"],
  [/\b\d{3}-\d{2}-\d{4}\b/, "ssn"],
  [/\bcredit card\b|\bdebit card\b|\bcard number\b/i, "card"],
  [/\bcvv\b|\bcvc\b|\bsecurity code\b/i, "card"],
  [/\brouting number\b|\baccount and routing\b/i, "bank"],
  [/\bmy (?:password|passcode|pin)\b|\bpin number\b/i, "credential"],
  [/\bdate of birth\b|\bdob\b/i, "dob"],
];

/**
 * Returns null when the text is fine, else a short machine-readable reason.
 *
 * Deliberately NOT triggered by long digit runs on their own: a legitimate call
 * very often needs "I'm calling about account 4829105512". Only a Luhn-valid
 * 13-19 digit run is treated as a card, because account numbers essentially
 * never satisfy Luhn by chance.
 */
export function goalIsUnsafe(text) {
  if (typeof text !== "string") return "empty";
  for (const [re, reason] of UNSAFE_PHRASES) if (re.test(text)) return reason;
  for (const run of text.match(/\d[\d\s-]{11,}\d/g) || []) {
    if (looksLikeCardNumber(run.replace(/[\s-]/g, ""))) return "card";
  }
  return null;
}

// ── The call instruction ────────────────────────────────────────────────────
//
// The provider takes one natural-language `task`. Everything the user authorised
// on the confirm screen, and every rule they did not have to think about, is
// assembled here — never on the phone, where it could be edited.

/**
 * `mayAgreeTo` is the user's authorisation, verbatim from the confirm screen.
 * Empty means the agent may commit them to nothing at all, which is the default
 * for a plain question.
 */
export function buildCallTask({ name, goal, mayAgreeTo }) {
  // ⚠️ AN EMAIL ADDRESS IS NOT A NAME — and this one is read aloud to a stranger.
  // An account with no name set shows its email as its display name, and the
  // app sent that straight here, so calls opened with "calling on behalf of
  // someone@example.com": a privacy leak to whoever answered, and the reason the
  // agent sounded broken from its first sentence. The fallback is spoken on
  // every call without a real name, so it has to read naturally in each place
  // `who` appears below (the old "the person I'm calling for" did not).
  const given = (name || "").trim();
  const who = given && !given.includes("@") ? given : "the account holder";
  const allowed = (mayAgreeTo || "").trim();
  return [
    `You are an AI assistant making a phone call on behalf of ${who}.`,
    ``,
    // ⚠️ THE GOAL BELOW IS IN THE USER'S OWN LANGUAGE, NOT THE CALL'S. It comes
    // from the scanned document as the app localized it, so a Chinese or Spanish
    // user hands us a Chinese or Spanish goal — and without this line the model
    // mirrors it and rings a US utility company speaking Chinese. The language
    // the user reads the app in says nothing about what the person answering the
    // phone speaks.
    `Speak ENGLISH for the entire call, whatever language the goal below happens to be written in. Understand the goal in its own language, then carry it out in English.`,
    ``,
    `Open the call by saying: "Hi, I'm an AI assistant calling on behalf of ${who}. Is now a good time to ask a quick question?"`,
    ``,
    `Your goal: ${goal.trim()}`,
    ``,
    allowed
      ? `You may agree to, on ${who}'s behalf: ${allowed}. Nothing else.`
      : `You may not agree to anything at all on ${who}'s behalf. You are only gathering an answer.`,
    ``,
    `Rules:`,
    `- Never say a credit or debit card number, bank or routing number, Social Security number, date of birth, or any password or PIN. If asked for one, say ${who} will follow up directly.`,
    `- Never agree to a charge, a fee, or any payment.`,
    `- Do not commit ${who} to anything beyond what you may agree to above. If pushed, say you will call back.`,
    `- If you are asked whether you are a recording or a robot, say plainly that you are an AI assistant calling for a real person.`,
    `- If you are put on hold for more than one minute, say you will call back, and end the call.`,
    `- End the call after four minutes, or sooner once the goal is met or is clearly not achievable.`,
    `- Speak only English on the call, even if the goal was written in another language.`,
    `- Be brief and polite. Do not negotiate.`,
  ].join("\n");
}

// What we ask the provider to extract once the call is over. Enums carry an
// `unknown` member on purpose: forcing a yes/no out of a call where nobody picked
// up produces a confident wrong answer on someone's to-do.
export const CALL_RESULT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["outcome", "needs_user_action"],
  properties: {
    outcome: {
      type: "string",
      enum: ["done", "partially", "not_done", "unknown"],
      description: "done when the goal was fully achieved. partially when some of it was. not_done when it was refused or impossible. unknown when nobody answered or the call gave no evidence either way.",
    },
    detail: {
      type: "string",
      description: "One plain sentence the caller can act on, in the words a person would use.",
    },
    agreed: {
      type: "string",
      description: "Exactly what was agreed, if anything: date, time, reference or confirmation number. Empty string when nothing was agreed.",
    },
    needs_user_action: {
      type: "string",
      enum: ["yes", "no", "unknown"],
      description: "yes when the business asked for something only the user themselves can do, such as sending a document or calling back in person.",
    },
    next_step: {
      type: "string",
      description: "The single next thing the user should do, or an empty string when there is nothing.",
    },
  },
};

// ── Storage ─────────────────────────────────────────────────────────────────
let actionTablesReady = false;

/** Lazy DDL, mirroring ensureSyncTables: a Worker deployed without running
 *  schema.sql still works instead of 500-ing on the first call. */
export async function ensureActionTables(db) {
  if (actionTablesReady) return;
  await db.exec("CREATE TABLE IF NOT EXISTS actions (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, item_id TEXT, kind TEXT NOT NULL, status TEXT NOT NULL, input_json TEXT NOT NULL, result_json TEXT, transcript TEXT, provider_call_id TEXT, failure_code TEXT, created_at TEXT NOT NULL, ended_at TEXT, polled_at TEXT)");
  await db.exec("CREATE INDEX IF NOT EXISTS idx_actions_user ON actions(user_id, status)");
  // Every webhook delivery is recorded by its provider event id BEFORE we act on
  // it, so a duplicate delivery (which the provider explicitly warns about) is a
  // no-op rather than a second write.
  await db.exec("CREATE TABLE IF NOT EXISTS action_events (event_id TEXT PRIMARY KEY, action_id TEXT NOT NULL, kind TEXT, received_at TEXT NOT NULL)");
  // Same shape as ai_usage: one row per scope per period, where scope is a user
  // id or the reserved global key.
  await db.exec("CREATE TABLE IF NOT EXISTS action_usage (scope TEXT NOT NULL, period TEXT NOT NULL, count INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (scope, period))");
  actionTablesReady = true;
}

/** Test seam: route tests create the tables themselves and need the guard reset
 *  between isolates. */
export function resetActionTableCache() { actionTablesReady = false; }

const monthKey = () => new Date().toISOString().slice(0, 7);

/** Reserve one call against both ceilings, atomically enough for our purposes.
 *  Charges FIRST and asks questions after — see the refund note in the handler. */
async function reserveCallBudget(db, userID) {
  const period = monthKey();
  const bump = db.prepare(
    `INSERT INTO action_usage (scope, period, count) VALUES (?, ?, 1)
     ON CONFLICT(scope, period) DO UPDATE SET count = count + 1
     RETURNING count`
  );
  const [mine, global] = await db.batch([
    bump.bind(userID, period),
    bump.bind(GLOBAL_SCOPE, period),
  ]);
  return {
    mine: mine.results?.[0]?.count ?? Infinity,
    global: global.results?.[0]?.count ?? Infinity,
  };
}

/** Give the reservation back when we know for certain no call was placed. */
async function refundCallBudget(db, userID) {
  const period = monthKey();
  const give = db.prepare(
    "UPDATE action_usage SET count = count - 1 WHERE scope = ? AND period = ? AND count > 0"
  );
  await db.batch([give.bind(userID, period), give.bind(GLOBAL_SCOPE, period)]);
}

// ── Provider ────────────────────────────────────────────────────────────────

/**
 * Place the call. In dry-run mode nothing is dialled and no key is needed, which
 * is how the whole feature is developed and demonstrated before the provider
 * account clears verification — and how anyone can run this module from the
 * public repository without a phone line.
 */
/**
 * One key per INTENT, so a retry can never become a second call.
 *
 * The key used to be the action id — a fresh `crypto.randomUUID()` on every
 * POST /actions. The dangerous case is when this Worker loses CALL-E's reply
 * (`provider_unreachable`): the call may already be ringing, but the action is
 * marked failed, so the one-live-call rule no longer blocks a retry — and the
 * retry minted a NEW key, which CALL-E correctly treats as a new call. The
 * business's phone rings twice. CALL-E's own guidance: "Do not generate a new
 * random key for each network retry."
 *
 * Same person, same to-do, same number, same words, same hour → same key, and
 * CALL-E returns the original call (or refuses with idempotency_conflict)
 * instead of dialling again. The hour bucket is the trade: it lets a deliberate
 * re-ask about the same thing go through later, while a panicked double-tap
 * cannot reach the business twice.
 */
export async function callIdempotencyKey({ userID, itemId, phone, task }, now = new Date()) {
  const hour = now.toISOString().slice(0, 13);
  const bytes = new TextEncoder().encode([userID, itemId || "", phone, task, hour].join("\n"));
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return "tadah-" + [...digest].map((b) => b.toString(16).padStart(2, "0")).join("").slice(0, 48);
}

async function createProviderCall(env, { actionID, task, phone, idempotencyKey }) {
  if (env.CALLE_DRY_RUN === "1") {
    return { ok: true, callID: `dry_${actionID}`, dryRun: true };
  }
  if (!env.CALLE_API_KEY) return { ok: false, code: "not_configured", status: 503 };

  let res;
  try {
    res = await fetch(`${env.CALLE_BASE_URL || CALLE_BASE_URL}/v1/calls`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.CALLE_API_KEY}`,
        "Content-Type": "application/json",
        // Derived from WHAT is being asked, not from this attempt — see
        // callIdempotencyKey. A random per-attempt key let a retry ring twice.
        "Idempotency-Key": idempotencyKey,
      },
      body: JSON.stringify({
        task,
        recipients: [{ phones: [phone], region: "US", locale: "en-US" }],
        result_schema: CALL_RESULT_SCHEMA,
        metadata: { action_id: actionID },
        ...(env.CALLE_WEBHOOK_SECRET && env.CALLE_WEBHOOK_BASE
          ? { webhook_url: `${env.CALLE_WEBHOOK_BASE}/actions/webhook/${env.CALLE_WEBHOOK_SECRET}` }
          : {}),
      }),
    });
  } catch {
    // We do not know whether the request reached the provider, so we do NOT
    // refund and we do NOT retry. The user is told it failed; at worst one
    // allowance is spent on a call that never happened, which is the cheap
    // direction to be wrong in.
    return { ok: false, code: "provider_unreachable", status: 502, keepCharge: true };
  }

  const body = await res.json().catch(() => null);
  if (!res.ok) {
    const code = body?.error?.code || "provider_error";
    // THE ONLY RECORD OF WHY A CALL WAS REFUSED. Without this every rejection —
    // an empty CALL-E balance, an unsupported region, a blocked recipient, a
    // policy refusal — reached the app as the same "please try again", and
    // retrying cannot fix any of them. Status and CALL-E's own code only: no
    // phone number, no goal, no message body (it can echo the request back).
    // Read it with `npx wrangler tail`.
    console.error("calle_create_rejected", JSON.stringify({ status: res.status, code }));
    // A 4xx means the provider rejected the request outright: no line was
    // seized, no money spent, so the allowance goes back.
    return { ok: false, code, status: res.status < 500 ? 400 : 502, keepCharge: res.status >= 500 };
  }
  return { ok: true, callID: body?.id || null };
}

/**
 * Read a finished call back from the provider.
 *
 * The webhook body is NOT trusted as data. It arrives at a URL whose only secret
 * is in the path, so it tells us WHICH call to look at and nothing more; the
 * content always comes from an authenticated fetch with our own key. A forged
 * webhook can therefore cost us one lookup of a call we already own, and nothing
 * else.
 */
async function fetchProviderCall(env, callID) {
  if (env.CALLE_DRY_RUN === "1" || String(callID).startsWith("dry_")) {
    return {
      ok: true,
      call: {
        id: callID,
        status: "completed",
        summary: "Dry run: no call was placed.",
        structured_result: {
          outcome: "unknown", detail: "Dry run: no call was placed.",
          agreed: "", needs_user_action: "unknown", next_step: "",
        },
        task_completed: null,
        completion_confidence: null,
        evidence: [],
        recipients: [],
      },
    };
  }
  if (!env.CALLE_API_KEY) return { ok: false };
  try {
    const res = await fetch(`${env.CALLE_BASE_URL || CALLE_BASE_URL}/v1/calls/${encodeURIComponent(callID)}`, {
      headers: { Authorization: `Bearer ${env.CALLE_API_KEY}` },
    });
    if (!res.ok) {
      console.error("calle_read_failed", JSON.stringify({ status: res.status }));
      return { ok: false };
    }
    return { ok: true, call: await res.json() };
  } catch {
    console.error("calle_read_unreachable");
    return { ok: false };
  }
}

/** Flatten the provider's terminal payload into what the app stores on the task. */
export function summarizeCall(call) {
  const turns = call?.recipients?.[0]?.attempts?.flatMap((a) => a.transcript_turns || []) || [];
  return {
    result: {
      summary: call?.summary ?? null,
      structured: call?.structured_result ?? call?.recipients?.[0]?.structured_result ?? null,
      taskCompleted: call?.task_completed ?? null,
      confidence: call?.completion_confidence ?? null,
      evidence: Array.isArray(call?.evidence) ? call.evidence : [],
    },
    transcript: turns.length
      ? turns.map((t) => `${t.speaker === "bot" ? "Tadah" : "Them"}: ${t.text}`).join("\n")
      : null,
    status: call?.status === "completed" ? "completed"
      : call?.status === "failed" ? "failed"
      : call?.status === "canceled" ? "canceled" : "in_progress",
    failureCode: call?.failure_code ?? null,
  };
}

/**
 * Write a provider payload onto the action. Shared by the webhook and by the
 * status refresh below, so the two paths can never disagree about what a
 * finished call looks like.
 */
async function persistCallOutcome(db, actionID, call) {
  const { result, transcript, status, failureCode } = summarizeCall(call);
  const terminal = status === "completed" || status === "failed" || status === "canceled";
  await db.prepare(
    "UPDATE actions SET status = ?, result_json = ?, transcript = ?, failure_code = ?, ended_at = ?, polled_at = ? WHERE id = ?"
  ).bind(
    status, JSON.stringify(result), transcript, failureCode,
    terminal ? new Date().toISOString() : null, new Date().toISOString(), actionID,
  ).run();
  return { status, result, transcript, failureCode };
}

// ── Constant-time compare ───────────────────────────────────────────────────
// The webhook secret is compared byte by byte with no early exit, so the time
// taken does not leak how much of a guess was right.
export function secretsMatch(a, b) {
  if (typeof a !== "string" || typeof b !== "string") return false;
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// ── Handlers ────────────────────────────────────────────────────────────────
//
// `deps` carries the shared Worker helpers: { json, readJSON, resolveSession,
// checkPlus }. See the header for why they are injected rather than imported.

const MAX_GOAL_CHARS = 600;   // was 400; the app now prepends whom the call is to
const MAX_AGREE_CHARS = 200;
const MAX_NAME_CHARS = 60;

/** POST /actions — authorise, charge, dial. */
export async function handleActionCreate(request, env, deps) {
  const { json, readJSON, resolveSession, checkPlus } = deps;
  if (!env.DB) return json({ error: "Actions not configured" }, 503);
  await ensureActionTables(env.DB);

  const token = request.headers.get("X-Tadah-Session") || "";
  const session = await resolveSession(env.DB, token);
  if (!session) return json({ error: "Session invalid" }, 401);
  const userID = session.user_id;

  // ── Who is allowed to make Tadah phone people ──────────────────────────
  //
  // TWO GATES BEFORE THE TIER CHECK, because both are about identity and the
  // tier is only about money.
  //
  // 1) THE ALLOW-LIST. Calling ships gated (roadmap 1.2: "gated to TestFlight
  //    and Rachel's account"). Without it the only thing standing between a
  //    stranger and a real phone line is CALLE_DRY_RUN — a var that exists to
  //    be switched off for testing, which is not an access control. An UNSET
  //    CALLE_ALLOWLIST means open, so the public release is a secret deletion
  //    rather than a code change.
  //
  // 2) A VERIFIED EMAIL. An unverified address is an unowned one: anyone can
  //    type a stranger's. This feature hands that person an agent that calls
  //    real businesses and speaks as them, so "we'll confirm who you are
  //    later" is the wrong order. Plus alone is a payment, not an identity.
  const allowlist = (env.CALLE_ALLOWLIST || "").split(",").map(s => s.trim()).filter(Boolean);
  if (allowlist.length && !allowlist.includes(userID)) {
    return json({ error: "not_invited", message: "Tadah Calls isn't open to everyone yet." }, 403);
  }

  const account = await env.DB.prepare(
    "SELECT verified_at FROM accounts WHERE user_id = ?").bind(userID).first();
  if (!account || !account.verified_at) {
    return json({ error: "email_unverified", message: "Verify your email address before Tadah calls for you." }, 403);
  }

  // Plus, checked live and FAILING CLOSED. If RevenueCat cannot be reached we
  // cannot prove this person is entitled, and the next step spends money on a
  // phone line, so we decline rather than assume.
  const { known, plus } = await checkPlus(userID, env);
  if (!known) return json({ error: "tier_unavailable", message: "Can't confirm your membership right now. Please try again shortly." }, 503);
  if (!plus) return json({ error: "plus_required", message: "Tadah Plus is needed to have Tadah make a call." }, 402);

  const read = await readJSON(request);
  if (!read.ok) return read.response;
  const body = read.body || {};

  if (body.kind && body.kind !== "call") return json({ error: "unsupported_action" }, 400);

  const phone = normalizePhone(body.phone);
  if (!phone) return json({ error: "invalid_phone", message: "That doesn't look like a US phone number." }, 400);
  const callable = phoneIsCallable(phone);
  if (!callable.ok) {
    return json({ error: callable.reason, message: "Tadah can't call that number." }, 400);
  }

  const goal = typeof body.goal === "string" ? body.goal.trim() : "";
  if (!goal) return json({ error: "missing_goal" }, 400);
  if (goal.length > MAX_GOAL_CHARS) return json({ error: "goal_too_long" }, 400);

  const mayAgreeTo = typeof body.mayAgreeTo === "string" ? body.mayAgreeTo.trim().slice(0, MAX_AGREE_CHARS) : "";
  const name = typeof body.name === "string" ? body.name.trim().slice(0, MAX_NAME_CHARS) : "";

  // Server-side safety scan of everything the user wrote. The system prompt says
  // the same thing to the agent, but a rule the model is asked to follow is not
  // a control — this is.
  const unsafe = goalIsUnsafe(goal) || goalIsUnsafe(mayAgreeTo);
  if (unsafe) {
    return json({
      error: "unsafe_goal", detail: unsafe,
      message: "Please take personal numbers out of the request — Tadah never reads card, bank or Social Security numbers over the phone.",
    }, 400);
  }

  // One live call per user. Two calls at once is how a bug becomes a bill, and
  // there is no legitimate reason for it: the user is looking at one to-do.
  const live = await env.DB.prepare(
    "SELECT id FROM actions WHERE user_id = ? AND status IN ('queued','in_progress') LIMIT 1"
  ).bind(userID).first();
  if (live) return json({ error: "call_in_progress", message: "Tadah is already on a call for you." }, 409);

  // Charge BEFORE dialling. Checking and then charging leaves a window where two
  // requests both see room; charging first means the worst case is an allowance
  // spent on a call that didn't happen, which the refund below cleans up whenever
  // we can be certain of that.
  const used = await reserveCallBudget(env.DB, userID);
  if (used.mine > CALL_MONTH_LIMIT) {
    await refundCallBudget(env.DB, userID);
    return json({ error: "quota_exceeded", limit: CALL_MONTH_LIMIT, message: `You've used all ${CALL_MONTH_LIMIT} calls this month.` }, 429);
  }
  if (used.global > CALL_GLOBAL_MONTH_LIMIT) {
    await refundCallBudget(env.DB, userID);
    return json({ error: "temporarily_unavailable", message: "Calling is paused right now. Please try again later." }, 503);
  }

  const actionID = crypto.randomUUID();
  const now = new Date().toISOString();
  const input = { phone, goal, mayAgreeTo, name, itemId: typeof body.itemId === "string" ? body.itemId : null };

  await env.DB.prepare(
    "INSERT INTO actions (id, user_id, item_id, kind, status, input_json, created_at) VALUES (?, ?, ?, 'call', 'queued', ?, ?)"
  ).bind(actionID, userID, input.itemId, JSON.stringify(input), now).run();

  const task = buildCallTask({ name, goal, mayAgreeTo });
  const idempotencyKey = await callIdempotencyKey({ userID, itemId: input.itemId, phone, task });
  const placed = await createProviderCall(env, { actionID, task, phone, idempotencyKey });

  if (!placed.ok) {
    await env.DB.prepare(
      "UPDATE actions SET status = 'failed', failure_code = ?, ended_at = ? WHERE id = ?"
    ).bind(placed.code, new Date().toISOString(), actionID).run();
    if (!placed.keepCharge) await refundCallBudget(env.DB, userID);
    return json({ error: placed.code, actionId: actionID, message: "Tadah couldn't place the call." }, placed.status || 502);
  }

  await env.DB.prepare(
    "UPDATE actions SET status = 'in_progress', provider_call_id = ? WHERE id = ?"
  ).bind(placed.callID, actionID).run();

  return json({
    ok: true,
    actionId: actionID,
    status: "in_progress",
    dryRun: !!placed.dryRun,
    callsUsed: used.mine,
    callsLimit: CALL_MONTH_LIMIT,
  }, 200);
}

/**
 * POST /actions/status — { actionId } → the action, scoped to this session.
 *
 * A POST rather than GET /actions/:id because this Worker answers POST only, on
 * every route. Not worth relaxing that for one read.
 */
export async function handleActionStatus(request, env, deps) {
  const { json, readJSON, resolveSession } = deps;
  if (!env.DB) return json({ error: "Actions not configured" }, 503);
  await ensureActionTables(env.DB);

  const session = await resolveSession(env.DB, request.headers.get("X-Tadah-Session") || "");
  if (!session) return json({ error: "Session invalid" }, 401);

  const read = await readJSON(request);
  if (!read.ok) return read.response;
  const actionID = typeof read.body?.actionId === "string" ? read.body.actionId : "";
  if (!actionID) return json({ error: "missing_action_id" }, 400);

  // Scoped by user_id in the WHERE clause, never by the id alone — an action id
  // is not a capability, and one account must not be able to read another's call.
  let row = await env.DB.prepare(
    "SELECT id, status, result_json, transcript, failure_code, created_at, ended_at, provider_call_id, polled_at FROM actions WHERE id = ? AND user_id = ?"
  ).bind(actionID, session.user_id).first();
  if (!row) return json({ error: "not_found" }, 404);

  // ASK THE PROVIDER, don't just read our own row.
  //
  // The webhook is the fast path, not the only one. If a delivery is lost, or
  // the webhook secret/base is unset, or the provider simply never calls back,
  // a purely local read would leave this action "in progress" forever — after
  // the user has already been charged a call and is watching a spinner. Polling
  // the provider makes the webhook an optimisation rather than a single point
  // of failure. Throttled, so many devices watching one call cost one request.
  const live = row.status === "queued" || row.status === "in_progress";
  const dueMs = Date.now() - (Date.parse(row.polled_at || 0) || 0);
  if (live && row.provider_call_id && dueMs > POLL_REFRESH_MS) {
    const fetched = await fetchProviderCall(env, row.provider_call_id);
    if (fetched.ok) {
      await persistCallOutcome(env.DB, row.id, fetched.call);
      row = await env.DB.prepare(
        "SELECT id, status, result_json, transcript, failure_code, created_at, ended_at, provider_call_id, polled_at FROM actions WHERE id = ?"
      ).bind(row.id).first();
    } else {
      // Note the attempt even when it failed, so a provider outage can't turn
      // one polling client into a hot loop against it.
      await env.DB.prepare("UPDATE actions SET polled_at = ? WHERE id = ?")
        .bind(new Date().toISOString(), row.id).run();
    }
  }

  return json({
    ok: true,
    actionId: row.id,
    status: row.status,
    result: row.result_json ? JSON.parse(row.result_json) : null,
    transcript: row.transcript || null,
    failureCode: row.failure_code || null,
    createdAt: row.created_at,
    endedAt: row.ended_at,
  }, 200);
}

/**
 * POST /actions/webhook/<secret> — the provider says a call reached a terminal
 * state.
 *
 * This route is dispatched BEFORE the X-Cuevi-Token gate in worker.js, because
 * the provider is not the app and has no reason to hold that shared secret. The
 * path secret is this route's whole authentication, which is why the body is
 * treated as a doorbell rather than as data (see fetchProviderCall).
 */
export async function handleActionWebhook(request, env, path, deps) {
  const { json, readJSON } = deps;
  if (!env.DB) return json({ error: "Actions not configured" }, 503);

  const supplied = path.slice("/actions/webhook/".length);
  if (!env.CALLE_WEBHOOK_SECRET || !secretsMatch(supplied, env.CALLE_WEBHOOK_SECRET)) {
    return json({ error: "Unauthorized" }, 401);
  }
  await ensureActionTables(env.DB);

  const read = await readJSON(request);
  if (!read.ok) return read.response;
  const event = read.body || {};

  // De-dupe on the provider's event id, recorded before we act. The provider
  // documents that a delivery can repeat; without this, a repeat would overwrite
  // a finished action with a second copy of itself.
  const eventID = request.headers.get("CALL-E-Event-Id") || event.id || "";
  if (eventID) {
    const seen = await env.DB.prepare(
      "INSERT OR IGNORE INTO action_events (event_id, action_id, kind, received_at) VALUES (?, ?, ?, ?) RETURNING event_id"
    ).bind(eventID, String(event?.data?.id || ""), String(event.type || ""), new Date().toISOString()).first();
    if (!seen) return json({ ok: true, duplicate: true }, 200);
  }

  // Find our action from the id we sent as metadata, falling back to the
  // provider's call id. Both are ours; neither is taken on trust as content.
  const actionID = event?.data?.metadata?.action_id || null;
  const providerCallID = event?.data?.id || null;
  const row = actionID
    ? await env.DB.prepare("SELECT id, user_id, provider_call_id, status FROM actions WHERE id = ?").bind(actionID).first()
    : providerCallID
      ? await env.DB.prepare("SELECT id, user_id, provider_call_id, status FROM actions WHERE provider_call_id = ?").bind(providerCallID).first()
      : null;
  if (!row) return json({ ok: true, unknown: true }, 200);   // 200: never make the provider retry
  if (row.status === "completed" || row.status === "failed" || row.status === "canceled") {
    return json({ ok: true, alreadyFinal: true }, 200);
  }

  const fetched = await fetchProviderCall(env, row.provider_call_id || providerCallID);
  if (!fetched.ok) return json({ ok: true, deferred: true }, 200);

  await persistCallOutcome(env.DB, row.id, fetched.call);
  return json({ ok: true }, 200);
}

/** Drop transcripts past their retention window. Called from sweepRetention. */
export function transcriptPurgeStatement(db) {
  const cutoff = new Date(Date.now() - TRANSCRIPT_TTL_DAYS * 86400_000).toISOString();
  return db.prepare(
    "UPDATE actions SET transcript = NULL WHERE transcript IS NOT NULL AND ended_at IS NOT NULL AND ended_at < ?"
  ).bind(cutoff);
}
