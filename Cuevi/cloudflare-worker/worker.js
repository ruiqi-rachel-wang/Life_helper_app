// Cuevi Worker — AI proxy + anonymous metrics ingest
//
// Two jobs, both POST-only and both gated by the optional X-Cuevi-Token secret:
//   • "/" or /v1/chat/completions  → proxy to OpenAI (keeps the key OFF the phone;
//     the app sends NO key, this Worker adds the secret OPENAI_API_KEY it holds).
//   • POST /events                 → store anonymous tester metrics in D1 (Part 1).
//
// Cost/abuse guardrails (the endpoint URL is discoverable, so these BOUND the
// damage rather than hide the URL):
//   • POST only; shared-secret header required IFF PROXY_TOKEN is set.
//   • AI: model allow-list + a hard max_tokens cap on every request.
//   • /events: capped batch size, every stored string clamped, only known event
//     kinds accepted, INSERT OR IGNORE so re-sends never duplicate.
//   • ALSO add a Cloudflare "Rate limiting rule" on this route in the dashboard,
//     and keep an OpenAI spending cap — those are the real volume/$ ceilings.

const ALLOWED_MODELS = new Set(["gpt-4o", "gpt-4o-mini"]);
const MAX_TOKENS = 2000; // hard ceiling AND the default when the client sends none

// /events guardrails.
const MAX_BATCH = 500;                               // events accepted per request
const VALID_KINDS = new Set(["confirmed", "completed"]);
const MAX_STR = 64;                                  // clamp every stored string

export default {
  async fetch(request, env) {
    if (request.method !== "POST") return json({ error: "POST only" }, 405);

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
