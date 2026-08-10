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
  pemToBytes,
  MAX_MESSAGES,
  MAX_MESSAGE_CHARS,
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

// `wrangler secret put` commonly yields a key with literal "\n" sequences rather
// than real newlines; both must import, or account deletion fails at the Apple
// revocation step.
test("pemToBytes handles real and escaped newlines identically", () => {
  const body = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE";
  const real = `-----BEGIN PRIVATE KEY-----\n${body}\n-----END PRIVATE KEY-----`;
  const escaped = `-----BEGIN PRIVATE KEY-----\\n${body}\\n-----END PRIVATE KEY-----`;
  assert.deepEqual(pemToBytes(real), pemToBytes(escaped));
  assert.ok(pemToBytes(real).length > 0);
});
