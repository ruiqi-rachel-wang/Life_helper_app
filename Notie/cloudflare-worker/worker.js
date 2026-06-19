// Plaino AI proxy — Cloudflare Worker
//
// Purpose: keep the OpenAI key OFF the phone. The app sends its chat-completion
// request here WITHOUT any key; this Worker adds the secret key it holds and
// forwards to OpenAI, then streams the response back. The key lives only as a
// Worker secret (set with `wrangler secret put OPENAI_API_KEY`), never in the app.
//
// Guardrails (cheap defenses — the app also rate-limits scans client-side):
//   • POST only, to /v1/chat/completions.
//   • Model allow-list, so a leaked endpoint can't run an arbitrary expensive model.
//   • A hard cap on max_tokens.
// For real abuse protection, add a Cloudflare "Rate limiting rule" in the
// dashboard (no code needed) once you have traffic.

const ALLOWED_MODELS = new Set(["gpt-4o", "gpt-4o-mini"]);
const MAX_TOKENS = 1500;

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return json({ error: "POST only" }, 405);
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: "Invalid JSON" }, 400);
    }

    if (!ALLOWED_MODELS.has(body.model)) {
      return json({ error: "Model not allowed" }, 400);
    }
    if (typeof body.max_tokens === "number") {
      body.max_tokens = Math.min(body.max_tokens, MAX_TOKENS);
    }

    const upstream = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${env.OPENAI_API_KEY}`,
      },
      body: JSON.stringify(body),
    });

    // Pass the OpenAI response straight through (status + body) so the app's
    // existing parsing and error handling work unchanged.
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
