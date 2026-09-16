// Pure-logic tests for actions.js — the parts that decide whether a phone line
// gets seized and what gets said on it. Plain Node, no runtime, no network.
//
// The route-level behaviour (auth, Plus gate, quota, webhook de-dupe) lives in
// routes.test.js, where there is a real workerd and a real D1.

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  normalizePhone, phoneIsCallable, looksLikeCardNumber, goalIsUnsafe,
  buildCallTask, summarizeCall, secretsMatch, callIdempotencyKey,
  clarifyingQuestions, createProviderCall,
  callLanguageName, callResultSchema, CALL_RESULT_SCHEMA,
} from "./actions.js";

// ── normalizePhone ──────────────────────────────────────────────────────────

test("normalizePhone accepts the shapes a document actually prints", () => {
  for (const raw of [
    "(212) 555-0100", "212-555-0100", "212.555.0100", "+1 212 555 0100",
    "1-212-555-0100", "2125550100", " +12125550100 ",
  ]) {
    assert.equal(normalizePhone(raw), "+12125550100", `failed on ${raw}`);
  }
});

test("normalizePhone drops an extension rather than dialling it into the number", () => {
  // "(212) 555-0100 ext. 4" must not become +12125551004.
  assert.equal(normalizePhone("(212) 555-0100 ext. 4"), "+12125550100");
  assert.equal(normalizePhone("212-555-0100 x229"), "+12125550100");
});

test("normalizePhone rejects what it cannot dial", () => {
  for (const raw of ["", "911", "555-0100", "+44 20 7946 0958", "abc", null, undefined, 12125550100]) {
    assert.equal(normalizePhone(raw), null, `should reject ${raw}`);
  }
});

// ── phoneIsCallable ─────────────────────────────────────────────────────────

test("phoneIsCallable allows ordinary businesses, including toll-free", () => {
  for (const n of ["+12125550100", "+18005550100", "+18885550100", "+19175550100"]) {
    assert.equal(phoneIsCallable(n).ok, true, `should allow ${n}`);
  }
});

test("phoneIsCallable does NOT reject mobile-style numbers", () => {
  // The whole point of enforcing "businesses only" by provenance: a clinic, a
  // contractor or a landlord answering on a mobile must still be callable.
  assert.equal(phoneIsCallable("+19295550123").ok, true);
  assert.equal(phoneIsCallable("+13475550123").ok, true);
});

test("phoneIsCallable blocks service codes, premium rate and malformed numbers", () => {
  assert.equal(phoneIsCallable("+19115550100").reason, "emergency_or_service");
  assert.equal(phoneIsCallable("+14115550100").reason, "emergency_or_service");
  assert.equal(phoneIsCallable("+19005550100").reason, "premium_rate");
  assert.equal(phoneIsCallable("+12129765100").reason, "premium_rate");
  assert.equal(phoneIsCallable("+11125550100").reason, "invalid_phone");   // NPA starts 1
  assert.equal(phoneIsCallable("+12121550100").reason, "invalid_phone");   // NXX starts 1
  assert.equal(phoneIsCallable("+442079460958").reason, "invalid_phone");  // not US
});

// ── goal safety ─────────────────────────────────────────────────────────────

test("looksLikeCardNumber uses Luhn, not just length", () => {
  assert.equal(looksLikeCardNumber("4111111111111111"), true);   // classic test Visa
  assert.equal(looksLikeCardNumber("4111111111111112"), false);  // one digit off
  assert.equal(looksLikeCardNumber("123"), false);
  assert.equal(looksLikeCardNumber("12345678901234567890"), false); // 20 digits
});

test("goalIsUnsafe catches a pasted card number, spaced or hyphenated", () => {
  assert.equal(goalIsUnsafe("pay with 4111 1111 1111 1111 please"), "card");
  assert.equal(goalIsUnsafe("card is 4111-1111-1111-1111"), "card");
});

test("goalIsUnsafe catches the phrases and the SSN shape", () => {
  assert.equal(goalIsUnsafe("give them my SSN"), "ssn");
  assert.equal(goalIsUnsafe("my number is 123-45-6789"), "ssn");
  assert.equal(goalIsUnsafe("read out the CVV"), "card");
  assert.equal(goalIsUnsafe("tell them my routing number"), "bank");
  assert.equal(goalIsUnsafe("give my password to them"), "credential");
  assert.equal(goalIsUnsafe("confirm my date of birth"), "dob");
});

test("goalIsUnsafe leaves a legitimate long account number alone", () => {
  // This is the false positive that would matter: a real call very often needs
  // "I'm calling about account …". Only a Luhn-valid run is treated as a card.
  assert.equal(goalIsUnsafe("Ask about account 829105512347 on the bill"), null);
  assert.equal(goalIsUnsafe("Do you accept the Fidelis Essential Plan?"), null);
  assert.equal(goalIsUnsafe("Ask what documents I need to bring on the 20th"), null);
});

// ── the call instruction ────────────────────────────────────────────────────

test("buildCallTask always discloses the AI and always forbids the money answers", () => {
  const task = buildCallTask({ name: "Maria", goal: "Ask if they take Fidelis", mayAgreeTo: "" });
  assert.match(task, /I'm an AI assistant calling on behalf of Maria/);
  assert.match(task, /Never say a credit or debit card number/);
  assert.match(task, /Never agree to a charge/);
  assert.match(task, /end the call/i);
});

test("buildCallTask says 'nothing at all' when the user authorised nothing", () => {
  const task = buildCallTask({ name: "Maria", goal: "Ask if they take Fidelis", mayAgreeTo: "" });
  assert.match(task, /may not agree to anything at all/);
});

test("buildCallTask carries the user's authorisation verbatim, and closes it", () => {
  const task = buildCallTask({
    name: "Maria",
    goal: "Book the earliest new-patient appointment after Sep 20",
    mayAgreeTo: "An appointment date and time, mornings only",
  });
  assert.match(task, /You may agree to, on Maria's behalf: An appointment date and time, mornings only\. Nothing else\./);
});

test("buildCallTask pins the spoken call to English when the goal is not", () => {
  // The goal arrives in the user's app language. Without an explicit
  // instruction the model mirrors it and rings a US business in Chinese.
  const task = buildCallTask({
    name: "Maria",
    goal: "\u8be2\u95ee\u8d26\u5355\u80fd\u5426\u5ef6\u671f\u652f\u4ed8",
    mayAgreeTo: "",
  });
  assert.match(task, /Speak ENGLISH for the entire call/);
  assert.match(task, /Speak only English on the call/);
  // The goal itself is still carried verbatim — we translate the delivery, not
  // the instruction, so nothing about what was asked for is lost.
  assert.ok(task.includes("\u8be2\u95ee\u8d26\u5355\u80fd\u5426\u5ef6\u671f\u652f\u4ed8"));
});

test("buildCallTask still works when the account has no name on it", () => {
  const task = buildCallTask({ name: "", goal: "Ask about hours", mayAgreeTo: "" });
  assert.match(task, /on behalf of the account holder/);
});

// An account with no name shows its EMAIL as its display name, and the name is
// read aloud to whoever answers. That was a privacy leak on every such call.
test("buildCallTask never reads an email address out as the caller's name", () => {
  const task = buildCallTask({ name: "someone@example.com", goal: "Ask about hours", mayAgreeTo: "" });
  assert.ok(!task.includes("@"), "an email address would be read aloud to a stranger");
  assert.match(task, /on behalf of the account holder/);
});

// A retry must never become a second call to the same business.
test("callIdempotencyKey is stable for one intent and changes when the intent does", async () => {
  const intent = { userID: "u1", itemId: "i1", phone: "+12125550100", task: "Ask about hours" };
  const at = new Date("2026-09-13T04:10:00Z");
  const key = await callIdempotencyKey(intent, at);
  assert.equal(key, await callIdempotencyKey(intent, new Date("2026-09-13T04:59:00Z")),
    "a retry within the hour must reuse the key, or CALL-E dials again");
  assert.notEqual(key, await callIdempotencyKey({ ...intent, task: "Ask about fees" }, at));
  assert.notEqual(key, await callIdempotencyKey({ ...intent, phone: "+12125550101" }, at));
  assert.ok(key.length <= 255, "CALL-E caps Idempotency-Key at 255");
});

// ── result flattening ───────────────────────────────────────────────────────

test("summarizeCall pulls the structured answer and joins the transcript", () => {
  const out = summarizeCall({
    status: "completed",
    summary: "They accept the plan.",
    structured_result: { outcome: "done", detail: "They accept Fidelis Essential." },
    task_completed: true,
    completion_confidence: { score: 0.92, label: "high" },
    evidence: ["The receptionist said yes."],
    recipients: [{
      attempts: [{
        transcript_turns: [
          { speaker: "bot", text: "Do you accept Fidelis Essential?" },
          { speaker: "user", text: "Yes we do." },
        ],
      }],
    }],
  });
  assert.equal(out.status, "completed");
  assert.equal(out.result.structured.outcome, "done");
  assert.equal(out.result.confidence.label, "high");
  assert.equal(out.transcript, "Tadah: Do you accept Fidelis Essential?\nThem: Yes we do.");
});

test("summarizeCall survives a call that produced nothing", () => {
  const out = summarizeCall({ status: "failed", failure_code: "no_answer" });
  assert.equal(out.status, "failed");
  assert.equal(out.failureCode, "no_answer");
  assert.equal(out.transcript, null);
  assert.equal(out.result.structured, null);
});

test("summarizeCall falls back to the recipient's structured result", () => {
  const out = summarizeCall({
    status: "completed",
    recipients: [{ structured_result: { outcome: "partially" }, attempts: [] }],
  });
  assert.equal(out.result.structured.outcome, "partially");
});

// ── webhook secret ──────────────────────────────────────────────────────────

test("secretsMatch compares exactly and survives bad input", () => {
  assert.equal(secretsMatch("abc123", "abc123"), true);
  assert.equal(secretsMatch("abc123", "abc124"), false);
  assert.equal(secretsMatch("abc123", "abc1234"), false);
  assert.equal(secretsMatch("", ""), true);
  assert.equal(secretsMatch(null, "abc"), false);
  assert.equal(secretsMatch("abc", undefined), false);
});

// ── The language the ANSWER comes back in ───────────────────────────────────
//
// The call is always in English. Someone who cannot make an English phone call
// is exactly who this feature is for, so handing them an English write-up would
// put the barrier back at the end.

test("callLanguageName maps what the app sends, and falls back to English", () => {
  assert.equal(callLanguageName("en"), "English");
  assert.equal(callLanguageName("es"), "Spanish");
  assert.equal(callLanguageName("zh-Hans"), "Simplified Chinese");
  for (const junk of ["", " ", "klingon", null, undefined, 7, {}]) {
    assert.equal(callLanguageName(junk), "English", `should fall back on ${JSON.stringify(junk)}`);
  }
});

test("the task asks for the write-up in the user's language, and never for the call", () => {
  const task = buildCallTask({
    name: "Mei", goal: "Ask about the late fee", mayAgreeTo: "", language: "Simplified Chinese",
  });
  assert.match(task, /write your summary and every field of the structured result in Simplified Chinese/i);
  // The call itself stays English no matter what the write-up language is.
  assert.match(task, /Speak ENGLISH for the entire call/);
  assert.match(task, /Speak only English on the call/);
});

test("an English user's task gains no extra language line", () => {
  const task = buildCallTask({ name: "Mei", goal: "Ask about the late fee", mayAgreeTo: "" });
  assert.ok(!/write your summary and every field/i.test(task));
});

test("the result schema carries the language, because that is what CALL-E extracts with", () => {
  const spanish = callResultSchema("Spanish");
  assert.match(spanish.properties.detail.description, /Write this in Spanish\.$/);
  assert.match(spanish.properties.agreed.description, /Write this in Spanish\.$/);
  assert.match(spanish.properties.next_step.description, /Write this in Spanish\.$/);
  // Enums are machine values and must NOT be translated, or the app can't read them.
  assert.deepEqual(spanish.properties.outcome.enum, ["done", "partially", "not_done", "unknown"]);
  assert.deepEqual(spanish.properties.needs_user_action.enum, ["yes", "no", "unknown"]);
  // The English schema is untouched, and shared, so no copy can drift.
  assert.equal(callResultSchema("English"), CALL_RESULT_SCHEMA);
  assert.ok(!/Write this in/.test(CALL_RESULT_SCHEMA.properties.detail.description));
});

test("a retry after a definite rejection gets a fresh key; a first try's key is unchanged", async () => {
  const intent = { userID: "u1", itemId: "i1", phone: "+12125550100", task: "Ask about the bill" };
  const at = new Date("2026-09-16T22:02:00Z");
  const first = await callIdempotencyKey(intent, at);
  assert.equal(first, await callIdempotencyKey({ ...intent, attempt: 0 }, at));
  const second = await callIdempotencyKey({ ...intent, attempt: 1 }, at);
  assert.notEqual(first, second);
  assert.notEqual(second, await callIdempotencyKey({ ...intent, attempt: 2 }, at));
});

test("clarifyingQuestions keeps what CALL-E asked, capped, and survives junk", () => {
  const body = { error: { code: "call_not_ready", details: { questions: [" Which language? ", "", 7, "x".repeat(400), "b", "c"] } } };
  const out = clarifyingQuestions(body);
  assert.equal(out[0], "Which language?");
  assert.equal(out[1].length, 300);
  assert.equal(out.length, 3);
  assert.deepEqual(clarifyingQuestions({ error: { code: "call_not_ready" } }), []);
  assert.deepEqual(clarifyingQuestions(null), []);
});

async function withFetch(status, body, run) {
  const original = globalThis.fetch;
  globalThis.fetch = async () => new Response(JSON.stringify(body), { status });
  const quiet = console.error;
  console.error = () => {};
  try { return await run(); } finally { globalThis.fetch = original; console.error = quiet; }
}

const LIVE_ENV = { CALLE_API_KEY: "test-key", CALLE_BASE_URL: "https://api.heycall-e.com" };
const CALL = { actionID: "a1", task: "t", phone: "+12125550100", idempotencyKey: "k", language: "English" };

test("a clarifying question is a definite rejection, refunded, with the question kept", async () => {
  const placed = await withFetch(422,
    { error: { code: "call_not_ready", details: { questions: ["Should the call be in Chinese?"] } } },
    () => createProviderCall(LIVE_ENV, CALL));
  assert.equal(placed.ok, false);
  assert.equal(placed.code, "call_not_ready");
  assert.equal(placed.rejected, true);
  assert.equal(placed.keepCharge, false);
  assert.deepEqual(placed.questions, ["Should the call be in Chinese?"]);
});

test("an idempotency conflict is never a definite rejection", async () => {
  const placed = await withFetch(409, { error: { code: "idempotency_conflict" } },
    () => createProviderCall(LIVE_ENV, CALL));
  assert.equal(placed.rejected, false);
});

test("a provider 5xx is never a definite rejection", async () => {
  const placed = await withFetch(503, { error: { code: "provider_unavailable" } },
    () => createProviderCall(LIVE_ENV, CALL));
  assert.equal(placed.rejected, false);
  assert.equal(placed.keepCharge, true);
});
