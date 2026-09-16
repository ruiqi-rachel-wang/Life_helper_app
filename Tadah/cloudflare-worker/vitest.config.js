// Route-level Worker tests, run in the REAL workerd runtime with a REAL D1
// binding (@cloudflare/vitest-pool-workers).
//
// The helper tests in worker.test.js cover pure functions and run under plain
// Node. They could never reach routing, auth, D1 transactions, the profile/task
// caps or the deletion race — which is exactly where several shipped bugs lived.
// These tests exercise the handlers themselves.
//
// Storage isolation is handled by the integration; tests that assert on counts
// still scope themselves to their own account id, because state is shared across
// cases within the file.
//
// NOTE on the API: pool-workers 0.21 (Vitest 4) dropped the old
// `@cloudflare/vitest-pool-workers/config` entry point and its
// `defineWorkersConfig` helper. The current shape is plain `defineConfig` with
// TWO pieces wired from the same options: the PLUGIN resolves the virtual
// `cloudflare:test` module (env, createExecutionContext, …), and the POOL runs
// the tests inside workerd.

import { defineConfig } from "vitest/config";
import { cloudflarePool, cloudflareTest } from "@cloudflare/vitest-pool-workers";

// Per-test storage isolation is provided by the integration itself — the old
// `isolatedStorage` / `singleWorker` keys are not current pool options and were
// silently doing nothing.
const workers = {
  miniflare: {
    compatibilityDate: "2026-08-01",
    compatibilityFlags: ["nodejs_compat"],
    d1Databases: { DB: "test-db" },
    // No PROXY_TOKEN here: the shared-secret gate is optional, and leaving it
    // unset lets these tests exercise the routes themselves.
    bindings: {
      APPLE_AUDIENCE: "com.ruiqiwang.cuevi",
      REVENUECAT_SECRET: "test-secret",
      // No fallback exists any more — a missing pepper is a hard 503, which is
      // the point. Tests supply one so they exercise the real path.
      PASSWORD_PEPPER: "test-pepper",
      EMAIL_FROM: "noreply@test.invalid",
      // No phone line in tests: the create path builds and stores everything
      // exactly as in production, then synthesizes the provider's answer.
      CALLE_DRY_RUN: "1",
      CALLE_WEBHOOK_SECRET: "test-webhook-secret",
    },
    // Intercept ALL outbound fetch, so tests never touch the network and — more
    // importantly — so the tier is KNOWN.
    //
    // Without this, RevenueCat is unreachable, checkPlus reports `known: false`,
    // and every cap test silently runs against the PLUS ceiling. That is how the
    // first profile-cap test came to prove nothing: with a cap of 8 and one seeded
    // profile, even the old (wrong) count of 2 passed. Returning a subscriber with
    // no entitlements pins the FREE tier, which is where the caps actually bite.
    outboundService: (request) => {
      const url = new URL(request.url);
      if (url.hostname === "api.revenuecat.com") {
        if (request.method === "DELETE") return new Response("{}", { status: 200 });
        // One reserved subscriber id reports PLUS, so the Plus-gated routes
        // (/actions) can be tested at all. Everyone else stays on the free tier,
        // which is where the profile/task caps bite.
        if (url.pathname.endsWith("/plus-test-user")) {
          return Response.json({ subscriber: { entitlements: { "Tadah Pro": { expires_date: null } } } });
        }
        // A subscriber whose renewal payment is BEING RETRIED: RevenueCat puts
        // `expires_date` in the past and the grace period in the future, and its
        // SDK still reports the entitlement as active. The Worker must agree, or
        // it tells a paying customer to buy what they already have.
        const hour = 60 * 60 * 1000;
        if (url.pathname.endsWith("/grace-test-user")) {
          return Response.json({ subscriber: { entitlements: { "Tadah Pro": {
            expires_date: new Date(Date.now() - hour).toISOString(),
            grace_period_expires_date: new Date(Date.now() + 12 * hour).toISOString(),
          } } } });
        }
        // Genuinely lapsed: the grace period has run out too. Still free.
        if (url.pathname.endsWith("/lapsed-test-user")) {
          return Response.json({ subscriber: { entitlements: { "Tadah Pro": {
            expires_date: new Date(Date.now() - 48 * hour).toISOString(),
            grace_period_expires_date: new Date(Date.now() - hour).toISOString(),
          } } } });
        }
        return Response.json({ subscriber: { entitlements: {} } });   // free tier
      }
      // The calling provider. Tests run with CALLE_DRY_RUN, so this should never
      // be reached; if a test ever does reach it, failing loudly is correct.
      if (url.hostname === "api.heycall-e.com") {
        return new Response(JSON.stringify({ error: { code: "should_not_be_called" } }), { status: 500 });
      }
      return new Response("unexpected outbound request", { status: 500 });
    },
  },
};

export default defineConfig({
  plugins: [cloudflareTest(workers)],
  test: {
    include: ["routes.test.js"],
    pool: cloudflarePool(workers),
  },
});
