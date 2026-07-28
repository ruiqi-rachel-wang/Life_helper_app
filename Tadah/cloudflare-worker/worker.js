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

// One-time (per isolate) lazy DDL so the quota table exists without a manual
// migration step. Cheap: runs once per Worker instance, IF NOT EXISTS after.
let usageTableReady = false;

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
