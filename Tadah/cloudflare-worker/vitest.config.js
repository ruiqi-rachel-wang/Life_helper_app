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
        return Response.json({ subscriber: { entitlements: {} } });   // free tier
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
