// Worker unit tests — `npm test` (Node's built-in runner, no dependencies).
//
// These cover the PURE logic, which is where the expensive bugs have actually
// lived: cursor paging that silently dropped rows, validation that let hostile
// ids through, and the request shaping that bounds what reaches OpenAI. Routing
// and D1 behaviour need `wrangler dev` / a real binding and are verified by the
// live probes recorded in testflight_build4_notes.md.

import test from "node:test";
import assert from "node:assert/strict";
import {
  parseCursor,
  formatCursor,
  validID,
  validStamp,
  sanitizeMessages,
  clamp,
  readJSON,
  MAX_BODY_BYTES,
  MAX_MESSAGES,
  MAX_MESSAGE_CHARS,
  sendEmail,
  normalizeEmail,
  validEmail,
  validDerivedKey,
  derivePasswordHash,
  timingSafeEqual,
} from "./worker.js";

const UUID_A = "11111111-1111-1111-1111-111111111111";
const UUID_B = "22222222-2222-2222-2222-222222222222";

// ── cursor ───────────────────────────────────────────────────────────────────

test("cursor round-trips both streams independently", () => {
  const packed = formatCursor(
    { at: "2026-08-08T00:00:00.000Z", id: UUID_A },
    { at: "2026-08-07T00:00:00.000Z", id: UUID_B });
  const parsed = parseCursor(packed);
  assert.deepEqual(parsed.task, { at: "2026-08-08T00:00:00.000Z", id: UUID_A });
  assert.deepEqual(parsed.profile, { at: "2026-08-07T00:00:00.000Z", id: UUID_B });
});

test("an empty cursor starts both streams from the beginning", () => {
  assert.deepEqual(parseCursor(""), {
    task: { at: "", id: "" },
    profile: { at: "", id: "" },
  });
});

// A client that synced before the composite cursor existed sends a bare
// timestamp. It must still work — reading it as "this stamp, no id" re-sends at
// most one already-applied page, which is harmless under last-writer-wins.
test("a legacy bare-timestamp cursor is still understood", () => {
  const parsed = parseCursor("2026-08-08T00:00:00.000Z");
  assert.equal(parsed.task.at, "2026-08-08T00:00:00.000Z");
  assert.equal(parsed.task.id, "");
  assert.equal(parsed.profile.at, "2026-08-08T00:00:00.000Z");
});

// The cursor is stored and re-sent by the client, and `since` is clamped on the
// way in. If that clamp were shorter than the cursor, it would be silently
// truncated and the whole account would re-download on every sync.
test("a packed cursor stays well under the 256-char clamp", () => {
  const packed = formatCursor({ at: "2026-08-08T00:00:00.000Z", id: UUID_A },
                              { at: "2026-08-08T00:00:00.000Z", id: UUID_B });
  assert.ok(packed.length < 256, `cursor was ${packed.length} chars`);
});

// ── id + timestamp validation ────────────────────────────────────────────────

test("validID accepts UUIDs and rejects everything else", () => {
  assert.equal(validID(UUID_A), UUID_A);
  assert.equal(validID("'; DROP TABLE tasks; --"), "");
  assert.equal(validID(""), "");
  assert.equal(validID(null), "");
  assert.equal(validID(42), "");
  assert.equal(validID(UUID_A + "extra"), "");
});

// A device with a badly skewed clock (or a hostile client sending year 9999)
// would otherwise write a row no honest later edit could ever beat under
// last-writer-wins — freezing that task forever. Clamping keeps the write and
// removes the poison.
test("validStamp clamps a future timestamp to now", () => {
  const now = "2026-08-08T12:00:00.000Z";
  assert.equal(validStamp("9999-01-01T00:00:00.000Z", now), now);
  assert.equal(validStamp("2026-08-08T11:00:00.000Z", now), "2026-08-08T11:00:00.000Z");
});

test("validStamp rejects unparseable values", () => {
  const now = "2026-08-08T12:00:00.000Z";
  assert.equal(validStamp("not-a-date", now), "");
  assert.equal(validStamp("", now), "");
  assert.equal(validStamp(null, now), "");
  assert.equal(validStamp("x".repeat(64), now), "");
});

// Small skew is normal across devices and must NOT be clamped, or every write
// from a slightly-fast phone would lose its ordering.
test("validStamp tolerates a few seconds of clock skew", () => {
  const now = new Date().toISOString();
  const slightlyAhead = new Date(Date.now() + 30_000).toISOString();
  assert.equal(validStamp(slightlyAhead, now), slightlyAhead);
});

// ── AI request shaping ───────────────────────────────────────────────────────

test("sanitizeMessages keeps a normal text conversation", () => {
  const out = sanitizeMessages([
    { role: "system", content: "You extract tasks." },
    { role: "user", content: "ELECTRIC BILL DUE 08/20 $42.17" },
  ]);
  assert.deepEqual(out, [
    { role: "system", content: "You extract tasks." },
    { role: "user", content: "ELECTRIC BILL DUE 08/20 $42.17" },
  ]);
});

// Tadah does OCR on the device and sends text; it has never sent an image. The
// multimodal array form opens a much more expensive class of request on an
// endpoint whose token ships inside the app, so it is refused outright.
test("sanitizeMessages refuses image / multimodal content", () => {
  assert.equal(sanitizeMessages([
    { role: "user", content: [{ type: "image_url", image_url: { url: "https://x/y.png" } }] },
  ]), null);
});

test("sanitizeMessages refuses unknown roles and malformed entries", () => {
  assert.equal(sanitizeMessages([{ role: "tool", content: "hi" }]), null);
  assert.equal(sanitizeMessages([{ content: "no role" }]), null);
  assert.equal(sanitizeMessages([null]), null);
  assert.equal(sanitizeMessages([]), null);
  assert.equal(sanitizeMessages("not an array"), null);
});

test("sanitizeMessages enforces the count and per-message size caps", () => {
  const many = Array.from({ length: MAX_MESSAGES + 1 },
                          () => ({ role: "user", content: "x" }));
  assert.equal(sanitizeMessages(many), null);
  assert.equal(sanitizeMessages([
    { role: "user", content: "x".repeat(MAX_MESSAGE_CHARS + 1) },
  ]), null);
});

// Anything the app doesn't send must not reach OpenAI. `n` in particular
// multiplies the bill per request.
test("sanitizeMessages drops extra per-message keys", () => {
  const out = sanitizeMessages([
    { role: "user", content: "hello", name: "x", tool_calls: [{}], n: 50 },
  ]);
  assert.deepEqual(out, [{ role: "user", content: "hello" }]);
});

// ── misc ─────────────────────────────────────────────────────────────────────

test("clamp coerces and truncates, never throws", () => {
  assert.equal(clamp("abc"), "abc");
  assert.equal(clamp(123), "");
  assert.equal(clamp(null), "");
  assert.equal(clamp("x".repeat(100)).length, 64);
  assert.equal(clamp("x".repeat(100), 10).length, 10);
});

// (The pemToBytes test went with the function on 2026-08-16 — its only caller was
// the Apple client-secret JWT, and there is no PEM key in this Worker any more.)

// ── bounded body reader ──────────────────────────────────────────────────────
// Every route reads through this. Before it existed each handler called
// request.json() immediately, so a multi-megabyte body was buffered before any
// validation ran — batch-count checks downstream can't prevent that.

const post = (body, headers = {}) =>
  new Request("https://x/", { method: "POST", body, headers });

test("readJSON accepts a normal object", async () => {
  const r = await readJSON(post(JSON.stringify({ a: 1 })));
  assert.equal(r.ok, true);
  assert.deepEqual(r.body, { a: 1 });
});

test("readJSON rejects a body over the limit with 413", async () => {
  const big = JSON.stringify({ x: "y".repeat(MAX_BODY_BYTES + 100) });
  const r = await readJSON(post(big));
  assert.equal(r.ok, false);
  assert.equal(r.response.status, 413);
});

// A chunked request can omit Content-Length entirely, or lie about it — so the
// bytes actually read have to be checked too, not just the header.
test("readJSON enforces the limit even when Content-Length lies", async () => {
  const big = JSON.stringify({ x: "y".repeat(MAX_BODY_BYTES + 100) });
  const r = await readJSON(post(big, { "Content-Length": "10" }));
  assert.equal(r.ok, false);
  assert.equal(r.response.status, 413);
});

test("readJSON rejects a declared oversize before reading the body", async () => {
  const r = await readJSON(post("{}", { "Content-Length": String(MAX_BODY_BYTES + 1) }));
  assert.equal(r.ok, false);
  assert.equal(r.response.status, 413);
});

test("readJSON rejects malformed JSON and non-objects with 400", async () => {
  for (const bad of ["not json", '"a string"', "42", "null"]) {
    const r = await readJSON(post(bad));
    assert.equal(r.ok, false, `expected rejection for ${bad}`);
    assert.equal(r.response.status, 400);
  }
});

test("readJSON honours a per-route limit", async () => {
  const r = await readJSON(post(JSON.stringify({ x: "y".repeat(500) })), 100);
  assert.equal(r.ok, false);
  assert.equal(r.response.status, 413);
});

// The Apple JWKS tests went with Sign in with Apple itself (2026-08-15): the
// route, token verification, key cache and grant revocation are all removed, so
// there is nothing left for them to protect. The throttle they pinned mattered
// only because `kid` was attacker-controlled on a route that no longer exists.


// ── transactional email (Resend) ─────────────────────────────────────────────

test("sendEmail posts to Resend with the key and the configured sender", async () => {
  const realFetch = globalThis.fetch;
  let seen = null;
  globalThis.fetch = async (url, init) => {
    seen = { url, init };
    return { ok: true, status: 200, json: async () => ({ id: "abc" }) };
  };
  try {
    await sendEmail(
      { RESEND_KEY: "re_test", EMAIL_FROM: "noreply@example.com" },
      { to: "user@example.com", subject: "Verify", html: "<p>hi</p>" });

    assert.equal(seen.url, "https://api.resend.com/emails");
    assert.equal(seen.init.method, "POST");
    assert.equal(seen.init.headers.Authorization, "Bearer re_test");
    const body = JSON.parse(seen.init.body);
    assert.equal(body.from, "noreply@example.com");
    assert.deepEqual(body.to, ["user@example.com"]);   // API wants an array
    assert.equal(body.subject, "Verify");
  } finally {
    globalThis.fetch = realFetch;
  }
});

// NO FALLBACK SENDER. Resend's shared onboarding@resend.dev only delivers to the
// account owner, so falling back to it would tell a real user "check your inbox"
// for a reset code that could never arrive — a silent dead end on the one route
// back into a locked-out account.
test("sendEmail refuses to send without a verified sender", async () => {
  await assert.rejects(
    () => sendEmail({ RESEND_KEY: "re_test" }, { to: "a@b.c", subject: "s", html: "h" }),
    /email_from_not_configured/);
});

// Fail LOUDLY rather than pretending a verification email went out — a silent
// no-op here would strand someone on "check your inbox" forever.
test("sendEmail throws when the key is missing or Resend rejects", async () => {
  await assert.rejects(
    () => sendEmail({}, { to: "a@b.c", subject: "s", html: "h" }),
    /email_not_configured/);

  const realFetch = globalThis.fetch;
  globalThis.fetch = async () => ({ ok: false, status: 422, json: async () => ({}) });
  try {
    await assert.rejects(
      () => sendEmail({ RESEND_KEY: "re_test", EMAIL_FROM: "x@y.z" },
                      { to: "a@b.c", subject: "s", html: "h" }),
      /email_send_failed_422/);
  } finally {
    globalThis.fetch = realFetch;
  }
});

// The thrown error travels into logs, so it must not carry the recipient, the
// body, or the API key. Observability is on for this Worker.
test("a failed send leaks neither the key nor the recipient", async () => {
  const realFetch = globalThis.fetch;
  globalThis.fetch = async () => ({ ok: false, status: 500, json: async () => ({}) });
  try {
    await sendEmail({ RESEND_KEY: "re_supersecret", EMAIL_FROM: "x@y.z" },
                    { to: "private@example.com", subject: "s", html: "reset-link" });
    assert.fail("expected a throw");
  } catch (e) {
    assert.ok(!e.message.includes("re_supersecret"), "API key leaked into the error");
    assert.ok(!e.message.includes("private@example.com"), "recipient leaked into the error");
    assert.ok(!e.message.includes("reset-link"), "body leaked into the error");
  } finally {
    globalThis.fetch = realFetch;
  }
});

// ── email + password helpers ────────────────────────────────────────────────

test("emails are normalised so one person is one account", () => {
  assert.equal(normalizeEmail("  Rachel@Example.COM "), "rachel@example.com");
  assert.equal(validEmail("Rachel@Example.com"), "rachel@example.com");
});

test("validEmail rejects what is obviously not an address", () => {
  for (const bad of ["", "  ", "nope", "a@b", "@example.com", "a b@example.com",
                     "a@example", "a@@example.com", "x".repeat(250) + "@e.com"]) {
    assert.equal(validEmail(bad), "", `should reject ${JSON.stringify(bad)}`);
  }
  for (const good of ["a@b.co", "first.last+tag@sub.example.com"]) {
    assert.ok(validEmail(good), `should accept ${good}`);
  }
});

// The client sends a PBKDF2 output, so anything else is either a bug or an
// attempt to feed the hash function something unbounded.
test("validDerivedKey demands exactly a 64-char hex digest", () => {
  assert.ok(validDerivedKey("a".repeat(64)));
  assert.equal(validDerivedKey("a".repeat(63)), "");
  assert.equal(validDerivedKey("a".repeat(65)), "");
  assert.equal(validDerivedKey("A".repeat(64)), "");        // upper-case hex
  assert.equal(validDerivedKey("g".repeat(64)), "");        // not hex
  assert.equal(validDerivedKey(""), "");
  assert.equal(validDerivedKey("x".repeat(100000)), "");
});

test("the same input always derives the same hash, a different salt does not", async () => {
  const env = { PASSWORD_PEPPER: "pepper" };
  const key = "b".repeat(64);
  const h1 = await derivePasswordHash(env, key, "salt-one");
  const h2 = await derivePasswordHash(env, key, "salt-one");
  const h3 = await derivePasswordHash(env, key, "salt-two");
  assert.equal(h1, h2);                    // deterministic, or nobody can log in
  assert.notEqual(h1, h3);                 // salted, so equal passwords differ
});

// The pepper is what makes a stolen `accounts` table useless on its own: without
// the Worker secret, an attacker can't even test guesses offline.
test("the pepper changes the hash, so a leaked table alone is not crackable", async () => {
  const key = "c".repeat(64);
  const withA = await derivePasswordHash({ PASSWORD_PEPPER: "A" }, key, "s");
  const withB = await derivePasswordHash({ PASSWORD_PEPPER: "B" }, key, "s");
  assert.notEqual(withA, withB);
});

test("timingSafeEqual matches only identical strings", () => {
  assert.ok(timingSafeEqual("abc", "abc"));
  assert.ok(!timingSafeEqual("abc", "abd"));
  assert.ok(!timingSafeEqual("abc", "ab"));      // length differs
  assert.ok(!timingSafeEqual("", "a"));
  assert.ok(timingSafeEqual("", ""));
});

// The pepper has no fallback: a deploy that forgets the secret must FAIL, not
// quietly hash everything with a public constant.
test("derivePasswordHash refuses to run without a pepper", async () => {
  await assert.rejects(() => derivePasswordHash({}, "a".repeat(64), "salt"),
                       /password_pepper_missing/);
  await assert.rejects(() => derivePasswordHash({ PASSWORD_PEPPER: "" }, "a".repeat(64), "salt"),
                       /password_pepper_missing/);
});
