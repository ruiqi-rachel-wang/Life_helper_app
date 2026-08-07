// Cuevi Worker — AI proxy + anonymous metrics ingest
//
// Two jobs, both POST-only and both gated by the optional X-Cuevi-Token secret:
//   • "/" or /v1/chat/completions  → proxy to OpenAI (keeps the key OFF the phone;
//     the app sends NO key, this Worker adds the secret OPENAI_API_KEY it holds).
//   • POST /events                 → store anonymous tester metrics in D1 (Part 1).
//
// Cost/abuse guardrails (the endpoint URL is discoverable, so these BOUND the
// damage rather than hide the URL) — layered, from outermost in:
//   • Per-IP rate limit (RATE_LIMITER binding below; no-op if the binding is
//     missing so a config slip can't take the app down).
//   • POST only; shared-secret header required IFF PROXY_TOKEN is set.
//   • AI: model allow-list + a hard max_tokens cap on every request.
//   • AI: per-install daily/monthly call caps in D1 (X-Cuevi-Install header).
//     Old app builds don't send the header and skip this check — the IP limit
//     still covers them; an abuser omitting the header is likewise IP-limited.
//   • /events: capped batch size, every stored string clamped, only known event
//     kinds accepted, INSERT OR IGNORE so re-sends never duplicate.
//   • The final $ ceiling is the OpenAI spending cap (dashboard) — keep it set.

const ALLOWED_MODELS = new Set(["gpt-4o", "gpt-4o-mini"]);
const MAX_TOKENS = 2000; // hard ceiling AND the default when the client sends none

// Per-install AI-call caps. Deliberately ~3x the app's own scan quota (10/day,
// 50/month) because guides also call the AI — honest users should never see
// these; they exist to bound a runaway device or a copied token+install id.
const AI_DAY_LIMIT = 30;
const AI_MONTH_LIMIT = 150;

// /events guardrails.
const MAX_BATCH = 500;                               // events accepted per request
const VALID_KINDS = new Set(["confirmed", "completed"]);
const MAX_STR = 64;                                  // clamp every stored string

// /sync + /auth guardrails (Part 3 account task sync).
const MAX_SYNC_BATCH = 500;     // changes + deletes accepted per push
const MAX_PULL = 1000;          // rows returned per pull
const MAX_PAYLOAD = 100_000;    // bytes of TaskDTO JSON stored per task (generous; images aren't synced)
const APPLE_ISS = "https://appleid.apple.com";
// MUST match PlusStore.entitlementID in the app AND the Entitlement identifier in
// the RevenueCat dashboard. If these drift, checkPlus() sees every user as free
// and Plus accounts get the free one-device limit. Override with a
// PLUS_ENTITLEMENT var if the dashboard id ever changes.
const PLUS_ENTITLEMENT = "Tadah Pro";

// One-time (per isolate) lazy DDL so the quota table exists without a manual
// migration step. Cheap: runs once per Worker instance, IF NOT EXISTS after.
let usageTableReady = false;
let syncTablesReady = false;              // lazy DDL for tasks/sessions (see ensureSyncTables)
let appleKeys = null, appleKeysAt = 0;    // cached Apple JWKS (per isolate)

export default {
  async fetch(request, env) {
    if (request.method !== "POST") return json({ error: "POST only" }, 405);

    // Outermost: per-IP rate limit (Workers rate-limiting binding). Applies to
    // every route, before any body parsing. Missing binding → skip, don't break.
    if (env.RATE_LIMITER) {
      const ip = request.headers.get("CF-Connecting-IP") || "unknown";
      const { success } = await env.RATE_LIMITER.limit({ key: ip });
      if (!success) return json({ error: "Too many requests" }, 429);
    }

    const path = new URL(request.url).pathname;

    // The shared secret gates EVERY route when configured (set it with
    // `wrangler secret put PROXY_TOKEN`, and put the same value in the app).
    if (env.PROXY_TOKEN && request.headers.get("X-Cuevi-Token") !== env.PROXY_TOKEN) {
      return json({ error: "Unauthorized" }, 401);
    }

    if (path === "/events") return handleEvents(request, env);
    if (path === "/auth/apple") return handleAppleAuth(request, env);
    if (path === "/sync") return handleSync(request, env);
    if (path === "/" || path === "/v1/chat/completions") return handleChat(request, env);
    return json({ error: "Not found" }, 404);
  },
};

// ── AI proxy ────────────────────────────────────────────────────────────────
async function handleChat(request, env) {
  let body;
  try { body = await request.json(); } catch { return json({ error: "Invalid JSON" }, 400); }

  if (!ALLOWED_MODELS.has(body.model)) return json({ error: "Model not allowed" }, 400);

  // Per-install quota (see header note at the top). Fail OPEN on storage
  // errors: a D1 hiccup shouldn't block every scan; the other layers hold.
  const installID = clamp(request.headers.get("X-Cuevi-Install") || "");
  if (installID && env.DB) {
    try {
      const { day, month } = await bumpUsage(env.DB, installID);
      if (day > AI_DAY_LIMIT || month > AI_MONTH_LIMIT) {
        return json({ error: "quota", message: "AI limit reached for this device" }, 429);
      }
    } catch { /* fail open */ }
  }

  // Cap tokens even if the client omitted max_tokens (the previously-broken cap).
  const requested = Number(body.max_tokens);
  body.max_tokens = Math.min(Number.isFinite(requested) ? requested : MAX_TOKENS, MAX_TOKENS);

  const upstream = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${env.OPENAI_API_KEY}`,
    },
    body: JSON.stringify(body),
  });

  return new Response(upstream.body, {
    status: upstream.status,
    headers: { "Content-Type": "application/json" },
  });
}

// Count this call against the install's day + month windows and return the new
// totals. Counts attempts (not successes) — the limits carry 3x headroom for that.
async function bumpUsage(db, installID) {
  if (!usageTableReady) {
    await db.exec(
      "CREATE TABLE IF NOT EXISTS ai_usage (install_id TEXT NOT NULL, period TEXT NOT NULL, count INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (install_id, period))"
    );
    usageTableReady = true;
  }
  const now = new Date().toISOString();       // "2026-07-08T…"
  const dayKey = now.slice(0, 10);            // 2026-07-08
  const monthKey = now.slice(0, 7);           // 2026-07
  const bump = db.prepare(
    `INSERT INTO ai_usage (install_id, period, count) VALUES (?, ?, 1)
     ON CONFLICT(install_id, period) DO UPDATE SET count = count + 1
     RETURNING count`
  );
  const [d, m] = await db.batch([bump.bind(installID, dayKey), bump.bind(installID, monthKey)]);
  return { day: d.results?.[0]?.count ?? 0, month: m.results?.[0]?.count ?? 0 };
}

// ── Anonymous metrics ingest ─────────────────────────────────────────────────
// Body shape (from Metrics.flush()):
//   { installID: "<uuid>", appVersion: "1.0 (3)",
//     events: [ { id, kind, date, itemID?, source?, onTime? }, … ] }
// Defensive by design: junk events are skipped (not fatal); INSERT OR IGNORE on
// the event_id primary key means a re-sent batch can't create duplicates.
async function handleEvents(request, env) {
  if (!env.DB) return json({ error: "Metrics storage not configured" }, 503);

  let body;
  try { body = await request.json(); } catch { return json({ error: "Invalid JSON" }, 400); }

  const installID = clamp(body.installID);
  const appVersion = clamp(body.appVersion);
  const events = Array.isArray(body.events) ? body.events : null;
  if (!installID || !events) return json({ error: "Bad payload" }, 400);
  if (events.length === 0) return json({ ok: true, accepted: 0 });
  if (events.length > MAX_BATCH) return json({ error: "Batch too large" }, 413);

  const stmt = env.DB.prepare(
    `INSERT OR IGNORE INTO events
       (event_id, install_id, kind, source, on_time, item_id, occurred_at, app_version)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
  );

  const rows = [];
  for (const e of events) {
    const id = clamp(e && e.id);
    const kind = clamp(e && e.kind);
    const occurredAt = clamp(e && e.date, 40);          // ISO-8601 string from the device
    if (!id || !VALID_KINDS.has(kind) || !occurredAt) continue;   // skip junk, keep the batch
    rows.push(stmt.bind(
      id,
      installID,
      kind,
      clamp(e.source) || null,
      onTimeToInt(e.onTime),
      clamp(e.itemID) || null,
      occurredAt,
      appVersion || null,
    ));
  }
  if (rows.length === 0) return json({ ok: true, accepted: 0 });

  try {
    await env.DB.batch(rows);
  } catch {
    return json({ error: "Store failed" }, 500);
  }
  return json({ ok: true, accepted: rows.length });
}

// ── Account task sync (Part 3) ───────────────────────────────────────────────
// Two routes:
//   POST /auth/apple  { idToken, deviceId } → verify the Sign-in-with-Apple JWT
//     (Apple's public keys), check the user's tier via RevenueCat, enforce the
//     free = 1-device rule, and issue a session token.
//   POST /sync        header X-Tadah-Session; { since, changes[], deletes[] } →
//     last-writer-wins upsert into `tasks`, then return everything changed since
//     the client's cursor. A revoked session ⇒ 401 (signed out on another device).
// The user_id is ALWAYS the verified Apple `sub` — never taken from the client.

// Create tasks/sessions if a migration hasn't been run (mirrors ai_usage's lazy
// DDL). Cheap: once per isolate, IF NOT EXISTS after.
async function ensureSyncTables(db) {
  if (syncTablesReady) return;
  await db.exec("CREATE TABLE IF NOT EXISTS tasks (user_id TEXT NOT NULL, item_id TEXT NOT NULL, payload TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT, PRIMARY KEY (user_id, item_id))");
  await db.exec("CREATE TABLE IF NOT EXISTS sessions (token TEXT PRIMARY KEY, user_id TEXT NOT NULL, device_id TEXT NOT NULL, created_at TEXT NOT NULL, last_seen TEXT NOT NULL, revoked INTEGER NOT NULL DEFAULT 0)");
  syncTablesReady = true;
}

async function handleAppleAuth(request, env) {
  if (!env.DB) return json({ error: "Sync not configured" }, 503);
  let body;
  try { body = await request.json(); } catch { return json({ error: "Invalid JSON" }, 400); }

  let userID;
  try { userID = await verifyAppleToken(body && body.idToken, env); }
  catch { return json({ error: "Invalid Apple token" }, 401); }

  await ensureSyncTables(env.DB);
  const deviceId = clamp(body.deviceId);
  const { known, plus } = await checkPlus(userID, env);
  const now = new Date().toISOString();

  // Device limit. Free (tier KNOWN and not Plus) → revoke the user's other live
  // sessions so only this device stays signed in. When the tier is UNKNOWN
  // (RevenueCat unreachable) we deliberately DON'T revoke — never wrongly sign
  // out a possible Plus user; the worst case is a brief extra device.
  if (known && !plus) {
    await env.DB.prepare("UPDATE sessions SET revoked = 1 WHERE user_id = ? AND revoked = 0")
      .bind(userID).run();
  }

  const token = newToken();
  await env.DB.prepare(
    "INSERT INTO sessions (token, user_id, device_id, created_at, last_seen, revoked) VALUES (?, ?, ?, ?, ?, 0)"
  ).bind(token, userID, deviceId, now, now).run();

  // Lets the client tell a NEW account (seed from local) from an EXISTING one
  // (pull + reconcile) — Phase 3.
  const has = await env.DB.prepare("SELECT 1 FROM tasks WHERE user_id = ? LIMIT 1").bind(userID).first();
  return json({ token, userID, plus, hasServerData: !!has }, 200);
}

async function handleSync(request, env) {
  if (!env.DB) return json({ error: "Sync not configured" }, 503);
  await ensureSyncTables(env.DB);

  const token = request.headers.get("X-Tadah-Session") || "";
  const session = await resolveSession(env.DB, token);
  if (!session) return json({ error: "Session invalid" }, 401);   // revoked/unknown → signed out
  const userID = session.user_id;

  let body;
  try { body = await request.json(); } catch { return json({ error: "Invalid JSON" }, 400); }
  const since = clamp(body.since, 40) || "";
  const changes = Array.isArray(body.changes) ? body.changes : [];
  const deletes = Array.isArray(body.deletes) ? body.deletes : [];
  if (changes.length + deletes.length > MAX_SYNC_BATCH) return json({ error: "Batch too large" }, 413);

  const now = new Date().toISOString();
  const stmts = [];

  // Upsert live changes, last-writer-wins on updated_at (a stale change no-ops).
  const upsert = env.DB.prepare(
    `INSERT INTO tasks (user_id, item_id, payload, updated_at, deleted_at) VALUES (?, ?, ?, ?, NULL)
     ON CONFLICT(user_id, item_id) DO UPDATE SET
       payload = excluded.payload, updated_at = excluded.updated_at, deleted_at = NULL
     WHERE excluded.updated_at > tasks.updated_at`
  );
  for (const c of changes) {
    const itemId = clamp(c && c.id, 64);
    const updatedAt = clamp(c && c.updatedAt, 40);
    if (!itemId || !updatedAt) continue;
    const payload = typeof (c && c.payload) === "string" ? c.payload : JSON.stringify((c && c.payload) ?? "");
    stmts.push(upsert.bind(userID, itemId, payload.slice(0, MAX_PAYLOAD), updatedAt));
  }

  // Soft-delete (tombstone), also LWW: a delete only wins if newer than the row.
  const tomb = env.DB.prepare(
    `INSERT INTO tasks (user_id, item_id, payload, updated_at, deleted_at) VALUES (?, ?, '', ?, ?)
     ON CONFLICT(user_id, item_id) DO UPDATE SET
       payload = '', updated_at = excluded.updated_at, deleted_at = excluded.deleted_at
     WHERE excluded.updated_at > tasks.updated_at`
  );
  for (const d of deletes) {
    const itemId = clamp(d && d.id, 64);
    const deletedAt = clamp(d && d.deletedAt, 40);
    if (!itemId || !deletedAt) continue;
    stmts.push(tomb.bind(userID, itemId, deletedAt, deletedAt));
  }

  if (stmts.length) {
    try { await env.DB.batch(stmts); } catch { return json({ error: "Store failed" }, 500); }
  }

  // Pull everything changed for this user since the client's cursor.
  const rows = (await env.DB.prepare(
    "SELECT item_id, payload, updated_at, deleted_at FROM tasks WHERE user_id = ? AND updated_at > ? ORDER BY updated_at ASC LIMIT ?"
  ).bind(userID, since, MAX_PULL).all()).results || [];

  const outChanges = [], outDeletes = [];
  let cursor = since;
  for (const r of rows) {
    if (r.updated_at > cursor) cursor = r.updated_at;
    if (r.deleted_at) outDeletes.push({ id: r.item_id, deletedAt: r.deleted_at });
    else outChanges.push({ id: r.item_id, payload: r.payload, updatedAt: r.updated_at });
  }

  await env.DB.prepare("UPDATE sessions SET last_seen = ? WHERE token = ?").bind(now, token).run();
  return json({ changes: outChanges, deletes: outDeletes, cursor }, 200);
}

// A live (non-revoked) session row, or null.
async function resolveSession(db, token) {
  if (!token) return null;
  const row = await db.prepare("SELECT user_id, revoked FROM sessions WHERE token = ?").bind(token).first();
  if (!row || row.revoked) return null;
  return row;
}

// Verify a Sign-in-with-Apple identity JWT against Apple's public keys and its
// standard claims. Returns the stable user id (`sub`). Throws on any failure.
async function verifyAppleToken(idToken, env) {
  const parts = String(idToken || "").split(".");
  if (parts.length !== 3) throw new Error("malformed token");
  const [h, p, s] = parts;
  const header = JSON.parse(b64urlToString(h));
  const payload = JSON.parse(b64urlToString(p));

  const jwk = (await getAppleKeys()).find((k) => k.kid === header.kid);
  if (!jwk) throw new Error("unknown signing key");
  const key = await crypto.subtle.importKey(
    "jwk", { kty: jwk.kty, n: jwk.n, e: jwk.e },
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
  const ok = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5", key, b64urlToBytes(s), new TextEncoder().encode(`${h}.${p}`));
  if (!ok) throw new Error("bad signature");

  if (payload.iss !== APPLE_ISS) throw new Error("bad issuer");
  // Bind the token to THIS app when the audience is configured (recommended:
  // set APPLE_AUDIENCE to the app's bundle id via `wrangler secret put`).
  if (env.APPLE_AUDIENCE && payload.aud !== env.APPLE_AUDIENCE) throw new Error("bad audience");
  if (!payload.exp || payload.exp * 1000 < Date.now()) throw new Error("expired");
  if (!payload.sub) throw new Error("no subject");
  return String(payload.sub);
}

// Apple's rotating public keys, cached ~6h per isolate.
async function getAppleKeys() {
  if (appleKeys && Date.now() - appleKeysAt < 6 * 3600 * 1000) return appleKeys;
  const res = await fetch(`${APPLE_ISS}/auth/keys`);
  if (!res.ok) throw new Error("jwks fetch failed");
  appleKeys = (await res.json()).keys || [];
  appleKeysAt = Date.now();
  return appleKeys;
}

// Authoritative tier check via the RevenueCat REST API (server-side, secret key).
// `known` = whether we could determine the tier at all; callers only ENFORCE the
// free device limit when the tier is known. Fails closed on `plus` (no false Plus)
// but the enforcement side fails open (no false sign-out).
async function checkPlus(userID, env) {
  if (!env.REVENUECAT_SECRET) return { known: false, plus: false };
  try {
    const res = await fetch(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userID)}`, {
      headers: { Authorization: `Bearer ${env.REVENUECAT_SECRET}` },
    });
    if (!res.ok) return { known: false, plus: false };
    const data = await res.json();
    const id = env.PLUS_ENTITLEMENT || PLUS_ENTITLEMENT;
    const ents = data && data.subscriber && data.subscriber.entitlements;
    const ent = ents && ents[id];   // bracket form: the id contains a space
    const active = !!ent && (!ent.expires_date || new Date(ent.expires_date).getTime() > Date.now());
    return { known: true, plus: active };
  } catch {
    return { known: false, plus: false };
  }
}

// A fresh opaque session token (256 bits of randomness, hex).
function newToken() {
  const b = new Uint8Array(32);
  crypto.getRandomValues(b);
  return Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");
}

// base64url → bytes / string (for decoding JWT segments).
function b64urlToBytes(s) {
  s = String(s).replace(/-/g, "+").replace(/_/g, "/");
  const pad = s.length % 4;
  if (pad) s += "=".repeat(4 - pad);
  const bin = atob(s);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}
function b64urlToString(s) { return new TextDecoder().decode(b64urlToBytes(s)); }

function onTimeToInt(v) { return v === true ? 1 : v === false ? 0 : null; }

// Coerce to a trimmed, length-capped string; non-strings → "".
function clamp(v, max = MAX_STR) {
  return typeof v === "string" ? v.slice(0, max) : "";
}

function json(obj, status) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
