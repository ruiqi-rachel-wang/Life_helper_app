// Cuevi Worker — AI proxy + anonymous metrics ingest
//
// Routes, all POST-only and all gated by the optional X-Cuevi-Token secret:
//   • "/" or /v1/chat/completions  → proxy to OpenAI (keeps the key OFF the phone;
//     the app sends NO key, this Worker adds the secret OPENAI_API_KEY it holds).
//   • POST /events                 → store anonymous tester metrics in D1 (Part 1).
//   • POST /auth/apple             → verify Sign in with Apple, issue a session.
//   • POST /auth/logout            → revoke THIS device's session.
//   • POST /account/delete         → erase the account's server data entirely.
//   • POST /sync                   → last-writer-wins task/profile sync (Part 3).
//
// Cost/abuse guardrails (the endpoint URL is discoverable, and X-Cuevi-Token ships
// inside the app so it must be assumed PUBLIC — these BOUND the damage rather than
// hide the URL) — layered, from outermost in:
//   • Rate limit keyed on session token → install id → IP (RATE_LIMITER binding;
//     no-op if the binding is missing so a config slip can't take the app down).
//     IP is the last resort only: whole schools and carrier NATs share one.
//   • POST only; shared-secret header required IFF PROXY_TOKEN is set.
//   • AI: model allow-list + a hard max_tokens cap on every request.
//   • AI: per-install daily/monthly call caps in D1, and the counter fails CLOSED.
//     A request with no X-Cuevi-Install header is metered by IP instead of being
//     waved through — when a missing header skipped the check and storage errors
//     failed open, omitting or rotating the header disabled the cap entirely.
//   • /events: capped batch size, every stored string clamped, only known event
//     kinds accepted, INSERT OR IGNORE so re-sends never duplicate.
//   • /auth: APPLE_AUDIENCE is mandatory, nonces are single-use, sessions expire.
//   • The final $ ceiling is the OpenAI spending cap (dashboard) — keep it set.

// gpt-4o stays listed even though the app moved to gpt-5-mini: builds already on
// testers' phones still ask for it, and dropping it would 400 every scan they make.
// Remove it only once those builds are gone.
const ALLOWED_MODELS = new Set(["gpt-5-mini", "gpt-4o", "gpt-4o-mini"]);
// Hard ceiling AND the default when the client sends none. 4000 (not 2000)
// because reasoning models spend part of this budget on hidden reasoning tokens
// before writing any JSON — too low a ceiling truncates the answer.
const MAX_TOKENS = 4000;

// INPUT bounds for the AI proxy. MAX_TOKENS only ever capped the response; the
// prompt side was unbounded, and prompt tokens are most of the bill on a document
// scan. A full page of OCR is a few KB, so 128 KB is generous for honest use.
const MAX_CHAT_BYTES = 128 * 1024;
const MAX_MESSAGES = 12;
const MAX_MESSAGE_CHARS = 40_000;      // per message
const ALLOWED_ROLES = new Set(["system", "user", "assistant"]);

// Per-install AI-call caps — a COST backstop, not entitlement enforcement.
// Entitlement is the app's job (ScanQuota.swift + PlusStore); this only bounds a
// device that bypasses it (ScanQuota lives in UserDefaults, so a reinstall resets
// it) or a copied token+install id.
//
// MUST be sized off the PLUS tier, not the free one: this endpoint is anonymous
// (install id only, no session), so it CANNOT tell a Plus user from a free one —
// every request has to be allowed the highest legitimate usage. Sizing these off
// the free tier is what made a paying user's 31st scan of the day fail with
// "AI service is busy", which is both wrong and unactionable.
//
// Keep them in sync with ScanQuota.swift — that drift is exactly the bug above:
//   Free: 10/day, 20 per rolling 30 days.  Plus: 60/day, 300 per rolling 30 days.
const PLUS_PER_DAY = 60;    // ScanQuota.perDayPlus
const PLUS_PER_30D = 300;   // ScanQuota.perWindowPlus
// 3x headroom on top, because the two sides don't count the same events: the app
// records a scan only when it SUCCEEDS (see CreateView), while bumpUsage counts
// every ATTEMPT — so retries over flaky network legitimately burn Worker budget
// the app never charged the user for.
const AI_DAY_LIMIT = PLUS_PER_DAY * 3;      // 180
const AI_MONTH_LIMIT = PLUS_PER_30D * 3;    // 900

// /events guardrails.
const MAX_BATCH = 500;                               // events accepted per request
const VALID_KINDS = new Set(["confirmed", "completed"]);
const MAX_STR = 64;                                  // clamp every stored string

// /sync + /auth guardrails (Part 3 account task sync).
const MAX_SYNC_BATCH = 500;     // changes + deletes accepted per push
const MAX_PULL = 1000;          // rows returned per pull
// Bytes of TaskDTO JSON stored per task (generous; images aren't synced). An
// oversized payload is REJECTED, never truncated — slicing a JSON string mid-value
// produces a record the client can't decode, and an undecodable record that the
// server keeps handing back is data the user silently loses.
const MAX_PAYLOAD = 100_000;
// Sessions expire, so a copied token can't be used forever. Refreshed on every
// /sync (last_seen), so an active device never gets logged out mid-use.
const SESSION_TTL_DAYS = 90;
// How long a tombstone / revoked session / usage row is kept before cleanup.
// Tombstones must outlive any plausible offline period, or a device that was away
// longer than this would resurrect deleted tasks.
const TOMBSTONE_TTL_DAYS = 180;
const REVOKED_SESSION_TTL_DAYS = 30;
const USAGE_TTL_DAYS = 60;
// Plus caps (decided 2026-08-05), enforced here because the client can lie. The
// two are DECOUPLED — any profile can be open on any device; the account simply
// can't exceed 8 of either. Free is 1 profile / 1 device (see handleAppleAuth).
const MAX_PROFILES = 8;
const MAX_DEVICES = 8;
// Free tier: one profile (you), one device. Must match ProfileStore.freeMax.
const FREE_PROFILES = 1;
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

    // Outermost: rate limit (Workers rate-limiting binding). Applies to every
    // route, before any body parsing. Missing binding → skip, don't break.
    //
    // Keyed on the most STABLE identifier the caller offers — session token, else
    // install id, else IP. Keying on IP alone punishes everyone behind one carrier
    // NAT or school/office network for the noisiest person on it, which for an
    // immigrant/ESL audience is a very likely deployment.
    if (env.RATE_LIMITER) {
      const key =
        request.headers.get("X-Tadah-Session") ||
        request.headers.get("X-Cuevi-Install") ||
        request.headers.get("CF-Connecting-IP") ||
        "unknown";
      const { success } = await env.RATE_LIMITER.limit({ key });
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
    if (path === "/auth/logout") return handleLogout(request, env);
    if (path === "/account/delete") return handleAccountDelete(request, env);
    if (path === "/sync") return handleSync(request, env);
    if (path === "/" || path === "/v1/chat/completions") return handleChat(request, env);
    return json({ error: "Not found" }, 404);
  },
};

// ── AI proxy ────────────────────────────────────────────────────────────────
async function handleChat(request, env) {
  // Bound the REQUEST before reading it. The token cap only limited what OpenAI
  // writes back; the input side was unbounded, so a caller could push megabytes of
  // prompt (which is what actually costs money) through a single allowed call.
  const declared = Number(request.headers.get("Content-Length") || 0);
  if (Number.isFinite(declared) && declared > MAX_CHAT_BYTES) {
    return json({ error: "Request too large" }, 413);
  }
  const raw = await request.text();
  if (raw.length > MAX_CHAT_BYTES) return json({ error: "Request too large" }, 413);

  let body;
  try { body = JSON.parse(raw); } catch { return json({ error: "Invalid JSON" }, 400); }
  if (!body || typeof body !== "object") return json({ error: "Invalid JSON" }, 400);

  if (!ALLOWED_MODELS.has(body.model)) return json({ error: "Model not allowed" }, 400);

  // Rebuild the request from a strict allow-list instead of forwarding whatever
  // arrived. Passing the caller's object through meant any OpenAI parameter was
  // reachable — `n: 50` (fifty completions), `stream`, tool definitions, an
  // arbitrary `model` field on a nested object, future billable features — none of
  // which the app ever sends. Only what Tadah actually uses gets through.
  const messages = sanitizeMessages(body.messages);
  if (!messages) return json({ error: "Invalid messages" }, 400);

  const safeBody = { model: body.model, messages };
  // The app relies on JSON mode for extraction; allow only that exact shape.
  if (body.response_format && body.response_format.type === "json_object") {
    safeBody.response_format = { type: "json_object" };
  }
  if (Number.isFinite(Number(body.temperature))) {
    safeBody.temperature = Math.min(Math.max(Number(body.temperature), 0), 2);
  }

  // Per-install quota (see header note at the top).
  //
  // A missing install header no longer SKIPS the quota — that made the whole cap
  // opt-in, since the proxy token ships inside the app and must be assumed public:
  // omitting the header (or rotating it per request) spent the OpenAI budget
  // freely. Instead we fall back to metering by IP.
  //
  // Why fall back rather than reject: build 2 is what testers are running right
  // now and it predates the header, so a hard 400 would break scanning for every
  // current tester. The fallback keeps them working while still counting them.
  const installID = clamp(request.headers.get("X-Cuevi-Install") || "");
  const quotaKey = installID.length >= 8
    ? installID
    : `ip:${clamp(request.headers.get("CF-Connecting-IP") || "unknown")}`;
  // Fail CLOSED, including when D1 isn't bound at all. Skipping the quota because
  // storage is missing means a misconfigured deploy silently has NO spend cap —
  // the one situation where you most want one.
  if (!env.DB) {
    return json({ error: "quota", message: "AI service is briefly unavailable. Please try again." }, 503);
  }
  let usage;
  try {
    usage = await bumpUsage(env.DB, quotaKey);
  } catch {
    return json({ error: "quota", message: "AI service is briefly unavailable. Please try again." }, 503);
  }
  if (usage.day > AI_DAY_LIMIT || usage.month > AI_MONTH_LIMIT) {
    return json({ error: "quota", message: "AI limit reached for this device" }, 429);
  }

  // Cap tokens even if the client omitted the field (the previously-broken cap).
  // Cap whichever field this client used — reasoning models (gpt-5) take
  // max_completion_tokens, the 4o family takes max_tokens — so old builds and new
  // ones are both bounded. Never write the field the client DIDN'T send: OpenAI
  // rejects max_tokens on a reasoning model.
  const field = body.max_completion_tokens !== undefined ? "max_completion_tokens" : "max_tokens";
  const requested = Number(body[field]);
  safeBody[field] = Math.min(Number.isFinite(requested) ? requested : MAX_TOKENS, MAX_TOKENS);

  const upstream = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${env.OPENAI_API_KEY}`,
    },
    body: JSON.stringify(safeBody),   // the allow-listed copy, never the caller's object
  });

  return new Response(upstream.body, {
    status: upstream.status,
    headers: { "Content-Type": "application/json" },
  });
}

// Validate the chat messages, returning a clean copy or null if unusable.
//
// TEXT ONLY, on purpose. Tadah does OCR on the device and sends the recognized
// text — it has never sent an image to the model. Accepting the multimodal array
// form (`content: [{type:"image_url", …}]`) would open a far more expensive class
// of request on an endpoint whose token is effectively public, so a non-string
// content is rejected rather than passed along.
function sanitizeMessages(messages) {
  if (!Array.isArray(messages) || messages.length === 0) return null;
  if (messages.length > MAX_MESSAGES) return null;

  const out = [];
  for (const m of messages) {
    if (!m || typeof m !== "object") return null;
    if (!ALLOWED_ROLES.has(m.role)) return null;
    if (typeof m.content !== "string") return null;      // no images, no tool parts
    if (m.content.length > MAX_MESSAGE_CHARS) return null;
    out.push({ role: m.role, content: m.content });
  }
  return out;
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
  // NOTE the two deliberate mismatches with ScanQuota, both fine because these
  // caps only need to sit safely ABOVE legitimate use, never exactly on it:
  //   • CALENDAR month here vs the app's ROLLING 30 days (so this window resets
  //     on the 1st, and AI_MONTH_LIMIT is derived from a rolling-30d number).
  //   • UTC day here vs the app's LOCAL day, so the two roll over at different
  //     moments for anyone not on UTC.
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
  await db.exec("CREATE TABLE IF NOT EXISTS profiles (user_id TEXT NOT NULL, profile_id TEXT NOT NULL, payload TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT, PRIMARY KEY (user_id, profile_id))");
  // Single-use Sign-in-with-Apple nonces. Without this an intercepted identity
  // token could be replayed until it expired to mint extra sessions.
  await db.exec("CREATE TABLE IF NOT EXISTS used_nonces (nonce TEXT PRIMARY KEY, used_at TEXT NOT NULL)");
  // Added after the sessions table shipped, so it's an ALTER rather than part of
  // the CREATE above. Harmless duplicate-column error on an already-migrated DB.
  try { await db.exec("ALTER TABLE sessions ADD COLUMN plus_checked_at TEXT"); } catch { /* already there */ }
  syncTablesReady = true;
}

async function handleAppleAuth(request, env) {
  if (!env.DB) return json({ error: "Sync not configured" }, 503);
  // Refuse to run unconfigured. Without APPLE_AUDIENCE any valid Sign-in-with-Apple
  // token from ANY app would authenticate here, so treating it as optional made
  // the check decorative. Fail loudly instead of silently accepting everyone.
  if (!env.APPLE_AUDIENCE) return json({ error: "Auth not configured" }, 503);

  let body;
  try { body = await request.json(); } catch { return json({ error: "Invalid JSON" }, 400); }

  await ensureSyncTables(env.DB);

  let claims;
  try { claims = await verifyAppleToken(body && body.idToken, env); }
  catch { return json({ error: "Invalid Apple token" }, 401); }
  const userID = claims.sub;

  // Replay protection: the client hashes a random nonce into the authorization
  // request, so the token carries sha256(rawNonce). We re-derive it from the raw
  // value the client sends and then BURN it, so the same token can't be presented
  // twice even inside its validity window.
  const rawNonce = clamp(body && body.nonce, 128);
  if (!rawNonce) return json({ error: "Nonce required" }, 401);
  if (claims.nonce !== (await sha256Hex(rawNonce))) return json({ error: "Nonce mismatch" }, 401);
  const fresh = await env.DB.prepare(
    "INSERT INTO used_nonces (nonce, used_at) VALUES (?, ?) ON CONFLICT(nonce) DO NOTHING RETURNING nonce"
  ).bind(claims.nonce, new Date().toISOString()).first();
  if (!fresh) return json({ error: "Nonce already used" }, 401);

  const deviceId = clamp(body.deviceId);
  if (!deviceId) return json({ error: "Device id required" }, 400);
  const { known, plus } = await checkPlus(userID, env);
  const now = new Date().toISOString();
  const token = newToken();

  // Revoke + create in ONE batch (D1 runs a batch as a transaction), so two
  // simultaneous sign-ins can't interleave and leave a free account with two live
  // sessions — which was how the one-device rule could be defeated by racing it.
  const revokeAll = env.DB.prepare(
    "UPDATE sessions SET revoked = 1 WHERE user_id = ? AND revoked = 0");
  const revokeDevice = env.DB.prepare(
    "UPDATE sessions SET revoked = 1 WHERE user_id = ? AND device_id = ? AND revoked = 0");
  const insert = env.DB.prepare(
    "INSERT INTO sessions (token, user_id, device_id, created_at, last_seen, revoked, plus_checked_at) VALUES (?, ?, ?, ?, ?, 0, ?)"
  ).bind(token, userID, deviceId, now, now, known ? now : null);

  // Free (tier KNOWN and not Plus) → revoke the user's other live sessions so only
  // this device stays signed in. When the tier is UNKNOWN (RevenueCat unreachable)
  // we deliberately DON'T revoke — never wrongly sign out a possible Plus user;
  // the worst case is a brief extra device.
  if (known && !plus) {
    await env.DB.batch([revokeAll.bind(userID), insert]);
  } else {
    // Plus (or unknown tier): several devices are fine, but not unlimited — each
    // one is sync traffic and another copy of the family's data. Re-signing in on
    // a device we already know just replaces its session and never counts twice.
    await env.DB.batch([revokeDevice.bind(userID, deviceId), insert]);
    // Counted AFTER inserting, then undone if we went over. Checking first and
    // inserting second is the race that let concurrent sign-ins both pass.
    const live = await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM sessions WHERE user_id = ? AND revoked = 0"
    ).bind(userID).first();
    if ((live?.n ?? 0) > MAX_DEVICES) {
      await env.DB.prepare("UPDATE sessions SET revoked = 1 WHERE token = ?").bind(token).run();
      return json({ error: "device_limit",
                    message: `This account is already signed in on ${MAX_DEVICES} devices. Sign out on one of them first.` }, 409);
    }
  }

  // Opportunistic retention cleanup — cheap, and keeps tombstones / dead sessions
  // / usage rows from growing without bound.
  await sweepRetention(env.DB);

  // Lets the client tell a NEW account (seed from local) from an EXISTING one
  // (pull + reconcile) — Phase 3.
  const has = await env.DB.prepare(
    "SELECT 1 FROM tasks WHERE user_id = ? AND deleted_at IS NULL LIMIT 1").bind(userID).first();
  return json({ token, userID, plus, hasServerData: !!has }, 200);
}

// Sign out THIS device: revoke the session server-side so its token stops working
// immediately. Without this a token stayed valid forever after sign-out, and the
// privacy policy's "signing out ends the session" claim was simply untrue.
async function handleLogout(request, env) {
  if (!env.DB) return json({ error: "Sync not configured" }, 503);
  await ensureSyncTables(env.DB);
  const token = request.headers.get("X-Tadah-Session") || "";
  if (!token) return json({ error: "Session invalid" }, 401);
  await env.DB.prepare("UPDATE sessions SET revoked = 1 WHERE token = ?").bind(token).run();
  return json({ ok: true }, 200);
}

// Delete the ENTIRE account. Apple requires an in-app path that deletes the
// account and its data — and, for apps using Sign in with Apple, that the token
// grant is REVOKED too (Apple TN3194). Deleting only our own rows leaves Tadah
// listed under Settings ▸ Apple ID ▸ Sign in with Apple, which is not deletion.
//
// Order matters: revoke the third-party state FIRST, while we still have the ids
// to do it with, and only drop our rows once that has succeeded. Deleting our
// rows first would leave no way to retry the revocation.
//
// Rows are removed outright rather than tombstoned — there is no other device left
// to propagate a deletion to once all sessions are revoked, and keeping tombstones
// would mean keeping the user's item ids after they asked us to forget them.
async function handleAccountDelete(request, env) {
  if (!env.DB) return json({ error: "Sync not configured" }, 503);
  await ensureSyncTables(env.DB);
  const token = request.headers.get("X-Tadah-Session") || "";
  const session = await resolveSession(env.DB, token);
  if (!session) return json({ error: "Session invalid" }, 401);
  const userID = session.user_id;

  let body = {};
  try { body = await request.json(); } catch { /* body is optional-ish; checked below */ }
  const authorizationCode = clamp(body && body.authorizationCode, 512);

  // 1) Revoke the Sign in with Apple grant.
  if (!appleRevocationConfigured(env)) {
    // Refuse rather than half-delete. A 501 tells the app to say "we couldn't
    // delete your account" instead of falsely confirming — the same rule the
    // client applies to every other failure here.
    return json({ error: "not_configured",
                  message: "Account deletion is temporarily unavailable. Please contact support." }, 501);
  }
  if (!authorizationCode) return json({ error: "authorization_required" }, 400);
  try {
    await revokeAppleGrant(authorizationCode, env);
  } catch {
    return json({ error: "revoke_failed",
                  message: "We couldn't fully disconnect your Apple ID. Nothing was deleted; please try again." }, 502);
  }

  // 2) Delete the RevenueCat subscriber, so no purchase history stays keyed to
  //    this user id. Purchases.logOut() only changes the SDK's local identity —
  //    it deletes nothing. Best-effort: a subscriber that never existed 404s, and
  //    that must not block the deletion the user asked for.
  await deleteRevenueCatSubscriber(userID, env);

  // 3) Now our own rows.
  await env.DB.batch([
    env.DB.prepare("DELETE FROM tasks WHERE user_id = ?").bind(userID),
    env.DB.prepare("DELETE FROM profiles WHERE user_id = ?").bind(userID),
    env.DB.prepare("DELETE FROM sessions WHERE user_id = ?").bind(userID),
  ]);
  return json({ ok: true }, 200);
}

// Apple token revocation needs a client secret: an ES256 JWT signed with the
// private key from the Apple Developer portal. All four must be set:
//   APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY (the .p8 contents), APPLE_AUDIENCE.
function appleRevocationConfigured(env) {
  return !!(env.APPLE_TEAM_ID && env.APPLE_KEY_ID && env.APPLE_PRIVATE_KEY && env.APPLE_AUDIENCE);
}

// Exchange the authorization code for a refresh token, then revoke it. Apple
// wants the token revoked, not just the local session dropped.
async function revokeAppleGrant(authorizationCode, env) {
  const secret = await appleClientSecret(env);

  const tokenRes = await fetch("https://appleid.apple.com/auth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: env.APPLE_AUDIENCE,
      client_secret: secret,
      code: authorizationCode,
      grant_type: "authorization_code",
    }),
  });
  if (!tokenRes.ok) throw new Error("apple token exchange failed");
  const tokens = await tokenRes.json();
  // Prefer the refresh token: revoking it invalidates the whole grant.
  const token = tokens.refresh_token || tokens.access_token;
  const hint = tokens.refresh_token ? "refresh_token" : "access_token";
  if (!token) throw new Error("no token to revoke");

  const revokeRes = await fetch("https://appleid.apple.com/auth/revoke", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: env.APPLE_AUDIENCE,
      client_secret: secret,
      token,
      token_type_hint: hint,
    }),
  });
  if (!revokeRes.ok) throw new Error("apple revoke failed");
}

// ES256 JWT signed with the Apple .p8 key — Apple's "client secret".
async function appleClientSecret(env) {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", kid: env.APPLE_KEY_ID, typ: "JWT" };
  const payload = {
    iss: env.APPLE_TEAM_ID,
    iat: now,
    exp: now + 300,                 // short-lived; minted per request
    aud: APPLE_ISS,
    sub: env.APPLE_AUDIENCE,
  };
  const signingInput =
    `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;

  const key = await crypto.subtle.importKey(
    "pkcs8", pemToBytes(env.APPLE_PRIVATE_KEY),
    { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(signingInput));
  return `${signingInput}.${b64urlFromBytes(new Uint8Array(sig))}`;
}

// RevenueCat keeps a subscriber record keyed by the app user id (our Apple sub).
// Deleting the account must delete that too, or purchase history outlives it.
async function deleteRevenueCatSubscriber(userID, env) {
  if (!env.REVENUECAT_SECRET) return;
  try {
    await fetch(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userID)}`, {
      method: "DELETE",
      headers: { Authorization: `Bearer ${env.REVENUECAT_SECRET}` },
    });
  } catch { /* best-effort; never block the user's deletion on it */ }
}

// Bounded retention for rows nothing reads anymore. Runs opportunistically off
// sign-in (a low-frequency route), so it never adds latency to /sync.
async function sweepRetention(db) {
  const cutoff = (days) => new Date(Date.now() - days * 86400_000).toISOString();
  try {
    await db.batch([
      db.prepare("DELETE FROM tasks WHERE deleted_at IS NOT NULL AND deleted_at < ?")
        .bind(cutoff(TOMBSTONE_TTL_DAYS)),
      db.prepare("DELETE FROM profiles WHERE deleted_at IS NOT NULL AND deleted_at < ?")
        .bind(cutoff(TOMBSTONE_TTL_DAYS)),
      db.prepare("DELETE FROM sessions WHERE revoked = 1 AND last_seen < ?")
        .bind(cutoff(REVOKED_SESSION_TTL_DAYS)),
      db.prepare("DELETE FROM used_nonces WHERE used_at < ?").bind(cutoff(1)),
      db.prepare("DELETE FROM ai_usage WHERE period < ?").bind(cutoff(USAGE_TTL_DAYS).slice(0, 10)),
    ]);
  } catch { /* cleanup is best-effort; never fail a sign-in over it */ }
}

async function handleSync(request, env) {
  if (!env.DB) return json({ error: "Sync not configured" }, 503);
  await ensureSyncTables(env.DB);

  const token = request.headers.get("X-Tadah-Session") || "";
  const session = await resolveSession(env.DB, token);
  if (!session) return json({ error: "Session invalid" }, 401);   // revoked/unknown → signed out
  const userID = session.user_id;

  // A Plus subscription that lapsed used to keep its extra devices forever,
  // because the tier was only ever consulted at sign-in. Re-check at most once a
  // day per session and drop back to one device when the entitlement is gone.
  const downgraded = await enforceTierOnSync(env, session, token);
  if (downgraded) return json({ error: "Session invalid" }, 401);

  let body;
  try { body = await request.json(); } catch { return json({ error: "Invalid JSON" }, 400); }
  // Roomy: a composite cursor is ~130 chars ("t:<stamp>~<uuid>|p:<stamp>~<uuid>").
  // Clamping this below the cursor's own length would silently corrupt it and
  // re-send the whole account on every sync.
  const since = clamp(body.since, 256) || "";
  const changes = Array.isArray(body.changes) ? body.changes : [];
  const deletes = Array.isArray(body.deletes) ? body.deletes : [];
  // Count PROFILES in the batch limit too. They used to be parsed further down,
  // after this check, so a request could carry any number of profile records and
  // bypass the cap entirely — the limit only bounded half the payload.
  const profiles = Array.isArray(body.profiles) ? body.profiles : [];
  const profileDeletes = Array.isArray(body.profileDeletes) ? body.profileDeletes : [];
  const batchSize = changes.length + deletes.length + profiles.length + profileDeletes.length;
  if (batchSize > MAX_SYNC_BATCH) return json({ error: "Batch too large" }, 413);

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
    const itemId = validID(c && c.id);
    const updatedAt = validStamp(c && c.updatedAt, now);
    if (!itemId || !updatedAt) return json({ error: "Bad change record" }, 400);
    const payload = typeof (c && c.payload) === "string" ? c.payload : JSON.stringify((c && c.payload) ?? "");
    // REJECT oversized, never truncate: `payload.slice()` used to cut the JSON
    // mid-value, and the stored record then failed to decode on every device that
    // pulled it — silently losing that task forever.
    if (payload.length > MAX_PAYLOAD) return json({ error: "Payload too large", itemId }, 413);
    stmts.push(upsert.bind(userID, itemId, payload, updatedAt));
  }

  // Soft-delete (tombstone), also LWW: a delete only wins if newer than the row.
  const tomb = env.DB.prepare(
    `INSERT INTO tasks (user_id, item_id, payload, updated_at, deleted_at) VALUES (?, ?, '', ?, ?)
     ON CONFLICT(user_id, item_id) DO UPDATE SET
       payload = '', updated_at = excluded.updated_at, deleted_at = excluded.deleted_at
     WHERE excluded.updated_at > tasks.updated_at`
  );
  for (const d of deletes) {
    const itemId = validID(d && d.id);
    const deletedAt = validStamp(d && d.deletedAt, now);
    if (!itemId || !deletedAt) return json({ error: "Bad delete record" }, 400);
    stmts.push(tomb.bind(userID, itemId, deletedAt, deletedAt));
  }

  // ── family profiles, same LWW contract as tasks ──────────────────────────
  // (`profiles` / `profileDeletes` were read above, so they count toward the
  // batch limit.)

  // Server-side cap: a client can lie, and profiles are what Plus is SOLD on.
  // Only counts NEW ids — edits to existing profiles are always allowed through,
  // so hitting the cap can never freeze someone out of renaming what they have.
  if (profiles.length) {
    const live = (await env.DB.prepare(
      "SELECT profile_id FROM profiles WHERE user_id = ? AND deleted_at IS NULL"
    ).bind(userID).all()).results || [];
    const known = new Set(live.map((r) => r.profile_id));
    // validID (not clamp) so this counts exactly the ids the upsert below will
    // accept — otherwise a junk id inflates the count and trips the cap error
    // instead of the clearer "Bad profile record" 400.
    const incomingNew = profiles
      .map((p) => validID(p && p.id))
      .filter((id) => id && !known.has(id));
    const total = known.size + new Set(incomingNew).size;

    // The cap is PER TIER. Every authenticated account could previously create 8
    // profiles regardless of subscription, so the paid feature wasn't actually
    // gated anywhere the client couldn't bypass. The tier is re-read here rather
    // than trusted from the session, and an UNKNOWN tier (RevenueCat unreachable)
    // gets the Plus cap — never block a possible subscriber over an outage.
    const { known: tierKnown, plus } = await checkPlus(userID, env);
    const cap = (tierKnown && !plus) ? FREE_PROFILES : MAX_PROFILES;
    if (total > cap) {
      return json({
        error: "profile_limit",
        limit: cap,
        message: cap === FREE_PROFILES
          ? "Tadah Plus is needed to add family members."
          : `An account can have at most ${MAX_PROFILES} profiles.`,
      }, 409);
    }
  }

  const upsertProfile = env.DB.prepare(
    `INSERT INTO profiles (user_id, profile_id, payload, updated_at, deleted_at) VALUES (?, ?, ?, ?, NULL)
     ON CONFLICT(user_id, profile_id) DO UPDATE SET
       payload = excluded.payload, updated_at = excluded.updated_at, deleted_at = NULL
     WHERE excluded.updated_at > profiles.updated_at`
  );
  for (const p of profiles) {
    const profileId = validID(p && p.id);
    const updatedAt = validStamp(p && p.updatedAt, now);
    if (!profileId || !updatedAt) return json({ error: "Bad profile record" }, 400);
    const payload = typeof (p && p.payload) === "string" ? p.payload : JSON.stringify((p && p.payload) ?? "");
    if (payload.length > MAX_PAYLOAD) return json({ error: "Payload too large", profileId }, 413);
    stmts.push(upsertProfile.bind(userID, profileId, payload, updatedAt));
  }

  const tombProfile = env.DB.prepare(
    `INSERT INTO profiles (user_id, profile_id, payload, updated_at, deleted_at) VALUES (?, ?, '', ?, ?)
     ON CONFLICT(user_id, profile_id) DO UPDATE SET
       payload = '', updated_at = excluded.updated_at, deleted_at = excluded.deleted_at
     WHERE excluded.updated_at > profiles.updated_at`
  );
  for (const d of profileDeletes) {
    const profileId = validID(d && d.id);
    const deletedAt = validStamp(d && d.deletedAt, now);
    if (!profileId || !deletedAt) return json({ error: "Bad profile delete record" }, 400);
    stmts.push(tombProfile.bind(userID, profileId, deletedAt, deletedAt));
  }

  if (stmts.length) {
    try { await env.DB.batch(stmts); } catch { return json({ error: "Store failed" }, 500); }
  }

  // Pull everything changed for this user since the client's cursor.
  //
  // The cursor is COMPOSITE — (updated_at, id) per stream — because updated_at
  // alone isn't unique. A bulk write (seeding an account, a migration) can give
  // more than MAX_PULL rows the same stamp; `updated_at > cursor` then skips every
  // row past the first page of that stamp, permanently. Tasks and profiles keep
  // separate components, packed into one opaque string the client just round-trips.
  const { task: taskMark, profile: profileMark } = parseCursor(since);

  const page = (table, idCol, mark) => env.DB.prepare(
    `SELECT ${idCol} AS id, payload, updated_at, deleted_at FROM ${table}
      WHERE user_id = ? AND (updated_at > ? OR (updated_at = ? AND ${idCol} > ?))
      ORDER BY updated_at ASC, ${idCol} ASC LIMIT ?`
  ).bind(userID, mark.at, mark.at, mark.id, MAX_PULL);

  const rows = (await page("tasks", "item_id", taskMark).all()).results || [];
  const profileRows = (await page("profiles", "profile_id", profileMark).all()).results || [];

  const outChanges = [], outDeletes = [];
  for (const r of rows) {
    if (r.deleted_at) outDeletes.push({ id: r.id, deletedAt: r.deleted_at });
    else outChanges.push({ id: r.id, payload: r.payload, updatedAt: r.updated_at });
  }

  // Family profiles ride the SAME round trip — a profile and the to-dos inside it
  // should never arrive on a device one without the other.
  const outProfiles = [], outProfileDeletes = [];
  for (const r of profileRows) {
    if (r.deleted_at) outProfileDeletes.push({ id: r.id, deletedAt: r.deleted_at });
    else outProfiles.push({ id: r.id, payload: r.payload, updatedAt: r.updated_at });
  }

  // Advance to the LAST row actually returned (rows are ordered), never to the max
  // stamp seen — otherwise the tail of a truncated page is skipped.
  const advance = (pageRows, mark) => {
    const last = pageRows[pageRows.length - 1];
    return last ? { at: last.updated_at, id: last.id } : mark;
  };
  const cursor = formatCursor(advance(rows, taskMark), advance(profileRows, profileMark));

  await env.DB.prepare("UPDATE sessions SET last_seen = ? WHERE token = ?").bind(now, token).run();
  return json({
    changes: outChanges, deletes: outDeletes,
    profiles: outProfiles, profileDeletes: outProfileDeletes,
    cursor,
    // True when either stream filled its page, so the client knows to come straight
    // back for the rest instead of waiting for the next lifecycle event.
    more: rows.length >= MAX_PULL || profileRows.length >= MAX_PULL,
  }, 200);
}

// A live (non-revoked, non-expired) session row, or null.
async function resolveSession(db, token) {
  if (!token) return null;
  const row = await db.prepare(
    "SELECT user_id, device_id, revoked, last_seen, plus_checked_at FROM sessions WHERE token = ?"
  ).bind(token).first();
  if (!row || row.revoked) return null;
  // Sessions expire on inactivity. They used to live forever, so a token copied
  // off a device stayed usable indefinitely even after the user stopped using it.
  // last_seen is refreshed on every /sync, so an active device never trips this.
  const idleMs = Date.now() - Date.parse(row.last_seen || 0);
  if (!(idleMs < SESSION_TTL_DAYS * 86400_000)) {
    await db.prepare("UPDATE sessions SET revoked = 1 WHERE token = ?").bind(token).run();
    return null;
  }
  return row;
}

// Re-verify the subscription behind a live session, at most once a day. Returns
// true when this session was revoked as a result (caller should 401).
//
// Plus used to be consulted only at sign-in, so an expired subscriber kept every
// extra device they had ever added — the paid limit was effectively permanent.
async function enforceTierOnSync(env, session, token) {
  const checkedMs = Date.parse(session.plus_checked_at || 0) || 0;
  if (Date.now() - checkedMs < 86400_000) return false;

  const { known, plus } = await checkPlus(session.user_id, env);
  const now = new Date().toISOString();
  if (!known) return false;    // RevenueCat unreachable → never sign anyone out

  await env.DB.prepare("UPDATE sessions SET plus_checked_at = ? WHERE token = ?")
    .bind(now, token).run();
  if (plus) return false;

  // Back on the free tier: keep only the most recently active device. Revoking
  // "all but the newest" rather than "all" means the person keeps using the phone
  // they're actually holding instead of being signed out everywhere at once.
  const newest = await env.DB.prepare(
    "SELECT token FROM sessions WHERE user_id = ? AND revoked = 0 ORDER BY last_seen DESC LIMIT 1"
  ).bind(session.user_id).first();
  if (!newest || newest.token === token) return false;

  await env.DB.prepare("UPDATE sessions SET revoked = 1 WHERE user_id = ? AND revoked = 0 AND token != ?")
    .bind(session.user_id, newest.token).run();
  return true;
}

// ── cursor packing ───────────────────────────────────────────────────────────
// "t:<stamp>~<id>|p:<stamp>~<id>". A legacy cursor (a bare timestamp from a client
// that synced before this change) is read as the stamp for BOTH streams with an
// empty id, which re-sends at most one already-applied page — harmless, since
// applying a change is idempotent under last-writer-wins.
function parseCursor(since) {
  const blank = { at: "", id: "" };
  if (!since) return { task: blank, profile: blank };
  if (!since.includes("|")) return { task: { at: since, id: "" }, profile: { at: since, id: "" } };
  const parts = Object.fromEntries(
    since.split("|").map((s) => [s.slice(0, 1), s.slice(2)]));
  const split = (s) => {
    if (!s) return blank;
    const i = s.lastIndexOf("~");
    return i < 0 ? { at: s, id: "" } : { at: s.slice(0, i), id: s.slice(i + 1) };
  };
  return { task: split(parts.t), profile: split(parts.p) };
}
function formatCursor(task, profile) {
  return `t:${task.at}~${task.id}|p:${profile.at}~${profile.id}`;
}

// ── record validation ────────────────────────────────────────────────────────
// Ids are UUIDs on the client; anything else is a malformed or hostile record and
// should never become a primary key.
const UUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
function validID(v) {
  return typeof v === "string" && UUID_RE.test(v) ? v : "";
}

// An ISO-8601 stamp, CLAMPED to now if it's in the future. A device with a badly
// skewed clock (or a client sending year 9999) would otherwise write a row that no
// honest later edit can ever beat under last-writer-wins — the task would be frozen
// forever. Clamping keeps the user's write while removing the poison.
const MAX_SKEW_MS = 5 * 60_000;
function validStamp(v, now) {
  if (typeof v !== "string" || v.length === 0 || v.length > 40) return "";
  const t = Date.parse(v);
  if (!Number.isFinite(t)) return "";
  return t > Date.now() + MAX_SKEW_MS ? now : v;
}

// Hex SHA-256, for comparing the Sign-in-with-Apple nonce against the token claim.
async function sha256Hex(s) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

// Verify a Sign-in-with-Apple identity JWT against Apple's public keys and its
// standard claims. Returns the verified claims (`sub` is the stable user id;
// `nonce` is checked by the caller against the raw value the client sends).
// Throws on any failure.
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
  // Binds the token to THIS app. handleAppleAuth refuses to run without
  // APPLE_AUDIENCE set, so this is never skipped in production.
  if (payload.aud !== env.APPLE_AUDIENCE) throw new Error("bad audience");
  if (!payload.exp || payload.exp * 1000 < Date.now()) throw new Error("expired");
  if (!payload.sub) throw new Error("no subject");
  return { sub: String(payload.sub), nonce: payload.nonce ? String(payload.nonce) : "" };
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

// bytes/string → base64url (for MINTING the Apple client-secret JWT).
function b64urlFromBytes(bytes) {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function b64url(str) { return b64urlFromBytes(new TextEncoder().encode(str)); }

// "-----BEGIN PRIVATE KEY----- …" → the DER bytes WebCrypto wants. Tolerates the
// literal "\n" sequences you get when a .p8 is pasted into `wrangler secret put`.
function pemToBytes(pem) {
  const body = String(pem)
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN [^-]+-----/, "")
    .replace(/-----END [^-]+-----/, "")
    .replace(/\s+/g, "");
  const bin = atob(body);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

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

// ── exported for tests ───────────────────────────────────────────────────────
// The Workers runtime only ever uses the `export default` handler above; these
// named exports exist so the pure logic (cursors, validation, request shaping)
// can be unit-tested without a network or a D1 binding. See worker.test.js.
export {
  parseCursor,
  formatCursor,
  validID,
  validStamp,
  sanitizeMessages,
  clamp,
  pemToBytes,
  MAX_MESSAGES,
  MAX_MESSAGE_CHARS,
  MAX_PROFILES,
  FREE_PROFILES,
};
