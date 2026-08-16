// Cuevi Worker — AI proxy + anonymous metrics ingest
//
// Routes, all POST-only and all gated by the optional X-Cuevi-Token secret:
//   • "/" or /v1/chat/completions  → proxy to OpenAI (keeps the key OFF the phone;
//     the app sends NO key, this Worker adds the secret OPENAI_API_KEY it holds).
//   • POST /events                 → store anonymous tester metrics in D1 (Part 1).
//   • POST /auth/register|login    → email + password, issue a session.
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
//   • /auth: passwords are salted+hashed server-side, sessions expire, and both
//     register and login are rate-limited like every other route.
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

// Body ceilings for the NON-chat routes. Every route reads through readJSON(),
// so nothing is ever buffered unbounded before validation runs.
//   • /events, /auth/*, /account/* are small fixed-shape payloads.
//   • /sync legitimately carries a page of records, hence its own larger limit
//     (MAX_SYNC_BATCH records × MAX_PAYLOAD would be far bigger, but the batch
//     count check downstream catches the rest).
const MAX_BODY_BYTES = 64 * 1024;
const MAX_SYNC_BYTES = 8 * 1024 * 1024;

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
//
// ⚠️ SIZED FOR D1's PER-INVOCATION QUERY LIMIT, not for what feels generous.
// D1 Free allows 50 queries per Worker invocation, and statements inside a
// batch() each count. At 500 this route could never store a full batch — the
// write failed, the client never advanced its cursor, and the same doomed batch
// retried forever. 25 leaves headroom for the lazy DDL and any read on the path.
const MAX_BATCH = 25;                                // events accepted per request
const VALID_KINDS = new Set(["confirmed", "completed"]);
const MAX_STR = 64;                                  // clamp every stored string

// /sync + /auth guardrails (Part 3 account task sync).
//
// ⚠️ Same D1 constraint as MAX_BATCH above. Every change/delete/profile record in
// a push becomes one statement in the batch, and /sync also spends queries on
// session lookup, the profile-cap read, two pulls and the last_seen update. 25
// records keeps the worst case comfortably under D1 Free's 50-per-invocation
// ceiling. The CLIENT pages to this size (see SyncService.maxRecordsPerPush), so
// a device with hundreds of pending edits sends several requests instead of one
// oversized one that could never succeed.
const MAX_SYNC_BATCH = 25;      // changes + deletes + profiles accepted per push
const MAX_PULL = 1000;          // rows returned per pull (see also MAX_PULL_BYTES)
// ⚠️ ROW COUNT ALONE IS NOT A BOUND. MAX_PULL × MAX_PAYLOAD is 100 MB, and the D1
// result set, the output arrays and JSON.stringify()'s buffer all share the
// Worker's 128 MB ceiling — so a large account could OOM the pull instead of
// syncing. Responses are therefore capped by BYTES as well; whichever limit is
// reached first ends the page, and `more` brings the client back for the rest.
const MAX_PULL_BYTES = 4 * 1024 * 1024;
// Per-row allowance for the id, timestamps and JSON punctuation around a payload.
const ROW_OVERHEAD_BYTES = 120;
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
// can't exceed 8 of either. Free is 1 profile / 1 device (see issueSession).
const MAX_PROFILES = 8;
const MAX_DEVICES = 8;
// Free tier: one profile (you), one device. Must match ProfileStore.freeMax.
const FREE_PROFILES = 1;
// STORAGE SAFETY CEILINGS — deliberately NOT the commercial limits.
//
// Be clear about what this is: the product's paid limits are 20/100 tasks PER
// PROFILE (TaskLimit.max / .maxPlus) and are enforced in the app. These numbers
// are per ACCOUNT and much larger; they exist only so a modified client cannot
// store unbounded rows, which is both a cost problem and exactly the volume
// needed to push a pull response toward the Worker's memory ceiling.
//
// Do not mistake these for tier enforcement, and don't tighten them to 20/100
// without also making them per-profile — the server can't see profile membership
// (payloads are opaque to it), so an account-wide 20 would break a legitimate
// family of four long before anyone hit their own limit.
const FREE_TASK_STORAGE_CEILING = 200;
const PLUS_TASK_STORAGE_CEILING = 2000;
// MUST match PlusStore.entitlementID in the app AND the Entitlement identifier in
// the RevenueCat dashboard. If these drift, checkPlus() sees every user as free
// and Plus accounts get the free one-device limit. Override with a
// PLUS_ENTITLEMENT var if the dashboard id ever changes.
const PLUS_ENTITLEMENT = "Tadah Pro";

// One-time (per isolate) lazy DDL so the quota table exists without a manual
// migration step. Cheap: runs once per Worker instance, IF NOT EXISTS after.
let usageTableReady = false;
let syncTablesReady = false;              // lazy DDL for tasks/sessions (see ensureSyncTables)

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
    if (path === "/auth/email/register") return handleEmailRegister(request, env);
    if (path === "/auth/email/login") return handleEmailLogin(request, env);
    if (path === "/auth/email/reset/request") return handleResetRequest(request, env);
    if (path === "/auth/email/reset/confirm") return handleResetConfirm(request, env);
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
  // writes back; the input side was unbounded, and prompt tokens are most of the
  // bill on a document scan.
  const read = await readJSON(request, MAX_CHAT_BYTES);
  if (!read.ok) return read.response;
  const body = read.body;

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

// Read and parse a JSON body with a HARD byte ceiling.
//
// Every route used to call `request.json()` straight away, which buffers whatever
// the caller sends before any validation runs — so batch-count checks downstream
// couldn't prevent a multi-megabyte body from being materialised first. This
// checks the declared Content-Length AND the bytes actually read (a chunked
// request can lie, or omit the header entirely).
//
// Returns { ok: true, body } or { ok: false, response } ready to return.
async function readJSON(request, limit = MAX_BODY_BYTES) {
  const tooLarge = { ok: false, response: json({ error: "Request too large" }, 413) };

  const declared = Number(request.headers.get("Content-Length") || 0);
  if (Number.isFinite(declared) && declared > limit) return tooLarge;
  if (!request.body) return { ok: false, response: json({ error: "Invalid JSON" }, 400) };

  // STREAMED, and counted in BYTES.
  //
  // Two bugs the earlier version had, both of which let an oversized body through:
  //   • it awaited request.text() first, so the whole payload was buffered before
  //     the limit was consulted — the check couldn't prevent the memory cost it
  //     was there to prevent;
  //   • it then compared `raw.length`, which is UTF-16 code units, NOT bytes. A
  //     body of two-byte characters measured at half its real size: 80,008 bytes
  //     sailed through a 65,536-byte limit as "40,008".
  // Reading chunk by chunk and cancelling the moment the byte count is exceeded
  // fixes both.
  const reader = request.body.getReader();
  const chunks = [];
  let received = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      received += value.byteLength;
      if (received > limit) {
        await reader.cancel();
        return tooLarge;
      }
      chunks.push(value);
    }
  } catch {
    return { ok: false, response: json({ error: "Invalid body" }, 400) };
  }

  const buffer = new Uint8Array(received);
  let offset = 0;
  for (const chunk of chunks) { buffer.set(chunk, offset); offset += chunk.byteLength; }

  try {
    const body = JSON.parse(new TextDecoder().decode(buffer));
    if (!body || typeof body !== "object") {
      return { ok: false, response: json({ error: "Invalid JSON" }, 400) };
    }
    return { ok: true, body };
  } catch {
    return { ok: false, response: json({ error: "Invalid JSON" }, 400) };
  }
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

  const read = await readJSON(request);
  if (!read.ok) return read.response;
  const body = read.body;

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
//   POST /auth/register|login  { email, derivedKey, deviceId } → authenticate,
//     check the user's tier via RevenueCat, enforce the free = 1-device rule, and
//     issue a session token.
//   POST /sync        header X-Tadah-Session; { since, changes[], deletes[] } →
//     last-writer-wins upsert into `tasks`, then return everything changed since
//     the client's cursor. A revoked session ⇒ 401 (signed out on another device).
// The user_id ALWAYS comes from the resolved session — never taken from the client.

// Create tasks/sessions if a migration hasn't been run (mirrors ai_usage's lazy
// DDL). Cheap: once per isolate, IF NOT EXISTS after.
async function ensureSyncTables(db) {
  if (syncTablesReady) return;
  await db.exec("CREATE TABLE IF NOT EXISTS tasks (user_id TEXT NOT NULL, item_id TEXT NOT NULL, payload TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT, PRIMARY KEY (user_id, item_id))");
  await db.exec("CREATE TABLE IF NOT EXISTS sessions (token TEXT PRIMARY KEY, user_id TEXT NOT NULL, device_id TEXT NOT NULL, created_at TEXT NOT NULL, last_seen TEXT NOT NULL, revoked INTEGER NOT NULL DEFAULT 0)");
  await db.exec("CREATE TABLE IF NOT EXISTS profiles (user_id TEXT NOT NULL, profile_id TEXT NOT NULL, payload TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT, PRIMARY KEY (user_id, profile_id))");
  // (The single-use Sign-in-with-Apple nonce table went with the route on
  // 2026-08-15. It is NOT created here any more — nothing reads or writes a nonce.
  // An existing deployment keeps its empty `used_nonces` table until it is dropped
  // by hand; it is unreferenced either way.)
  // Per-user progress through account deletion. Deletion spans RevenueCat and D1
  // and cannot be atomic, so the completed step is recorded and a retry resumes
  // rather than repeating (or falsely reporting) work.
  // Email accounts + their reset codes. Created lazily like the rest so a Worker
  // deployed without running schema.sql still works rather than 500-ing on the
  // first registration.
  await db.exec("CREATE TABLE IF NOT EXISTS accounts (user_id TEXT PRIMARY KEY, email TEXT NOT NULL, pw_hash TEXT NOT NULL, pw_salt TEXT NOT NULL, pw_iterations INTEGER NOT NULL, pw_version INTEGER NOT NULL DEFAULT 1, verified_at TEXT, created_at TEXT NOT NULL)");
  await db.exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_accounts_email ON accounts(email)");
  await db.exec("CREATE TABLE IF NOT EXISTS password_resets (user_id TEXT PRIMARY KEY, code_hash TEXT NOT NULL, expires_at TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL)");
  await db.exec("CREATE TABLE IF NOT EXISTS account_deletions (user_id TEXT PRIMARY KEY, revenuecat_deleted INTEGER NOT NULL DEFAULT 0, started_at TEXT NOT NULL)");
  // Added after the sessions table shipped, so it's an ALTER rather than part of
  // the CREATE above. Harmless duplicate-column error on an already-migrated DB.
  try { await db.exec("ALTER TABLE sessions ADD COLUMN plus_checked_at TEXT"); } catch { /* already there */ }
  syncTablesReady = true;
}

// Sign in with Apple was REMOVED on 2026-08-15 along with its route, token
// verification, JWKS handling and grant revocation. It authenticates the DEVICE's
// Apple ID, so a family member on their own iPhone could only ever create their
// own account — which made a shared family account unbuildable on it. Accounts
// never shipped under it, so there is nothing to keep a compatibility path for.

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

// Delete the ENTIRE account. Apple (App Store guideline 5.1.1(v)) requires an
// in-app path that deletes the account and its data, not just the local copy.
//
// The Sign-in-with-Apple grant revocation this handler used to do first is gone
// with the auth route — every account is an email account, and there is no
// third-party grant to sever. What remains is RevenueCat, then our own rows.
//
// Order still matters: revoke the third-party state FIRST, while we still have
// the ids to do it with, and only drop our rows once that has succeeded. Deleting
// our rows first would leave no way to retry.
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

  const read = await readJSON(request);
  if (!read.ok) return read.response;

  // ACCOUNTS RE-AUTHENTICATE WITH THEIR PASSWORD.
  //
  // Deleting an account is irreversible and takes every to-do with it, so it must
  // not be possible with a borrowed unlocked phone — hence proving you know the
  // password. (This used to read an `authorizationCode` from the body for Apple
  // grant revocation; the field was still being parsed long after the code that
  // consumed it was deleted, so it went too.)
  const emailAccount = await env.DB.prepare(
    "SELECT pw_hash, pw_salt FROM accounts WHERE user_id = ?").bind(userID).first();

  if (emailAccount) {
    const derived = validDerivedKey(read.body && read.body.derivedKey);
    const computed = await derivePasswordHash(env, derived || "0".repeat(64),
                                              emailAccount.pw_salt);
    if (!derived || !timingSafeEqual(computed, emailAccount.pw_hash)) {
      return json({ error: "invalid_credentials" }, 401);
    }
    if (!env.REVENUECAT_SECRET) {
      return json({ error: "not_configured",
                    message: "Account deletion is temporarily unavailable. Please contact support." }, 501);
    }
  } else {
    // No `accounts` row means no account to delete. Every account is an email
    // account now (Apple auth is gone and never shipped), so this is a session
    // pointing at nothing rather than a legacy case to support.
    return json({ error: "invalid_credentials" }, 401);
  }

  // Deletion spans two systems and CANNOT be atomic — a RevenueCat success
  // followed by a D1 failure leaves a partially-deleted account no matter how it
  // is ordered. Rather than pretend otherwise, progress is recorded and the whole
  // handler is idempotent: a retry resumes at the step that hasn't completed, and
  // a completed step is skipped. The response reports exactly what is done.
  const progress = await deletionProgress(env.DB, userID);

  // 1) RevenueCat subscriber, so no purchase history stays keyed to this user id.
  //    Purchases.logOut() only changes the SDK's local identity — it deletes
  //    nothing. The RESULT is checked: silently swallowing a failure here meant
  //    reporting a complete deletion while RevenueCat still held the customer.
  if (!progress.revenuecat) {
    const rc = await deleteRevenueCatSubscriber(userID, env);
    if (!rc.ok) {
      // Unconfigured is an operator problem, not a transient one — retrying won't
      // help until the secret is set, so say so differently.
      if (rc.unconfigured) {
        return json({ error: "not_configured", completed: progress,
                      message: "Account deletion can't be completed right now. Please contact support and we'll finish it for you." }, 501);
      }
      return json({ error: "revenuecat_failed", completed: progress,
                    message: "We couldn't finish deleting your subscription record. Nothing else has been removed yet. Please try again." }, 502);
    }
    await markDeletionStep(env.DB, userID);
    progress.revenuecat = true;
  }

  // 2) Our own rows, last. ONE BATCH, including the progress row — D1 batches are
  //    transactional and roll back as a unit.
  //
  //    Deleting the progress row in a separate statement was a trap: it runs after
  //    `sessions` is already gone, so if it failed the user could no longer
  //    authenticate to retry — locked out of finishing their own deletion. In one
  //    batch, either everything goes or nothing does and the session survives.
  try {
    await env.DB.batch([
      env.DB.prepare("DELETE FROM tasks WHERE user_id = ?").bind(userID),
      env.DB.prepare("DELETE FROM profiles WHERE user_id = ?").bind(userID),
      env.DB.prepare("DELETE FROM account_deletions WHERE user_id = ?").bind(userID),
      // Any outstanding reset code goes too. Leaving it behind would let a live
      // code outlive the account it belonged to — and if the address were later
      // re-registered, an old row keyed on a recycled user id is a mess nobody
      // wants to reason about.
      env.DB.prepare("DELETE FROM password_resets WHERE user_id = ?").bind(userID),
      env.DB.prepare("DELETE FROM sessions WHERE user_id = ?").bind(userID),
      // The credentials themselves. Leaving this row behind would keep the email
      // address registered forever — the user's data would be gone but they could
      // never sign up again with their own address, and we'd still be holding a
      // password hash for an account we told them we deleted.
      env.DB.prepare("DELETE FROM accounts WHERE user_id = ?").bind(userID),
    ]);
  } catch {
    return json({ error: "store_failed", completed: progress,
                  message: "Your subscription record is deleted, but we couldn't finish deleting your saved items. Please try again." }, 502);
  }
  return json({ ok: true }, 200);
}

// Which deletion steps have already succeeded for this user. Only RevenueCat can
// half-succeed now; the Apple-grant step went with Sign in with Apple. Older
// databases still carry an `apple_revoked` column — it is never read or written.
async function deletionProgress(db, userID) {
  const row = await db.prepare(
    "SELECT revenuecat_deleted FROM account_deletions WHERE user_id = ?"
  ).bind(userID).first();
  return { revenuecat: !!(row && row.revenuecat_deleted) };
}

async function markDeletionStep(db, userID) {
  await db.prepare(
    `INSERT INTO account_deletions (user_id, revenuecat_deleted, started_at) VALUES (?, 1, ?)
     ON CONFLICT(user_id) DO UPDATE SET revenuecat_deleted = 1`
  ).bind(userID, new Date().toISOString()).run();
}

// RevenueCat keeps a subscriber record keyed by the app user id.
// Deleting the account must delete that too, or purchase history outlives it.
//
// Returns { ok }. The result is CHECKED by the caller — this used to swallow
// missing configuration, network errors and every HTTP status alike, so a failed
// deletion still reported complete success to the user.
async function deleteRevenueCatSubscriber(userID, env) {
  // FAIL CLOSED when unconfigured. It's tempting to treat a missing secret as
  // "no purchases exist, nothing to delete" — but the APP configures RevenueCat
  // with its own public key (see TadahApp), so subscriber records are created
  // regardless of whether this Worker secret is set. A missing/rotated secret
  // would then leave that data in place while telling the user deletion finished.
  if (!env.REVENUECAT_SECRET) return { ok: false, unconfigured: true };
  try {
    const res = await fetch(
      `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userID)}`,
      { method: "DELETE", headers: { Authorization: `Bearer ${env.REVENUECAT_SECRET}` } });
    // 200 = deleted. 404 = no such subscriber, which is the desired end state for
    // anyone who never purchased. Anything else is a real failure.
    return { ok: res.status === 200 || res.status === 404 };
  } catch {
    return { ok: false };
  }
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

  // Sync legitimately carries a page of records, so it gets the larger ceiling.
  const read = await readJSON(request, MAX_SYNC_BYTES);
  if (!read.ok) return read.response;
  const body = read.body;
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
  // DELETES ARE COLLECTED SEPARATELY AND RUN FIRST.
  //
  // D1 executes a batch in order, and every conflict clause below requires a
  // STRICTLY newer timestamp. So for an id that appears as both a change and a
  // delete with the SAME stamp, whichever runs first wins — the second no-ops.
  // With changes first the change won, while the cap preflight had already
  // counted that id as deleted: a request could pass the check and still leave
  // the account one row over its ceiling (and the same trick bypassed the
  // profile cap).
  //
  // Running deletions first makes the database agree with the declared policy —
  // a tie goes to the delete — which is also the conservative direction: a
  // deletion is never silently undone.
  const stmts = [];
  const deleteStmts = [];

  // Upsert live changes, last-writer-wins on updated_at (a stale change no-ops).
  // ⚠️ EVERY write below is conditional on the session STILL being live.
  //
  // The session was validated at the top of the request, but account deletion can
  // land in between: it erases every row (sessions included) and returns success,
  // and then this already-authorized sync recreates the tasks it was holding —
  // the user's account resurrects itself moments after they deleted it. Making the
  // liveness check part of the write itself closes that window, because the
  // deletion's DELETE FROM sessions and these inserts can no longer interleave.
  const LIVE = "EXISTS (SELECT 1 FROM sessions WHERE token = ? AND revoked = 0)";

  // NOTE ON THE RESIDUAL RACE: the storage-ceiling preflight above is a read
  // outside the batch, so two syncs for the same account landing together can
  // each see one free slot and both insert — overshooting the ceiling by the
  // number of concurrent requests. Folding the count into this INSERT's WHERE was
  // tried and rejected: SQLite will not accept a subquery over the target table
  // in an upsert's SELECT, and the attempt broke every sync write.
  //
  // Left as-is deliberately. This ceiling is a STORAGE safety net (200/2000 per
  // account), not a correctness or billing boundary — the commercial limits are
  // enforced in the app — and overshooting it by a row or two under genuine
  // concurrency costs nothing. Tightening it properly needs a real transaction
  // around read-then-write, which D1 does not currently offer outside a batch.
  const upsert = env.DB.prepare(
    `INSERT INTO tasks (user_id, item_id, payload, updated_at, deleted_at)
     SELECT ?, ?, ?, ?, NULL WHERE ${LIVE}
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
    // byteLength, not .length: MAX_PAYLOAD is a byte budget, and String.length
    // counts UTF-16 units — a payload of non-ASCII text measured up to 4x small.
    if (byteLength(payload) > MAX_PAYLOAD) return json({ error: "Payload too large", itemId }, 413);
    stmts.push(upsert.bind(userID, itemId, payload, updatedAt, token));
  }

  // Soft-delete (tombstone), also LWW: a delete only wins if newer than the row.
  const tomb = env.DB.prepare(
    `INSERT INTO tasks (user_id, item_id, payload, updated_at, deleted_at)
     SELECT ?, ?, '', ?, ? WHERE ${LIVE}
     ON CONFLICT(user_id, item_id) DO UPDATE SET
       payload = '', updated_at = excluded.updated_at, deleted_at = excluded.deleted_at
     WHERE excluded.updated_at > tasks.updated_at`
  );
  for (const d of deletes) {
    const itemId = validID(d && d.id);
    const deletedAt = validStamp(d && d.deletedAt, now);
    if (!itemId || !deletedAt) return json({ error: "Bad delete record" }, 400);
    deleteStmts.push(tomb.bind(userID, itemId, deletedAt, deletedAt, token));
  }

  // ── family profiles, same LWW contract as tasks ──────────────────────────
  // (`profiles` / `profileDeletes` were read above, so they count toward the
  // batch limit.)

  // Server-side cap: a client can lie, and profiles are what Plus is SOLD on.
  // Only counts NEW ids — edits to existing profiles are always allowed through,
  // so hitting the cap can never freeze someone out of renaming what they have.
  if (profiles.length) {
    // Read LIVE *and* TOMBSTONED rows. Reading only live ones made a stale client
    // update for a profile the server had already deleted look like a brand-new
    // profile — so a free account whose canonical owner was still in flight got a
    // permanent 409 and could never pull the tombstone that would have resolved
    // it. The cap has to be computed on the FINAL state, which means knowing about
    // the deletions too.
    const rows = (await env.DB.prepare(
      "SELECT profile_id, updated_at, deleted_at FROM profiles WHERE user_id = ?"
    ).bind(userID).all()).results || [];
    // Same merge-then-count rule as tasks: resolve every id to its FINAL state
    // before counting, so an id appearing in both `profiles` and `profileDeletes`
    // is counted by whichever write actually wins rather than by pass order.
    const finalProfiles = new Map();   // id → { at, live, fromServer }
    for (const r of rows) {
      finalProfiles.set(r.profile_id, { at: r.updated_at, live: !r.deleted_at, fromServer: true });
    }
    const considerProfile = (id, at, isLive) => {
      const seen = finalProfiles.get(id);
      if (!seen) { finalProfiles.set(id, { at, live: isLive, fromServer: false }); return; }
      if (seen.fromServer) {
        if (at > seen.at) finalProfiles.set(id, { at, live: isLive, fromServer: false });
        return;
      }
      if (at > seen.at || (at === seen.at && !isLive)) {
        finalProfiles.set(id, { at, live: isLive, fromServer: false });
      }
    };
    for (const p of profiles) {
      const id = validID(p && p.id);
      const at = validStamp(p && p.updatedAt, now);
      if (id && at) considerProfile(id, at, true);
    }
    for (const d of profileDeletes) {
      const id = validID(d && d.id);
      const at = validStamp(d && d.deletedAt, now);
      if (id && at) considerProfile(id, at, false);
    }
    const total = [...finalProfiles.values()].filter((v) => v.live).length;

    // Which live profiles this request ADDS — ids that are live at the end but
    // were not already live on the server.
    //
    // ⚠️ THE CAP MUST ONLY BLOCK GROWTH, NOT EDITS. Counting the final total
    // alone locked out anyone already ABOVE the cap, which is exactly what a
    // lapsed Plus family is: cap drops to 1 while they still have 3 profiles, so
    // every profile push — including a plain rename — returned 409 and, because
    // this route rejects the WHOLE request, their tasks stopped syncing too. The
    // app hides routine sync errors, so it just looked like the app had quietly
    // stopped saving. Renaming what you already have can never be the thing that
    // breaks your backup.
    const wasLiveOnServer = new Set(
      rows.filter((r) => !r.deleted_at).map((r) => r.profile_id));
    const added = [...finalProfiles.entries()]
      .filter(([id, v]) => v.live && !v.fromServer && !wasLiveOnServer.has(id));

    // STORAGE IS NOT THE PAID BOUNDARY — USING PROFILES IS.
    //
    // This used to apply the FREE cap (1) to what the database may hold, and that
    // broke real people two ways. A Plus family that lapsed still had 3 profiles
    // on disk, and a free account could end up with 2 via the deliberate
    // fail-open while RevenueCat was unreachable. In both cases every sync then
    // returned 409 — and because this route rejects the WHOLE request, their
    // TASKS stopped backing up too, over rows that were merely *stored*.
    //
    // The app already gates the feature: `ProfileStore.familyUnlocked` hides the
    // switcher, the assignee picker and the per-person lists on a free account, so
    // extra profiles are invisible and unusable there — it simply looks like one
    // list. Keeping the rows costs nothing and means resubscribing restores the
    // family instead of asking someone to rebuild it.
    //
    // So the server keeps only the ABSOLUTE ceiling (8) — an anti-abuse bound on
    // storage, not a tier check. No `checkPlus` call either, which also drops an
    // outbound request from the hot sync path.
    const cap = MAX_PROFILES;
    if (total > cap && added.length > 0) {
      return json({
        error: "profile_limit",
        limit: cap,
        message: `An account can have at most ${MAX_PROFILES} profiles.`,
      }, 409);
    }
  }

  // Storage ceiling, computed on the FINAL last-writer-wins state — the same
  // arithmetic the profile cap uses, and for the same reason: counting raw
  // submissions instead of what will actually win both over-counts (a stale
  // update to a tombstoned row is not a new task) and under-counts (a winning
  // delete in this very request frees a slot).
  if (changes.length) {
    // Only pushes that carry changes need the tier — resolving it outside this
    // block made a RevenueCat round trip on every pull-only sync (i.e. most
    // launch/foreground passes, on every device).
    const { known: tierKnownForTasks, plus: plusForTasks } = await checkPlus(userID, env);
    const taskCeiling = (tierKnownForTasks && !plusForTasks)
      ? FREE_TASK_STORAGE_CEILING : PLUS_TASK_STORAGE_CEILING;

    const rows = (await env.DB.prepare(
      "SELECT item_id, updated_at, deleted_at FROM tasks WHERE user_id = ?"
    ).bind(userID).all()).results || [];

    // RESOLVE EACH ID TO ITS FINAL STATE FIRST, then count.
    //
    // Walking `deletes` and `changes` as two separate passes was not the same
    // thing as the final state: an id present in BOTH arrays would be counted by
    // whichever pass ran last, regardless of which write actually wins. A new id
    // that is created and then tombstoned (delete newer) ends up NOT live, but the
    // preflight counted it as live and returned a 409 for a request that would
    // have stored nothing.
    //
    // Merge every stamp per id — server row, incoming change, incoming delete —
    // and let the newest decide, exactly as the upserts below will.
    const finalState = new Map();   // id → { at, live, fromServer }
    for (const r of rows) {
      finalState.set(r.item_id, { at: r.updated_at, live: !r.deleted_at, fromServer: true });
    }
    const consider = (id, at, isLive) => {
      const seen = finalState.get(id);
      if (!seen) { finalState.set(id, { at, live: isLive, fromServer: false }); return; }
      // Against a SERVER row the comparison is strictly newer, exactly matching
      // the upserts' `WHERE excluded.updated_at > tasks.updated_at` — a tie
      // changes nothing, so the preflight must not pretend it does.
      if (seen.fromServer) {
        if (at > seen.at) finalState.set(id, { at, live: isLive, fromServer: false });
        return;
      }
      // Between two records in the SAME request, a tie goes to the delete: the
      // conservative reading, and it keeps the count from drifting upward.
      if (at > seen.at || (at === seen.at && !isLive)) {
        finalState.set(id, { at, live: isLive, fromServer: false });
      }
    };
    for (const c of changes) {
      const id = validID(c && c.id);
      const at = validStamp(c && c.updatedAt, now);
      if (id && at) consider(id, at, true);
    }
    for (const d of deletes) {
      const id = validID(d && d.id);
      const at = validStamp(d && d.deletedAt, now);
      if (id && at) consider(id, at, false);
    }
    const live = new Set(
      [...finalState.entries()].filter(([, v]) => v.live).map(([id]) => id));

    if (live.size > taskCeiling) {
      return json({ error: "task_limit", limit: taskCeiling,
                    message: "This account has reached the maximum number of stored to-dos." }, 409);
    }
  }

  const upsertProfile = env.DB.prepare(
    `INSERT INTO profiles (user_id, profile_id, payload, updated_at, deleted_at)
     SELECT ?, ?, ?, ?, NULL WHERE ${LIVE}
     ON CONFLICT(user_id, profile_id) DO UPDATE SET
       payload = excluded.payload, updated_at = excluded.updated_at, deleted_at = NULL
     WHERE excluded.updated_at > profiles.updated_at`
  );
  for (const p of profiles) {
    const profileId = validID(p && p.id);
    const updatedAt = validStamp(p && p.updatedAt, now);
    if (!profileId || !updatedAt) return json({ error: "Bad profile record" }, 400);
    const payload = typeof (p && p.payload) === "string" ? p.payload : JSON.stringify((p && p.payload) ?? "");
    if (byteLength(payload) > MAX_PAYLOAD) return json({ error: "Payload too large", profileId }, 413);
    stmts.push(upsertProfile.bind(userID, profileId, payload, updatedAt, token));
  }

  const tombProfile = env.DB.prepare(
    `INSERT INTO profiles (user_id, profile_id, payload, updated_at, deleted_at)
     SELECT ?, ?, '', ?, ? WHERE ${LIVE}
     ON CONFLICT(user_id, profile_id) DO UPDATE SET
       payload = '', updated_at = excluded.updated_at, deleted_at = excluded.deleted_at
     WHERE excluded.updated_at > profiles.updated_at`
  );
  for (const d of profileDeletes) {
    const profileId = validID(d && d.id);
    const deletedAt = validStamp(d && d.deletedAt, now);
    if (!profileId || !deletedAt) return json({ error: "Bad profile delete record" }, 400);
    deleteStmts.push(tombProfile.bind(userID, profileId, deletedAt, deletedAt, token));
  }

  // Deletions first — see the note where `deleteStmts` is declared.
  const ordered = [...deleteStmts, ...stmts];
  if (ordered.length) {
    try { await env.DB.batch(ordered); } catch { return json({ error: "Store failed" }, 500); }
  }

  // Pull everything changed for this user since the client's cursor.
  //
  // The cursor is COMPOSITE — (updated_at, id) per stream — because updated_at
  // alone isn't unique. A bulk write (seeding an account, a migration) can give
  // more than MAX_PULL rows the same stamp; `updated_at > cursor` then skips every
  // row past the first page of that stamp, permanently. Tasks and profiles keep
  // separate components, packed into one opaque string the client just round-trips.
  const { task: taskMark, profile: profileMark } = parseCursor(since);

  // The byte bound is applied IN SQL, not after the fact.
  //
  // Truncating in JavaScript was too late: D1 had already materialised up to
  // MAX_PULL rows — 1,000 × 100 KB payloads — and that result set shares the
  // Worker's 128 MB allocation, so the pull could OOM before the loop ever ran.
  // A running total inside the query means D1 only ever serialises rows that fit.
  //
  // LENGTH(CAST(payload AS BLOB)) is BYTES; bare LENGTH() on TEXT counts
  // characters, which under-measures anything non-ASCII by up to 4x — the same
  // mistake the request-size check made.
  const page = (table, idCol, mark) => env.DB.prepare(
    `SELECT id, payload, updated_at, deleted_at FROM (
       SELECT ${idCol} AS id, payload, updated_at, deleted_at,
              SUM(LENGTH(CAST(payload AS BLOB)) + ${ROW_OVERHEAD_BYTES})
                OVER (ORDER BY updated_at ASC, ${idCol} ASC
                      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running
         FROM ${table}
        WHERE user_id = ? AND (updated_at > ? OR (updated_at = ? AND ${idCol} > ?))
        ORDER BY updated_at ASC, ${idCol} ASC
        LIMIT ?
     )
     WHERE running <= ?
     ORDER BY updated_at ASC, id ASC`
  ).bind(userID, mark.at, mark.at, mark.id, MAX_PULL, MAX_PULL_BYTES);

  const rows = (await page("tasks", "item_id", taskMark).all()).results || [];
  // Whatever the tasks page didn't spend is available to profiles.
  const spent = rows.reduce((n, r) => n + byteLength(r.payload) + ROW_OVERHEAD_BYTES, 0);
  const profileBudget = Math.max(MAX_PULL_BYTES - spent, ROW_OVERHEAD_BYTES);
  const profileRows = (await env.DB.prepare(
    `SELECT id, payload, updated_at, deleted_at FROM (
       SELECT profile_id AS id, payload, updated_at, deleted_at,
              SUM(LENGTH(CAST(payload AS BLOB)) + ${ROW_OVERHEAD_BYTES})
                OVER (ORDER BY updated_at ASC, profile_id ASC
                      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running
         FROM profiles
        WHERE user_id = ? AND (updated_at > ? OR (updated_at = ? AND profile_id > ?))
        ORDER BY updated_at ASC, profile_id ASC
        LIMIT ?
     )
     WHERE running <= ?
     ORDER BY updated_at ASC, id ASC`
  ).bind(userID, profileMark.at, profileMark.at, profileMark.id, MAX_PULL, profileBudget)
    .all()).results || [];

  // Is there more AFTER what we returned?
  //
  // Inferring it from "bytes spent >= budget" was wrong: the SQL stops at the last
  // row that FITS, so when the next row is too big `spent` sits BELOW the budget
  // and truncation looked like completion. With 50 × 100 KB rows that reported
  // more:false after 41 — the remaining 9 then waited for some later lifecycle
  // sync, so a first sign-in could settle with an incomplete account.
  //
  // Ask the database instead: is there a row past the last one we returned?
  const existsAfter = async (table, idCol, rowsReturned, mark) => {
    const last = rowsReturned[rowsReturned.length - 1];
    const at = last ? last.updated_at : mark.at;
    const id = last ? last.id : mark.id;
    const row = await env.DB.prepare(
      `SELECT 1 AS more FROM ${table}
        WHERE user_id = ? AND (updated_at > ? OR (updated_at = ? AND ${idCol} > ?))
        LIMIT 1`
    ).bind(userID, at, at, id).first();
    return !!row;
  };
  const tasksTruncated = await existsAfter("tasks", "item_id", rows, taskMark);
  const profilesTruncated = await existsAfter("profiles", "profile_id", profileRows, profileMark);

  // SQL already bounded these, so every returned row is taken.
  const outChanges = [], outDeletes = [];
  const takenTasks = rows.length;
  for (const r of rows) {
    if (r.deleted_at) outDeletes.push({ id: r.id, deletedAt: r.deleted_at });
    else outChanges.push({ id: r.id, payload: r.payload, updatedAt: r.updated_at });
  }

  // Family profiles ride the SAME round trip — a profile and the to-dos inside it
  // should never arrive on a device one without the other.
  const outProfiles = [], outProfileDeletes = [];
  const takenProfiles = profileRows.length;
  for (const r of profileRows) {
    if (r.deleted_at) outProfileDeletes.push({ id: r.id, deletedAt: r.deleted_at });
    else outProfiles.push({ id: r.id, payload: r.payload, updatedAt: r.updated_at });
  }

  // Advance to the LAST row actually returned (rows are ordered), never to the max
  // stamp seen — otherwise the tail of a truncated page is skipped.
  const advance = (pageRows, taken, mark) => {
    const last = pageRows[taken - 1];
    return last ? { at: last.updated_at, id: last.id } : mark;
  };
  const cursor = formatCursor(advance(rows, takenTasks, taskMark),
                              advance(profileRows, takenProfiles, profileMark));

  await env.DB.prepare("UPDATE sessions SET last_seen = ? WHERE token = ?").bind(now, token).run();
  return json({
    changes: outChanges, deletes: outDeletes,
    profiles: outProfiles, profileDeletes: outProfileDeletes,
    cursor,
    // True when either stream filled its page, so the client knows to come straight
    // back for the rest instead of waiting for the next lifecycle event.
    // More to come if either stream filled its row budget OR was truncated for
    // size. Without the byte case, rows dropped for size would never be requested.
    more: rows.length >= MAX_PULL || profileRows.length >= MAX_PULL
       || tasksTruncated || profilesTruncated,
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
  if (t > Date.now() + MAX_SKEW_MS) return now;
  // NORMALIZE to one canonical form. Rows are compared LEXICALLY (that's what
  // makes the composite cursor and the last-writer-wins upserts work), but
  // ISO-8601 has several spellings of the same instant — "+00:00" vs "Z", with or
  // without milliseconds. Storing them verbatim let an older write sort ABOVE a
  // newer one purely on formatting, silently inverting the conflict rule.
  return new Date(t).toISOString();
}

// UTF-8 byte length. `String.length` is UTF-16 code units and under-measures any
// non-ASCII text — the same trap the request-size check fell into.
function byteLength(s) {
  return typeof s === "string" ? new TextEncoder().encode(s).byteLength : 0;
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

// Transactional email via Resend (verification + password reset).
//
// Deliberately the REST API and not the `resend` npm SDK: this Worker has no
// runtime dependencies, and the SDK's whole job here would be one fetch. Same
// reasoning that kept the Apple client-secret JWT hand-rolled before it was
// removed: one fetch does not need a dependency.
//
// ⚠️ NOTHING ABOUT THE MESSAGE IS LOGGED. `to` is a user's email address and the
// body can carry a reset link — a log line with either in it turns the
// observability we enabled into a credential leak and a PII spill. Only the
// status code is ever surfaced.
export async function sendEmail(env, { to, subject, html, text }) {
  if (!env.RESEND_KEY) throw new Error("email_not_configured");
  // Resend's shared `onboarding@resend.dev` sender only delivers to the ACCOUNT
  // OWNER's address. Falling back to it meant a real user could be told "check
  // your inbox" for a reset code that could never arrive — a silent dead end on
  // the one path back into a locked-out account. Demand a verified sender.
  if (!env.EMAIL_FROM) throw new Error("email_from_not_configured");
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.RESEND_KEY}`,
      "Content-Type": "application/json",
    },
    // EMAIL_FROM is config, not code, so moving off Resend's shared testing
    // sender to noreply@<your domain> is a `wrangler secret put`, not a deploy.
    body: JSON.stringify({ from: env.EMAIL_FROM, to: [to], subject, html, text }),
  });
  if (!res.ok) {
    // Status only — the response can echo the recipient back.
    throw new Error(`email_send_failed_${res.status}`);
  }
  return true;
}

// Mint a session for an ALREADY-AUTHENTICATED account.
//
// Shared by every auth route. The device-limit rules and — more importantly —
// the race handling around them are subtle enough that a second copy would drift
// from this one, and the drift would show up as "the one-device rule can be
// beaten by signing in twice quickly", which is exactly the bug the batch below
// exists to prevent.
//
// Returns { ok: true, token, plus } or { ok: false, response } to send as-is.
async function issueSession(userID, deviceId, env) {
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
      return { ok: false, response: json({
        error: "device_limit",
        message: `This account is already signed in on ${MAX_DEVICES} devices. Sign out on one of them first.` }, 409) };
    }
  }
  return { ok: true, token, plus };
}

// Does this account already hold anything? Lets the client tell a NEW account
// (seed from local) from an EXISTING one (pull + reconcile).
//
// PROFILES COUNT TOO. Checking tasks alone reported "new account" for an account
// that already had family members but no live to-dos, so the device skipped
// reconciliation and seeded straight over it.
async function accountHasData(userID, env) {
  const hasTasks = await env.DB.prepare(
    "SELECT 1 FROM tasks WHERE user_id = ? AND deleted_at IS NULL LIMIT 1").bind(userID).first();
  const hasProfiles = await env.DB.prepare(
    "SELECT 1 FROM profiles WHERE user_id = ? AND deleted_at IS NULL LIMIT 1").bind(userID).first();
  return !!(hasTasks || hasProfiles);
}

// ── email + password ────────────────────────────────────────────────────────

// Normalise an address for storage and lookup. Lower-cased and trimmed so
// "Rachel@Example.com " and "rachel@example.com" are one account, not two.
export function normalizeEmail(raw) {
  return String(raw || "").trim().toLowerCase();
}

// Deliberately permissive. Email syntax is famously not a regex, and the real
// proof an address works is that a message to it arrives — so this only rejects
// what is obviously not an address, and verification does the rest.
export function validEmail(raw) {
  const e = normalizeEmail(raw);
  if (e.length < 3 || e.length > 254) return "";
  if (!/^[^\s@]+@[^\s@.]+(\.[^\s@.]+)+$/.test(e)) return "";
  return e;
}

// The CLIENT sends an already-stretched value, so what arrives must look like the
// output of PBKDF2 and nothing else: fixed-length hex. This also stops a hostile
// client shoving a megabyte into the hash function.
export function validDerivedKey(raw) {
  const s = String(raw || "");
  return /^[0-9a-f]{64}$/.test(s) ? s : "";
}

// The stored verifier: HMAC-SHA256(pepper, salt || clientDerivedKey), base64.
//
// One HMAC is microseconds, which is the entire point — see schema.sql. The
// pepper is a Worker SECRET, not a column, so a database leak on its own doesn't
// let an attacker test guesses offline at all: they'd need the secret too.
export async function derivePasswordHash(env, derivedKeyHex, saltB64) {
  // NO FALLBACK, DELIBERATELY. This used to default to a public constant, so a
  // deploy that forgot `wrangler secret put PASSWORD_PEPPER` would keep working
  // while quietly losing the one protection that makes a stolen `accounts` table
  // useless — and nothing would say so. Failing loudly is the only safe choice
  // for a secret whose absence is invisible.
  if (!env.PASSWORD_PEPPER) throw new Error("password_pepper_missing");
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw", enc.encode(env.PASSWORD_PEPPER),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(`${saltB64}:${derivedKeyHex}`));
  return btoa(String.fromCharCode(...new Uint8Array(sig)));
}

// Constant-time compare. `a === b` on secrets leaks their common prefix through
// timing, which is enough to reconstruct a verifier one byte at a time.
export function timingSafeEqual(a, b) {
  const x = String(a), y = String(b);
  if (x.length !== y.length) return false;
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x.charCodeAt(i) ^ y.charCodeAt(i);
  return diff === 0;
}

function randomSaltB64() {
  const b = new Uint8Array(16);
  crypto.getRandomValues(b);
  return btoa(String.fromCharCode(...b));
}

// The floor for client-side stretching. The phone is supposed to run PBKDF2 at
// PW_ITERATIONS; this rejects a client claiming it did far less, which would make
// a stolen hash cheap to attack. It can't PROVE the work was done — only the real
// app is expected here — but it stops an accidental regression shipping silently.
const MIN_PW_ITERATIONS = 100000;

// ── password reset ──────────────────────────────────────────────────────────

const RESET_TTL_MINUTES = 15;
const RESET_MAX_ATTEMPTS = 5;
// Don't let one account be used to flood an inbox.
const RESET_RESEND_COOLDOWN_SECONDS = 60;

// KEYED with the pepper, not a bare SHA-256.
//
// A six-digit code has only a million possibilities, so an unkeyed digest in a
// leaked `password_resets` table is searched in about a second. Keying it means
// the table alone is useless without the Worker secret — the same reasoning as
// the password verifier.
async function resetCodeHash(env, code) {
  return derivePasswordHash(env, "0".repeat(64), `reset:${code}`);
}

// Six digits, uniformly distributed. `crypto.getRandomValues` rather than
// Math.random, which is not a CSPRNG and would make codes predictable.
function newResetCode() {
  const b = new Uint32Array(1);
  crypto.getRandomValues(b);
  return String(b[0] % 1000000).padStart(6, "0");
}

// STEP 1 — ask for a code.
//
// ALWAYS answers 200, whether or not the address is registered. Saying "no such
// account" here would hand over a list of who uses Tadah to anyone willing to
// type addresses — the same enumeration leak the login route refuses.
async function handleResetRequest(request, env) {
  if (!env.DB) return json({ error: "Sync not configured" }, 503);
  if (!env.PASSWORD_PEPPER) {
    return json({ error: "not_configured",
                  message: "Accounts are temporarily unavailable. Please try again later." }, 503);
  }
  await ensureSyncTables(env.DB);
  const read = await readJSON(request);
  if (!read.ok) return read.response;
  const email = validEmail((read.body || {}).email);

  const ok = json({ ok: true }, 200);
  if (!email) return ok;

  const account = await env.DB.prepare(
    "SELECT user_id FROM accounts WHERE email = ?").bind(email).first();
  if (!account) return ok;                       // silently, on purpose

  // Inbox-flood guard. Still answers 200 so the response stays identical for
  // registered and unregistered addresses — it just doesn't send again yet.
  const existing = await env.DB.prepare(
    "SELECT created_at FROM password_resets WHERE user_id = ?").bind(account.user_id).first();
  if (existing && Date.now() - new Date(existing.created_at).getTime()
        < RESET_RESEND_COOLDOWN_SECONDS * 1000) {
    return ok;
  }

  const code = newResetCode();
  const now = new Date();
  const expires = new Date(now.getTime() + RESET_TTL_MINUTES * 60_000);
  // ON CONFLICT REPLACE: a new request invalidates the previous code rather than
  // leaving several live at once.
  await env.DB.prepare(
    `INSERT INTO password_resets (user_id, code_hash, expires_at, attempts, created_at)
     VALUES (?, ?, ?, 0, ?)
     ON CONFLICT(user_id) DO UPDATE SET
       code_hash = excluded.code_hash, expires_at = excluded.expires_at,
       attempts = 0, created_at = excluded.created_at`
  ).bind(account.user_id, await resetCodeHash(env, code), expires.toISOString(), now.toISOString()).run();

  try {
    await sendEmail(env, {
      to: email,
      subject: "Your Tadah password reset code",
      text: `Your Tadah reset code is ${code}. It expires in ${RESET_TTL_MINUTES} minutes.\n\nIf you didn't ask to reset your password, you can ignore this — nothing has changed.`,
      html: `<p>Your Tadah reset code is:</p><p style="font-size:28px;font-weight:600;letter-spacing:4px">${code}</p><p>It expires in ${RESET_TTL_MINUTES} minutes.</p><p>If you didn't ask to reset your password, you can ignore this — nothing has changed.</p>`,
    });
  } catch (e) {
    // The RESPONSE is unchanged by design — reporting "we couldn't send" would
    // confirm the address exists. But swallowing it entirely left a broken mail
    // configuration completely invisible, and the old comment claiming Worker
    // metrics would surface it was simply wrong: a caught exception is not an
    // error event. Log the REASON only — never the address or the code.
    console.error("reset_email_failed", e && e.message ? e.message : "unknown");
  }
  return ok;
}

// STEP 2 — use the code to set a new password.
async function handleResetConfirm(request, env) {
  if (!env.DB) return json({ error: "Sync not configured" }, 503);
  if (!env.PASSWORD_PEPPER) {
    return json({ error: "not_configured",
                  message: "Accounts are temporarily unavailable. Please try again later." }, 503);
  }
  await ensureSyncTables(env.DB);
  const read = await readJSON(request);
  if (!read.ok) return read.response;
  const body = read.body || {};

  const email = validEmail(body.email);
  const code = String(body.code || "").trim();
  const derived = validDerivedKey(body.derivedKey);
  const iterations = Number(body.iterations);
  if (!email || !/^\d{6}$/.test(code) || !derived) return json({ error: "invalid_code" }, 400);
  if (!Number.isInteger(iterations) || iterations < MIN_PW_ITERATIONS) {
    return json({ error: "weak_derivation" }, 400);
  }

  const row = await env.DB.prepare(
    `SELECT a.user_id AS user_id, r.code_hash AS code_hash, r.expires_at AS expires_at,
            r.attempts AS attempts
     FROM accounts a JOIN password_resets r ON r.user_id = a.user_id
     WHERE a.email = ?`).bind(email).first();
  if (!row) return json({ error: "invalid_code" }, 400);

  // Expired or exhausted → burn it. Without the attempt cap, six digits is a
  // million guesses and a patient script.
  if (new Date(row.expires_at).getTime() < Date.now() || row.attempts >= RESET_MAX_ATTEMPTS) {
    await env.DB.prepare("DELETE FROM password_resets WHERE user_id = ?").bind(row.user_id).run();
    return json({ error: "invalid_code" }, 400);
  }

  // CLAIM AN ATTEMPT ATOMICALLY, BEFORE COMPARING.
  //
  // Reading `attempts`, comparing, then incrementing is three steps that two
  // concurrent requests interleave freely — a scripted attacker could fire far
  // more than five guesses through a cap that "passes" for all of them. A
  // conditional UPDATE ... RETURNING makes the increment itself the check, so
  // exactly RESET_MAX_ATTEMPTS guesses can ever be claimed.
  const claimed = await env.DB.prepare(
    `UPDATE password_resets SET attempts = attempts + 1
     WHERE user_id = ? AND attempts < ? RETURNING attempts`
  ).bind(row.user_id, RESET_MAX_ATTEMPTS).first();
  if (!claimed) {
    await env.DB.prepare("DELETE FROM password_resets WHERE user_id = ?").bind(row.user_id).run();
    return json({ error: "invalid_code" }, 400);
  }

  if (!timingSafeEqual(await resetCodeHash(env, code), row.code_hash)) {
    return json({ error: "invalid_code" }, 400);
  }

  const salt = randomSaltB64();
  const hash = await derivePasswordHash(env, derived, salt);
  // One batch: set the password, consume the code, and revoke EVERY session.
  // Revoking matters — a reset is what someone does when they fear the account is
  // compromised, so leaving other devices signed in would defeat the point.
  await env.DB.batch([
    env.DB.prepare(
      "UPDATE accounts SET pw_hash = ?, pw_salt = ?, pw_iterations = ? WHERE user_id = ?"
    ).bind(hash, salt, iterations, row.user_id),
    env.DB.prepare("DELETE FROM password_resets WHERE user_id = ?").bind(row.user_id),
    env.DB.prepare("UPDATE sessions SET revoked = 1 WHERE user_id = ? AND revoked = 0")
      .bind(row.user_id),
  ]);
  return json({ ok: true }, 200);
}

// REGISTER. The password never reaches this Worker: the phone sends a PBKDF2
// output (see schema.sql for why the heavy lifting is client-side).
async function handleEmailRegister(request, env) {
  if (!env.DB) return json({ error: "Sync not configured" }, 503);
  if (!env.PASSWORD_PEPPER) {
    return json({ error: "not_configured",
                  message: "Accounts are temporarily unavailable. Please try again later." }, 503);
  }
  await ensureSyncTables(env.DB);
  const read = await readJSON(request);
  if (!read.ok) return read.response;
  const body = read.body || {};

  const email = validEmail(body.email);
  if (!email) return json({ error: "invalid_email" }, 400);
  const derived = validDerivedKey(body.derivedKey);
  if (!derived) return json({ error: "invalid_credentials" }, 400);
  const iterations = Number(body.iterations);
  if (!Number.isInteger(iterations) || iterations < MIN_PW_ITERATIONS) {
    return json({ error: "weak_derivation" }, 400);
  }
  const deviceId = clamp(body.deviceId);
  if (!deviceId) return json({ error: "Device id required" }, 400);

  const userID = crypto.randomUUID();
  const salt = randomSaltB64();
  const hash = await derivePasswordHash(env, derived, salt);
  const now = new Date().toISOString();

  try {
    await env.DB.prepare(
      "INSERT INTO accounts (user_id, email, pw_hash, pw_salt, pw_iterations, pw_version, verified_at, created_at) VALUES (?, ?, ?, ?, ?, 1, NULL, ?)"
    ).bind(userID, email, hash, salt, iterations, now).run();
  } catch {
    // The UNIQUE index is the real guard: checking "does this email exist?" first
    // and inserting after is not atomic, and two simultaneous registrations would
    // both pass the check. Let the constraint decide.
    return json({ error: "email_taken" }, 409);
  }

  const session = await issueSession(userID, deviceId, env);
  if (!session.ok) return session.response;
  // A brand-new account by definition holds nothing.
  return json({ token: session.token, userID, plus: session.plus, hasServerData: false }, 200);
}

// LOG IN.
async function handleEmailLogin(request, env) {
  if (!env.DB) return json({ error: "Sync not configured" }, 503);
  if (!env.PASSWORD_PEPPER) {
    return json({ error: "not_configured",
                  message: "Accounts are temporarily unavailable. Please try again later." }, 503);
  }
  await ensureSyncTables(env.DB);
  const read = await readJSON(request);
  if (!read.ok) return read.response;
  const body = read.body || {};

  const email = validEmail(body.email);
  const derived = validDerivedKey(body.derivedKey);
  const deviceId = clamp(body.deviceId);
  if (!deviceId) return json({ error: "Device id required" }, 400);

  const row = email
    ? await env.DB.prepare(
        "SELECT user_id, pw_hash, pw_salt FROM accounts WHERE email = ?").bind(email).first()
    : null;

  // ONE reply for every failure, and the HMAC runs even when there is no such
  // account. Otherwise "unknown email" would return faster than "wrong password",
  // and that timing difference alone tells an attacker which addresses are
  // registered — a list of your users, extractable by anyone.
  const computed = await derivePasswordHash(env, derived || "0".repeat(64),
                                            row?.pw_salt || "no-such-account");
  if (!email || !derived || !row || !timingSafeEqual(computed, row.pw_hash)) {
    return json({ error: "invalid_credentials" }, 401);
  }

  const session = await issueSession(row.user_id, deviceId, env);
  if (!session.ok) return session.response;
  return json({
    token: session.token,
    userID: row.user_id,
    plus: session.plus,
    hasServerData: await accountHasData(row.user_id, env),
  }, 200);
}

// A fresh opaque session token (256 bits of randomness, hex).
function newToken() {
  const b = new Uint8Array(32);
  crypto.getRandomValues(b);
  return Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");
}

// (The base64url codec and the PEM→DER reader were removed on 2026-08-16. Their
// only callers were Sign-in-with-Apple JWT decoding and the ES256 client-secret
// minting, both deleted with the route.)

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
  readJSON,
  parseCursor,
  formatCursor,
  validID,
  validStamp,
  sanitizeMessages,
  clamp,
  MAX_MESSAGES,
  MAX_MESSAGE_CHARS,
  MAX_PROFILES,
  FREE_PROFILES,
  MAX_BODY_BYTES,
};
