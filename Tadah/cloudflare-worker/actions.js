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
// 5, not 10, decided 2026-09-16: a real call has cost about $1.56 in CALL-E
// credits, so ten a month could cost more than a $6.99 Plus subscription earns.
export const CALL_MONTH_LIMIT = 5;          // per user, per calendar month
export const CALL_GLOBAL_MONTH_LIMIT = 300;  // circuit breaker across everybody
export const GLOBAL_SCOPE = "*global*";      // reserved scope key in action_usage
// How long a call counts as "live" for the one-call-at-a-time rule. A real call
// is over in well under this: four minutes of talk, a minute on hold, ringing,
// and CALL-E writing up the result.
export const LIVE_CALL_WINDOW_MINUTES = 30;

// The transcript is evidence, not the product. It is the most sensitive thing
// this feature stores — a recording of a stranger's voice, about someone's
// medical or immigration business — so it has the shortest life of anything in
// the database. The structured result stays; the words go.
export const TRANSCRIPT_TTL_DAYS = 30;

// The languages the app explains documents in. The CALL itself is always in
// English; this is the language the ANSWER comes back in, which is the whole
// point for someone who cannot make the call themselves.
const CALL_LANGUAGES = { en: "English", es: "Spanish", "zh-Hans": "Simplified Chinese" };

/** Unknown or missing input falls back to English rather than refusing. */
export function callLanguageName(code) {
  return CALL_LANGUAGES[String(code || "").trim()] || "English";
}

export const CALLE_BASE_URL = "https://api.heycall-e.com";

// How long to wait for CALL-E to accept a new call. See createProviderCall.
export const CALLE_CREATE_TIMEOUT_MS = 45_000;

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
 * 13-19 digit run is treated as a possible card. Luhn is a conservative
 * heuristic, not proof: some long reference numbers will also match.
 */
export function goalIsUnsafe(text) {
  if (typeof text !== "string") return "empty";
  text = text.normalize("NFKC").replace(/[\u200B-\u200D\uFEFF]/g, "")
    .normalize("NFD").replace(/\p{M}/gu, "").replace(/[‐‑‒–—−]/g, "-");
  for (const [re, reason] of UNSAFE_PHRASES) if (re.test(text)) return reason;
  const translated = [
    [/\b(?:seguro social|seguridad social|nss)\b|社会安全|社會安全|社会保障号|社會保障號|社保号|社保號/i, "ssn"],
    [/\btarjeta (?:de )?(?:credito|debito)\b|\bnumero de (?:la )?tarjeta\b|\bcodigo de seguridad\b|信用卡|借记卡|借記卡|银行卡号|銀行卡號|安全码|安全碼/i, "card"],
    [/\b(?:numero de ruta|cuenta bancaria|cuenta y ruta|iban|clabe)\b|银行账[号户]|銀行[帳賬][號戶]|路由号|路由號/i, "bank"],
    [/\b(?:contrasena|codigo de acceso|mi pin|mi nip|codigo de verificacion)\b|密码|密碼|验证码|驗證碼/i, "credential"],
    [/\bfecha de nacimiento\b|出生日期|出生年月/i, "dob"],
  ];
  for (const [re, reason] of translated) if (re.test(text)) return reason;
  for (const run of text.match(/\d[\d\s.\-]{11,}\d/g) || []) {
    if (looksLikeCardNumber(run.replace(/[\s.\-]/g, ""))) return "card";
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
export function buildCallTask({ name, goal, mayAgreeTo, language = "English" }) {
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
    ...(language === "English"
      ? []
      // The person who gets this answer could not have made the call. Handing
      // them an English summary would put the language barrier back at the end.
      : [`Afterwards, write your summary and every field of the structured result in ${language}. The call is in English; the write-up is not.`]),
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
    // The confirm screen can authorise a payment plan or a later due date, so
    // "never any payment" and "do not negotiate" contradicted the user's own
    // permission, and the agent had to pick which instruction to break.
    `- Never agree to a charge or a fee, and never make a payment on the call. The only exception is an arrangement listed in what you may agree to above, such as a payment plan.`,
    `- Do not commit ${who} to anything beyond what you may agree to above. If pushed, say you will call back.`,
    `- If you are asked whether you are a recording or a robot, say plainly that you are an AI assistant calling for a real person.`,
    `- If you are put on hold for more than one minute, say you will call back, and end the call.`,
    `- End the call after four minutes, or sooner once the goal is met or is clearly not achievable.`,
    `- Speak only English on the call, even if the goal was written in another language.`,
    `- Be brief and polite. Do not bargain for anything beyond what you may agree to above.`,
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

/**
 * The same schema, asking for the free-text fields in the user's language.
 * CALL-E hands these descriptions to its extraction model, so this is what
 * actually decides the language of the answer — the task text alone does not.
 */
export function callResultSchema(language) {
  if (language === "English") return CALL_RESULT_SCHEMA;
  const schema = structuredClone(CALL_RESULT_SCHEMA);
  for (const field of ["detail", "agreed", "next_step"]) {
    schema.properties[field].description += ` Write this in ${language}.`;
  }
  return schema;
}

// ── Storage ─────────────────────────────────────────────────────────────────
let actionTablesReady = false;

/** Lazy DDL, mirroring ensureSyncTables: a Worker deployed without running
 *  schema.sql still works instead of 500-ing on the first call. */
export async function ensureActionTables(db) {
  if (actionTablesReady) return;
  await db.exec("CREATE TABLE IF NOT EXISTS actions (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, item_id TEXT, kind TEXT NOT NULL, status TEXT NOT NULL, input_json TEXT NOT NULL, result_json TEXT, transcript TEXT, provider_call_id TEXT, failure_code TEXT, created_at TEXT NOT NULL, ended_at TEXT, polled_at TEXT)");
  await db.exec("CREATE INDEX IF NOT EXISTS idx_actions_user ON actions(user_id, status)");
  await db.exec("CREATE INDEX IF NOT EXISTS idx_actions_item ON actions(user_id, item_id, created_at)");
  // Record successful processing only, so temporary provider failures can retry.
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
    period,
    mine: mine.results?.[0]?.count ?? Infinity,
    global: global.results?.[0]?.count ?? Infinity,
  };
}

/** Give the reservation back when we know for certain no call was placed. */
async function refundCallBudget(db, userID, period) {
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
export async function callIdempotencyKey({ userID, itemId, phone, task, attempt = 0 }, now = new Date()) {
  const hour = now.toISOString().slice(0, 13);
  // `attempt` counts this intent's earlier REJECTED attempts this hour (see
  // handleActionCreate). CALL-E stores a key with its first answer, so after a
  // definite "no" (a clarifying question, a refused number) the same key can
  // only ever conflict: every retry of that to-do failed with
  // idempotency_conflict until the hour turned, on 2026-09-16. A rejection
  // placed no call, so a fresh key is safe. Attempt 0 adds nothing, so the key
  // for a first try is unchanged.
  const parts = [userID, itemId || "", phone, task, hour];
  if (attempt > 0) parts.push(`attempt:${attempt}`);
  const bytes = new TextEncoder().encode(parts.join("\n"));
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return "tadah-" + [...digest].map((b) => b.toString(16).padStart(2, "0")).join("").slice(0, 48);
}

/**
 * CALL-E's clarifying question(s) from a 422 `call_not_ready`. CALL-E asks
 * instead of guessing (for example which language to speak) and spends no call
 * doing so. The question is the one thing the user can act on, so it goes back
 * to the app instead of a blanket "couldn't place the call". Capped: it is
 * shown on a card and stored on the action.
 */
export function clarifyingQuestions(body) {
  const raw = body?.error?.details?.questions;
  if (!Array.isArray(raw)) return [];
  return raw.filter((q) => typeof q === "string" && q.trim())
    .slice(0, 3)
    .map((q) => q.trim().slice(0, 300));
}

export async function createProviderCall(env, { actionID, task, phone, idempotencyKey, language }) {
  if (env.CALLE_DRY_RUN === "1") {
    return { ok: true, callID: `dry_${actionID}`, dryRun: true };
  }
  if (!env.CALLE_API_KEY) return { ok: false, code: "not_configured", status: 503 };

  let res;
  try {
    res = await fetch(`${env.CALLE_BASE_URL || CALLE_BASE_URL}/v1/calls`, {
      method: "POST",
      // ⚠️ "manual", NEVER "error". The Workers runtime refuses redirect: "error"
      // and fetch throws before sending anything, so from 2026-09-16 evening every
      // call was left 'uncertain' without reaching CALL-E. "manual" still never
      // carries the key to another host: a 3xx is simply a failed response.
      redirect: "manual",
      // CREATING A CALL IS SLOW. CALL-E plans the call before it answers: a
      // clarifying question took 20 s on 2026-09-16. 45 s leaves room for that
      // and stays under the app's 60 s request timeout, so the phone hears back.
      signal: AbortSignal.timeout(CALLE_CREATE_TIMEOUT_MS),
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
        result_schema: callResultSchema(language),
        metadata: { action_id: actionID },
        ...(env.CALLE_WEBHOOK_SECRET && env.CALLE_WEBHOOK_BASE
          ? { webhook_url: `${env.CALLE_WEBHOOK_BASE}/actions/webhook/${env.CALLE_WEBHOOK_SECRET}` }
          : {}),
      }),
    });
  } catch (err) {
    // The error's NAME only: TimeoutError means CALL-E was still planning,
    // TypeError a network failure. The message can carry the URL.
    console.error("calle_create_unreachable", JSON.stringify({ name: err?.name || "unknown" }));
    // We do not know whether the request reached the provider, so we do NOT
    // refund and we do NOT retry. Keep it uncertain so a webhook can recover
    // the accepted call without a second dial.
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
    //
    // `rejected` = a DEFINITE no, which frees the next attempt to use a fresh
    // idempotency key. Not for a 5xx (we can't be sure nothing was created),
    // and never for idempotency_conflict: that answer can mean the ORIGINAL
    // call went through and only its reply was lost, and a fresh key there is
    // exactly how the business's phone would ring twice.
    return {
      ok: false, code, status: res.status < 500 ? 400 : 502,
      keepCharge: res.status >= 500 || code === "idempotency_conflict",
      rejected: res.status < 500 && code !== "idempotency_conflict",
      questions: code === "call_not_ready" ? clarifyingQuestions(body) : [],
    };
  }
  if (typeof body?.id !== "string" || !body.id.trim()) {
    return { ok: false, code: "provider_invalid_response", status: 502, keepCharge: true };
  }
  return { ok: true, callID: body.id };
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
      redirect: "manual",   // not "error": see createProviderCall
      signal: AbortSignal.timeout(15000),
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
  // A status fetch can finish after a webhook. Decide at write time so a stale
  // in-progress snapshot cannot erase the final answer or its retention date.
  await db.prepare(
    "UPDATE actions SET status = ?, result_json = ?, transcript = ?, failure_code = ?, ended_at = ?, polled_at = ? WHERE id = ? AND status IN ('queued','in_progress','uncertain')"
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

  // Refused, never truncated: the end of an authorisation can be the limit on
  // it ("…but nothing after the 30th"), and cutting it off would hand the agent
  // more permission than the user gave.
  const mayAgreeTo = typeof body.mayAgreeTo === "string" ? body.mayAgreeTo.trim() : "";
  if (mayAgreeTo.length > MAX_AGREE_CHARS) return json({ error: "agreement_too_long" }, 400);
  const name = typeof body.name === "string" ? body.name.trim().slice(0, MAX_NAME_CHARS) : "";
  const language = callLanguageName(body.language);

  // Server-side safety scan of everything the user wrote. The system prompt says
  // the same thing to the agent, but a rule the model is asked to follow is not
  // a control — this is.
  const unsafe = goalIsUnsafe(goal) || goalIsUnsafe(mayAgreeTo) || goalIsUnsafe(name);
  if (unsafe) {
    return json({
      error: "unsafe_goal", detail: unsafe,
      message: "Please take personal numbers out of the request — Tadah never reads card, bank or Social Security numbers over the phone.",
    }, 400);
  }

  const requestID = body.requestId;
  if (requestID != null && (typeof requestID !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(requestID))) {
    return json({ error: "invalid_request_id" }, 400);
  }
  const actionID = requestID || crypto.randomUUID();
  const now = new Date().toISOString();
  const itemId = typeof body.itemId === "string" ? body.itemId : null;
  const task = buildCallTask({ name, goal, mayAgreeTo, language });
  // The request's identity: same person, to-do, number and words, same hour.
  // Stored on the row so a retry can find ITS OWN earlier rejections (below).
  const intent = requestID ? `tadah-${requestID}` : await callIdempotencyKey({ userID, itemId, phone, task });
  const business = typeof body.business === "string" ? body.business.trim().slice(0, 200) : null;
  const input = { phone, goal, mayAgreeTo, name, language, itemId, intent, business };
  // The client persists this ID before sending. Replaying it only reads our row:
  // no second reservation or provider POST, even across an hour boundary.
  const replay = async () => {
    const existing = await env.DB.prepare("SELECT * FROM actions WHERE id = ? AND user_id = ?")
      .bind(actionID, userID).first();
    if (!existing) return null;
    if (existing.input_json !== JSON.stringify(input)) return json({ error: "request_conflict" }, 409);
    if (existing.status === "rejected") return json({ error: existing.failure_code || "provider_error",
      actionId: existing.id, questions: existing.result_json ? JSON.parse(existing.result_json).questions : [] }, 400);
    return json({ ok: true, actionId: existing.id, status: existing.status,
      dryRun: String(existing.provider_call_id || "").startsWith("dry_"), callsLimit: CALL_MONTH_LIMIT }, 200);
  };
  if (requestID) { const response = await replay(); if (response) return response; }

  // ONE LIVE CALL PER USER, CLAIMED ATOMICALLY. Two calls at once is how a bug
  // becomes a bill. This used to be a SELECT and then, later, an INSERT, and two
  // requests arriving together (two to-dos, two devices) could both read "no
  // live call" before either wrote one. A single conditional INSERT is one
  // statement, so D1 runs it alone: exactly one request gets the slot.
  //
  // ⚠️ ONLY RECENT ROWS COUNT. The row is written as 'queued' BEFORE CALL-E is
  // asked, and only this request ever moves it on. If the request is cut off in
  // between (the phone drops the connection, or CALL-E answers slower than the
  // app waits), the row stays 'queued' forever, and this check used to lock that
  // person out of calling for good. Nothing older than a real call can run is live.
  const liveSince = new Date(Date.now() - LIVE_CALL_WINDOW_MINUTES * 60_000).toISOString();
  const claim = await env.DB.prepare(
    `INSERT OR IGNORE INTO actions (id, user_id, item_id, kind, status, input_json, created_at)
     SELECT ?, ?, ?, 'call', 'queued', ?, ?
     WHERE NOT EXISTS (SELECT 1 FROM actions WHERE user_id = ? AND status IN ('queued','in_progress','uncertain') AND created_at > ?)`
  ).bind(actionID, userID, itemId, JSON.stringify(input), now, userID, liveSince).run();
  if (!claim.meta?.changes) {
    if (requestID) { const response = await replay(); if (response) return response; }
    return json({ error: "call_in_progress", message: "Tadah is already on a call for you." }, 409);
  }
  // Nothing was placed on a slot we give back, so the row simply goes.
  const release = () => env.DB.prepare("DELETE FROM actions WHERE id = ?").bind(actionID).run();

  // Charge BEFORE dialling, and after the slot: only the request that holds the
  // slot can spend. Checking and then charging would leave a window where two
  // requests both see room; charging first means the worst case is an allowance
  // spent on a call that didn't happen, which the refunds below clean up
  // whenever we can be certain of that.
  const used = await reserveCallBudget(env.DB, userID);
  if (used.mine > CALL_MONTH_LIMIT) {
    await refundCallBudget(env.DB, userID, used.period);
    await release();
    return json({ error: "quota_exceeded", limit: CALL_MONTH_LIMIT, message: `You've used all ${CALL_MONTH_LIMIT} calls this month.` }, 429);
  }
  if (used.global > CALL_GLOBAL_MONTH_LIMIT) {
    await refundCallBudget(env.DB, userID, used.period);
    await release();
    return json({ error: "temporarily_unavailable", message: "Calling is paused right now. Please try again later." }, 503);
  }

  // The account can be deleted while this request is on its way. Don't dial for
  // someone who no longer exists, and don't leave their request behind.
  const stillThere = await env.DB.prepare("SELECT 1 AS ok FROM accounts WHERE user_id = ?").bind(userID).first();
  if (!stillThere) {
    await refundCallBudget(env.DB, userID, used.period);
    await release();
    return json({ error: "Session invalid" }, 401);
  }

  // A fresh key only after THIS request was definitely refused before — the
  // same intent, not merely the same to-do. Counting every rejection on the
  // to-do would let an edited request's refusal hand an earlier, uncertain one
  // a new key, and that is how a business would be rung twice.
  const rejectedBefore = await env.DB.prepare(
    "SELECT COUNT(*) AS n FROM actions WHERE user_id = ? AND status = 'rejected' AND json_extract(input_json, '$.intent') = ?"
  ).bind(userID, intent).first();
  const attempt = rejectedBefore?.n || 0;
  const idempotencyKey = !requestID && attempt ? await callIdempotencyKey({ userID, itemId, phone, task, attempt }) : intent;
  const placed = await createProviderCall(env, { actionID, task, phone, idempotencyKey, language });

  if (!placed.ok) {
    // 'rejected' = CALL-E said a definite no and nothing was dialled; 'uncertain'
    // = anything we can't be sure about. Only 'rejected' earns a fresh key.
    const questions = placed.questions || [];
    await env.DB.prepare(
      "UPDATE actions SET status = ?, failure_code = ?, result_json = ?, ended_at = ? WHERE id = ? AND status IN ('queued','in_progress','uncertain')"
    ).bind(
      placed.keepCharge ? "uncertain" : "rejected", placed.code,
      questions.length ? JSON.stringify({ questions, evidence: [] }) : null,
      placed.keepCharge ? null : new Date().toISOString(), actionID,
    ).run();
    if (placed.keepCharge) return json({ ok: true, actionId: actionID, status: "uncertain", callsUsed: used.mine, callsLimit: CALL_MONTH_LIMIT }, 200);
    if (!placed.keepCharge) await refundCallBudget(env.DB, userID, used.period);
    return json({
      error: placed.code, actionId: actionID, message: "Tadah couldn't place the call.",
      ...(questions.length ? { questions } : {}),
    }, placed.status || 502);
  }

  // A webhook may already have finished the call while creation was returning.
  await env.DB.prepare(
    "UPDATE actions SET status = CASE WHEN status = 'queued' THEN 'in_progress' ELSE status END, provider_call_id = ? WHERE id = ?"
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
  const itemID = typeof read.body?.itemId === "string" ? read.body.itemId : "";
  if (!actionID && !itemID) return json({ error: "missing_action_id" }, 400);
  let row = actionID
    ? await env.DB.prepare("SELECT * FROM actions WHERE id = ? AND user_id = ?").bind(actionID, session.user_id).first()
    : await env.DB.prepare("SELECT * FROM actions WHERE item_id = ? AND user_id = ? ORDER BY created_at DESC, rowid DESC LIMIT 1").bind(itemID, session.user_id).first();
  if (!row) return json({ error: "not_found" }, 404);
  await refreshAction(env, row);
  row = await env.DB.prepare("SELECT * FROM actions WHERE id = ? AND user_id = ?").bind(row.id, session.user_id).first();
  if (!row) return json({ error: "not_found" }, 404);

  return json({
    ok: true,
    actionId: row.id,
    status: row.status,
    business: JSON.parse(row.input_json)?.business || null,
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

  const eventID = request.headers.get("CALL-E-Event-Id") || event.id || "";
  if (eventID && await env.DB.prepare("SELECT event_id FROM action_events WHERE event_id = ?").bind(eventID).first()) {
    return json({ ok: true, duplicate: true }, 200);
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
  if (row.status === "completed" || row.status === "failed" || row.status === "canceled" || row.status === "rejected") {
    return json({ ok: true, alreadyFinal: true }, 200);
  }

  const fetched = await fetchProviderCall(env, row.provider_call_id || providerCallID);
  if (!fetched.ok) return json({ error: "provider_unavailable" }, 503);
  // On an uncertain create, only the authenticated provider payload can bind
  // an otherwise unknown call ID to this action.
  if (fetched.call?.id !== (row.provider_call_id || providerCallID) ||
      (!row.provider_call_id && fetched.call?.metadata?.action_id !== row.id)) {
    return json({ error: "call_mismatch" }, 400);
  }
  await env.DB.prepare("UPDATE actions SET provider_call_id = ? WHERE id = ? AND provider_call_id IS NULL")
    .bind(row.provider_call_id || providerCallID, row.id).run();
  await persistCallOutcome(env.DB, row.id, fetched.call);
  // Record success AFTER the fetch and write. A temporary read failure must
  // remain retryable; repeated successful delivery is a harmless no-op.
  if (eventID) await env.DB.prepare(
    "INSERT OR IGNORE INTO action_events (event_id, action_id, kind, received_at) SELECT ?, id, ?, ? FROM actions WHERE id = ?"
  ).bind(eventID, String(event.type || ""), new Date().toISOString(), row.id).run();
  return json({ ok: true }, 200);
}

/** One shared, atomic refresh claim for status reads and the scheduled job. */
async function refreshAction(env, row) {
  if (!row.provider_call_id) return;
  const due = new Date(Date.now() - POLL_REFRESH_MS).toISOString();
  const claimed = await env.DB.prepare(
    "UPDATE actions SET polled_at = ? WHERE id = ? AND status IN ('queued','in_progress','uncertain') AND (polled_at IS NULL OR polled_at < ?) RETURNING id"
  ).bind(new Date().toISOString(), row.id, due).first();
  if (!claimed) return;
  const fetched = await fetchProviderCall(env, row.provider_call_id);
  if (fetched.ok) await persistCallOutcome(env.DB, row.id, fetched.call);
}

/** Read-only provider reconciliation: never POST a call or spend an allowance. */
export async function reconcileCalls(env) {
  if (!env.DB) return;
  await ensureActionTables(env.DB);
  const rows = await env.DB.prepare(
    "SELECT * FROM actions WHERE status IN ('queued','in_progress','uncertain') AND provider_call_id IS NOT NULL ORDER BY COALESCE(polled_at, created_at) LIMIT 25"
  ).all();
  for (const row of rows.results || []) await refreshAction(env, row);
}

/** Drop transcripts past their retention window. Called from sweepRetention. */
export function transcriptPurgeStatement(db) {
  const cutoff = new Date(Date.now() - TRANSCRIPT_TTL_DAYS * 86400_000).toISOString();
  return db.prepare(
    "UPDATE actions SET transcript = NULL WHERE transcript IS NOT NULL AND ended_at IS NOT NULL AND ended_at < ?"
  ).bind(cutoff);
}
