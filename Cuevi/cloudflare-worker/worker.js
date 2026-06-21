// Cuevi AI proxy — Cloudflare Worker
//
// Purpose: keep the OpenAI key OFF the phone. The app sends its chat-completion
// request here WITHOUT the OpenAI key; this Worker adds the secret key it holds
// and forwards to OpenAI. The OpenAI key lives only as a Worker secret
// (`wrangler secret put OPENAI_API_KEY`), never in the app.
//
// Cost/abuse guardrails (the endpoint URL is discoverable, so these BOUND the
// damage rather than hide the URL):
//   • POST only, to "/" or /v1/chat/completions.
//   • Optional shared secret: if the PROXY_TOKEN secret is set, every request
//     must send a matching `X-Cuevi-Token` header (deters casual abuse).
//   • Model allow-list — a leaked endpoint can't run an arbitrary pricey model.
//   • max_tokens is capped on EVERY request, even when the client omits it, so a
//     forged request can't ask for a huge (expensive) completion.
//   • ALSO add a Cloudflare "Rate limiting rule" on this route in the dashboard,
//     and keep an OpenAI spending cap — those are the real volume/$ ceilings.

const ALLOWED_MODELS = new Set(["gpt-4o", "gpt-4o-mini"]);
const MAX_TOKENS = 2000; // hard ceiling AND the default when the client sends none

export default {
  async fetch(request, env) {
    if (request.method !== "POST") return json({ error: "POST only" }, 405);

    const path = new URL(request.url).pathname;
    if (path !== "/" && path !== "/v1/chat/completions") {
      return json({ error: "Not found" }, 404);
    }

    // Require the shared secret IFF one is configured (set it with
    // `wrangler secret put PROXY_TOKEN`, and put the same value in the app).
    if (env.PROXY_TOKEN && request.headers.get("X-Cuevi-Token") !== env.PROXY_TOKEN) {
      return json({ error: "Unauthorized" }, 401);
    }

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
  },
};

function json(obj, status) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
