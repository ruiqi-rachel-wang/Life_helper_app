// Route-level Worker tests — real workerd runtime, real D1 binding.
//
// These reach the layer worker.test.js structurally cannot: routing, the
// shared-secret gate, session validation, the D1 writes, the profile/task caps,
// and the account-deletion race. Several shipped bugs lived here precisely
// because nothing automated exercised it.
//
// Run with `npm run test:routes` (or `npm test`, which runs both suites).

import { env, createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { describe, it, expect, beforeEach } from "vitest";
import worker, { IP_DAY_LIMIT, GLOBAL_DAY_LIMIT, hashedIP, ipDayScope, ipMonthScope } from "./worker.js";

const USER = "apple-sub-test-user";
const OTHER = "apple-sub-other-user";
const TOKEN = "session-token-aaaaaaaaaaaaaaaaaaaaaaaa";
const uuid = (n) => `${String(n).padStart(8, "0")}-1111-1111-1111-111111111111`;

async function call(path, { body, headers = {}, method = "POST" } = {}) {
  const request = new Request(`https://worker.test${path}`, {
    method,
    headers: { "Content-Type": "application/json", ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const ctx = createExecutionContext();
  const response = await worker.fetch(request, env, ctx);
  await waitOnExecutionContext(ctx);
  let json = null;
  try { json = await response.clone().json(); } catch { /* not JSON */ }
  return { status: response.status, body: json };
}

// The Worker lazily creates its tables, but seeding a session directly is the
// only way to test /sync without a real Apple token.
async function seedSchema() {
  await env.DB.exec("CREATE TABLE IF NOT EXISTS tasks (user_id TEXT NOT NULL, item_id TEXT NOT NULL, payload TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT, PRIMARY KEY (user_id, item_id))");
  await env.DB.exec("CREATE TABLE IF NOT EXISTS sessions (token TEXT PRIMARY KEY, user_id TEXT NOT NULL, device_id TEXT NOT NULL, created_at TEXT NOT NULL, last_seen TEXT NOT NULL, revoked INTEGER NOT NULL DEFAULT 0, plus_checked_at TEXT)");
  await env.DB.exec("CREATE TABLE IF NOT EXISTS profiles (user_id TEXT NOT NULL, profile_id TEXT NOT NULL, payload TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT, PRIMARY KEY (user_id, profile_id))");
  await env.DB.exec("CREATE TABLE IF NOT EXISTS accounts (user_id TEXT PRIMARY KEY, email TEXT NOT NULL, pw_hash TEXT NOT NULL, pw_salt TEXT NOT NULL, pw_iterations INTEGER NOT NULL, pw_version INTEGER NOT NULL DEFAULT 1, verified_at TEXT, created_at TEXT NOT NULL)");
  await env.DB.exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_accounts_email ON accounts(email)");
  await env.DB.exec("CREATE TABLE IF NOT EXISTS password_resets (user_id TEXT PRIMARY KEY, code_hash TEXT NOT NULL, expires_at TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL)");
  await env.DB.exec("CREATE TABLE IF NOT EXISTS account_deletions (user_id TEXT PRIMARY KEY, revenuecat_deleted INTEGER NOT NULL DEFAULT 0, started_at TEXT NOT NULL)");
  await env.DB.exec("CREATE TABLE IF NOT EXISTS ai_usage (install_id TEXT NOT NULL, period TEXT NOT NULL, count INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (install_id, period))");
  await env.DB.exec("CREATE TABLE IF NOT EXISTS events (event_id TEXT PRIMARY KEY, install_id TEXT NOT NULL, kind TEXT NOT NULL, source TEXT, on_time INTEGER, item_id TEXT, occurred_at TEXT NOT NULL, app_version TEXT, received_at TEXT)");
}

async function seedSession(token = TOKEN, user = USER, revoked = 0) {
  const now = new Date().toISOString();
  await env.DB.prepare(
    "INSERT OR REPLACE INTO sessions (token, user_id, device_id, created_at, last_seen, revoked) VALUES (?, ?, ?, ?, ?, ?)"
  ).bind(token, user, "device-1", now, now, revoked).run();
}

const stamp = (iso) => iso;
const change = (id, updatedAt, payload = '{"title":"x"}') => ({ id, payload, updatedAt });

// Bulk-seed live tasks straight into D1 (not through /sync, which is batch-capped
// at 25). Needed to test the cap arithmetic AT the ceiling, where it matters.
async function seedTasks(user, count, from = 1000) {
  const stmt = env.DB.prepare(
    "INSERT INTO tasks (user_id, item_id, payload, updated_at, deleted_at) VALUES (?, ?, ?, ?, NULL)");
  const rows = Array.from({ length: count }, (_, i) =>
    stmt.bind(user, uuid(from + i), '{"title":"seed"}', "2026-08-01T00:00:00.000Z"));
  for (let i = 0; i < rows.length; i += 50) await env.DB.batch(rows.slice(i, i + 50));
}

beforeEach(async () => {
  await seedSchema();
});

// ── routing + method gates ───────────────────────────────────────────────────

describe("routing", () => {
  it("rejects non-POST", async () => {
    expect((await call("/sync", { method: "GET" })).status).toBe(405);
  });

  it("404s an unknown route", async () => {
    expect((await call("/nope", { body: {} })).status).toBe(404);
  });

  it("401s /sync without a session", async () => {
    const r = await call("/sync", { body: { since: "", changes: [], deletes: [] } });
    expect(r.status).toBe(401);
  });

  it("401s /sync with a REVOKED session", async () => {
    await seedSession("revoked-token", USER, 1);
    const r = await call("/sync", {
      body: { since: "", changes: [], deletes: [] },
      headers: { "X-Tadah-Session": "revoked-token" },
    });
    expect(r.status).toBe(401);
  });

  it("404s /auth/apple now that Sign in with Apple is removed", async () => {
    // Pinned deliberately: the route is GONE, not merely unused. A comment in
    // wrangler.toml claimed as much while the handler was still routed, which is
    // the sort of drift that leaves dead auth surface live for months.
    const r = await call("/auth/apple", {
      body: { idToken: "not.a.token", deviceId: "d1", nonce: "abc" },
    });
    expect(r.status).toBe(404);
  });
});

// ── sync writes ──────────────────────────────────────────────────────────────

describe("sync", () => {
  it("stores a change and returns it to a second device", async () => {
    await seedSession();
    const push = await call("/sync", {
      headers: { "X-Tadah-Session": TOKEN },
      body: { since: "", changes: [change(uuid(1), "2026-08-10T10:00:00.000Z")], deletes: [] },
    });
    expect(push.status).toBe(200);

    const pull = await call("/sync", {
      headers: { "X-Tadah-Session": TOKEN },
      body: { since: "", changes: [], deletes: [] },
    });
    expect(pull.status).toBe(200);
    expect(pull.body.changes.map((c) => c.id)).toContain(uuid(1));
  });

  it("applies last-writer-wins: a stale change does not overwrite a newer row", async () => {
    await seedSession();
    await call("/sync", {
      headers: { "X-Tadah-Session": TOKEN },
      body: { since: "", changes: [change(uuid(2), "2026-08-10T12:00:00.000Z", '{"title":"new"}')], deletes: [] },
    });
    await call("/sync", {
      headers: { "X-Tadah-Session": TOKEN },
      body: { since: "", changes: [change(uuid(2), "2026-08-10T09:00:00.000Z", '{"title":"stale"}')], deletes: [] },
    });
    const row = await env.DB.prepare("SELECT payload FROM tasks WHERE user_id = ? AND item_id = ?")
      .bind(USER, uuid(2)).first();
    expect(row.payload).toBe('{"title":"new"}');
  });

  it("rejects a malformed id rather than storing it", async () => {
    await seedSession();
    const r = await call("/sync", {
      headers: { "X-Tadah-Session": TOKEN },
      body: { since: "", changes: [change("'; DROP TABLE tasks; --", "2026-08-10T10:00:00.000Z")], deletes: [] },
    });
    expect(r.status).toBe(400);
  });

  it("413s an oversized batch", async () => {
    await seedSession();
    const many = Array.from({ length: 30 }, (_, i) => change(uuid(100 + i), "2026-08-10T10:00:00.000Z"));
    const r = await call("/sync", {
      headers: { "X-Tadah-Session": TOKEN },
      body: { since: "", changes: many, deletes: [] },
    });
    expect(r.status).toBe(413);
  });

  // One account must never see another's rows.
  it("scopes rows to the authenticated user", async () => {
    await seedSession();
    await seedSession("other-token", OTHER);
    await call("/sync", {
      headers: { "X-Tadah-Session": TOKEN },
      body: { since: "", changes: [change(uuid(3), "2026-08-10T10:00:00.000Z")], deletes: [] },
    });
    const pull = await call("/sync", {
      headers: { "X-Tadah-Session": "other-token" },
      body: { since: "", changes: [], deletes: [] },
    });
    expect(pull.body.changes).toHaveLength(0);
  });
});

// ── the account-deletion race ────────────────────────────────────────────────

describe("deletion race", () => {
  // A DETERMINISTIC race, driven entirely through the production handler.
  //
  // The earlier version of this test copied the conditional SQL into the test and
  // ran it directly, which proved the statement worked but not that the Worker
  // uses it. This one exploits the handler's real order of operations:
  //
  //     resolveSession(...)   ← authenticates
  //     readJSON(request)     ← awaits the BODY
  //     ...batch of writes
  //
  // By feeding the request a body stream we control, we can let it authenticate,
  // delete the session while it waits for the body, then finish the body. The
  // write therefore executes with a session that was valid at auth time and gone
  // by write time — exactly the window account deletion opens.
  it("a sync authorized before deletion cannot write after it", async () => {
    const user = "apple-sub-gated";
    const token = "session-token-gated";
    await seedSession(token, user);

    const payload = JSON.stringify({
      since: "",
      changes: [change(uuid(50), "2026-08-10T10:00:00.000Z")],
      deletes: [],
    });
    const head = payload.slice(0, 10);
    const tail = payload.slice(10);

    // Synchronised on the STREAM, not on a timer. `reachedBody` resolves the
    // moment the handler asks for the second chunk, which can only happen after
    // it has authenticated — so there is no sleep to lose a race with, and a slow
    // machine can't accidentally delete the session before authentication and
    // "pass" without exercising anything.
    let reachedBody, releaseTail;
    const atBody = new Promise((resolve) => { reachedBody = resolve; });
    const gate = new Promise((resolve) => { releaseTail = resolve; });
    let sentHead = false;
    const body = new ReadableStream({
      async pull(controller) {
        if (!sentHead) {
          sentHead = true;
          controller.enqueue(new TextEncoder().encode(head));
          return;
        }
        reachedBody();                    // handler is past auth, waiting on us
        await gate;                       // held open until the session is deleted
        controller.enqueue(new TextEncoder().encode(tail));
        controller.close();
      },
    });

    const request = new Request("https://worker.test/sync", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Tadah-Session": token },
      body,
      duplex: "half",
    });
    const ctx = createExecutionContext();
    const inFlight = worker.fetch(request, env, ctx);

    // Wait for the handler to actually reach the body read (i.e. it has already
    // authenticated), THEN pull the session out from under it.
    await atBody;
    await env.DB.prepare("DELETE FROM sessions WHERE token = ?").bind(token).run();
    releaseTail();

    const response = await inFlight;
    await waitOnExecutionContext(ctx);

    // Whatever the handler returns, the invariant is the same: nothing was
    // written for an account whose session had been deleted.
    // The handler authenticated successfully, so it completes normally — the
    // session-conditional writes are what make the batch a no-op. Asserting the
    // exact status matters: accepting "200 or 401" would also pass if the session
    // had been deleted BEFORE authentication, which is a different (already
    // covered) scenario and not this race.
    expect(response.status).toBe(200);
    const n = await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM tasks WHERE user_id = ?").bind(user).first();
    expect(n.n).toBe(0);
  });

  // Belt and braces: an already-authorized token is refused outright too.
  it("401s a request whose session was deleted before it arrived", async () => {
    const token = "session-token-gone";
    await seedSession(token, "apple-sub-gone");
    await env.DB.prepare("DELETE FROM sessions WHERE token = ?").bind(token).run();
    const r = await call("/sync", {
      headers: { "X-Tadah-Session": token },
      body: { since: "", changes: [change(uuid(43), "2026-08-10T10:00:00.000Z")], deletes: [] },
    });
    expect(r.status).toBe(401);
  });
});

// ── paging ───────────────────────────────────────────────────────────────────

describe("byte-paged pull", () => {
  // A page truncated for SIZE must report `more: true`. Inferring it from bytes
  // spent was wrong — the SQL stops at the last row that FITS, so `spent` sits
  // below the budget and truncation looked like completion, stranding the tail
  // until some later lifecycle sync.
  it("reports more:true when a page is cut short for size, and pages to completion", async () => {
    const user = "apple-sub-bigdata";
    const token = "session-token-bigdata";
    await seedSession(token, user);

    // 50 rows × ~100 KB — comfortably past the 4 MB response budget.
    const payload = "x".repeat(100_000);
    const stmt = env.DB.prepare(
      "INSERT INTO tasks (user_id, item_id, payload, updated_at, deleted_at) VALUES (?, ?, ?, ?, NULL)");
    await env.DB.batch(Array.from({ length: 50 }, (_, i) =>
      stmt.bind(user, uuid(500 + i), payload, `2026-08-10T10:00:00.${String(i).padStart(3, "0")}Z`)));

    const first = await call("/sync", {
      headers: { "X-Tadah-Session": token },
      body: { since: "", changes: [], deletes: [] },
    });
    expect(first.status).toBe(200);
    expect(first.body.changes.length).toBeGreaterThan(0);
    expect(first.body.changes.length).toBeLessThan(50);     // truncated for size
    expect(first.body.more).toBe(true);                     // …and says so

    // Follow the cursor: the remainder arrives, and nothing is skipped.
    const second = await call("/sync", {
      headers: { "X-Tadah-Session": token },
      body: { since: first.body.cursor, changes: [], deletes: [] },
    });
    expect(second.status).toBe(200);
    expect(first.body.changes.length + second.body.changes.length).toBe(50);
    expect(second.body.more).toBe(false);

    const ids = new Set([...first.body.changes, ...second.body.changes].map((c) => c.id));
    expect(ids.size).toBe(50);                              // no duplicates, none lost
  });
});

// ── caps: the arithmetic, on the FREE tier ───────────────────────────────────
// (vitest.config stubs RevenueCat to a subscriber with no entitlements, so the
// tier is KNOWN and FREE. Without that stub the tier is unknown, the Plus cap
// applies, and none of these assertions would be meaningful.)

describe("cap arithmetic", () => {
  // STORAGE IS NOT TIER-GATED — see worker.js. A free account may HOLD several
  // profiles (from a lapsed subscription, or from the deliberate fail-open while
  // RevenueCat is unreachable); the app hides them, so it looks like one list.
  // Rejecting them here only broke sync for real people, and took their TASKS
  // down with it.
  it("a free account can store a second profile instead of 409-ing forever", async () => {
    const user = "apple-sub-freecap";
    const token = "session-token-freecap";
    await seedSession(token, user);
    await env.DB.prepare(
      "INSERT INTO profiles (user_id, profile_id, payload, updated_at, deleted_at) VALUES (?, ?, ?, ?, NULL)"
    ).bind(user, uuid(60), '{"name":"Me","isOwner":true}', "2026-08-10T09:00:00.000Z").run();

    const r = await call("/sync", {
      headers: { "X-Tadah-Session": token },
      body: {
        since: "", changes: [change(uuid(64), "2026-08-10T10:00:00.000Z")], deletes: [],
        profiles: [{ id: uuid(61), payload: '{"name":"Mom"}', updatedAt: "2026-08-10T10:00:00.000Z" }],
        profileDeletes: [],
      },
    });
    expect(r.status).toBe(200);

    // And crucially the TASK in the same request landed — the old behaviour held
    // ordinary to-dos hostage to a profile-count rule they had nothing to do with.
    const task = await env.DB.prepare(
      "SELECT 1 AS ok FROM tasks WHERE user_id = ? AND item_id = ?").bind(user, uuid(64)).first();
    expect(task).toBeTruthy();
  });

  // The ceiling that remains is anti-abuse, not a tier check.
  it("still refuses to store more than the absolute maximum", async () => {
    const user = "apple-sub-ceiling";
    const token = "session-token-ceiling";
    await seedSession(token, user);
    const stmt = env.DB.prepare(
      "INSERT INTO profiles (user_id, profile_id, payload, updated_at, deleted_at) VALUES (?, ?, ?, ?, NULL)");
    await env.DB.batch(Array.from({ length: 8 }, (_, i) =>
      stmt.bind(user, uuid(500 + i), '{"name":"P"}', "2026-08-10T09:00:00.000Z")));

    const r = await call("/sync", {
      headers: { "X-Tadah-Session": token },
      body: {
        since: "", changes: [], deletes: [],
        profiles: [{ id: uuid(520), payload: '{"name":"Ninth"}', updatedAt: "2026-08-11T10:00:00.000Z" }],
        profileDeletes: [],
      },
    });
    expect(r.status).toBe(409);
    expect(r.body.error).toBe("profile_limit");
    expect(r.body.limit).toBe(8);
  });

  // THE LAPSED-PLUS FAMILY. Someone who had 3 profiles on Plus drops to free,
  // where the cap is 1. They are now permanently ABOVE the cap through no action
  // of their own. Blocking on the final total alone meant every profile push —
  // including a plain rename — returned 409, and since this route rejects the
  // WHOLE request, their TASKS stopped syncing too. The cap must only stop
  // growth.
  it("an account already over the cap can still edit the profiles it has", async () => {
    const user = "apple-sub-lapsed-plus";
    const token = "session-token-lapsed";
    await seedSession(token, user);
    const stmt = env.DB.prepare(
      "INSERT INTO profiles (user_id, profile_id, payload, updated_at, deleted_at) VALUES (?, ?, ?, ?, NULL)");
    await env.DB.batch([
      stmt.bind(user, uuid(70), '{"name":"Me","isOwner":true}', "2026-08-10T09:00:00.000Z"),
      stmt.bind(user, uuid(71), '{"name":"Mom"}', "2026-08-10T09:00:00.000Z"),
      stmt.bind(user, uuid(72), '{"name":"Dad"}', "2026-08-10T09:00:00.000Z"),
    ]);

    // A RENAME of one they already have, alongside an ordinary task edit.
    const r = await call("/sync", {
      headers: { "X-Tadah-Session": token },
      body: {
        since: "",
        changes: [change(uuid(73), "2026-08-11T10:00:00.000Z")],
        deletes: [],
        profiles: [{ id: uuid(71), payload: '{"name":"Mum"}', updatedAt: "2026-08-11T10:00:00.000Z" }],
        profileDeletes: [],
      },
    });
    expect(r.status).toBe(200);

    // The rename landed, and the task rode along instead of being rejected with it.
    const renamed = await env.DB.prepare(
      "SELECT payload FROM profiles WHERE user_id = ? AND profile_id = ?"
    ).bind(user, uuid(71)).first();
    expect(renamed.payload).toContain("Mum");
    const task = await env.DB.prepare(
      "SELECT 1 AS ok FROM tasks WHERE user_id = ? AND item_id = ?"
    ).bind(user, uuid(73)).first();
    expect(task).toBeTruthy();
  });

  // THE OWNER-MIGRATION CASE. The canonical owner and a tombstone for the old
  // random-id owner arrive in ONE request. Counting the old profile as still live
  // gave a free account 2 against a cap of 1 and a 409 the migration could never
  // get past — on exactly the accounts that need it.
  it("a migration that replaces the owner in one request is not blocked", async () => {
    const user = "apple-sub-migrating-user";
    const token = "session-token-migration";
    await seedSession(token, user);

    const oldOwner = uuid(20), newOwner = uuid(21);
    await env.DB.prepare(
      "INSERT INTO profiles (user_id, profile_id, payload, updated_at, deleted_at) VALUES (?, ?, ?, ?, NULL)"
    ).bind(user, oldOwner, '{"name":"Jing","isOwner":true}', "2026-08-10T09:00:00.000Z").run();

    const r = await call("/sync", {
      headers: { "X-Tadah-Session": token },
      body: {
        since: "", changes: [], deletes: [],
        profiles: [{ id: newOwner, payload: '{"name":"Jing","isOwner":true}', updatedAt: "2026-08-10T10:00:00.000Z" }],
        profileDeletes: [{ id: oldOwner, deletedAt: "2026-08-10T10:00:00.000Z" }],
      },
    });
    expect(r.status).toBe(200);

    const live = await env.DB.prepare(
      "SELECT profile_id FROM profiles WHERE user_id = ? AND deleted_at IS NULL"
    ).bind(user).all();
    expect(live.results.map((row) => row.profile_id)).toEqual([newOwner]);
  });

  // A STALE update for a profile the server already tombstoned must not count as
  // a new profile — its upsert loses LWW and revives nothing. Counting it wedged
  // a free account behind a permanent 409 it could never clear.
  it("a stale update to a tombstoned profile does not consume cap", async () => {
    const user = "apple-sub-stalecap";
    const token = "session-token-stalecap";
    await seedSession(token, user);
    // Owner (live) + an old member the server has already tombstoned NEWER.
    await env.DB.batch([
      env.DB.prepare("INSERT INTO profiles (user_id, profile_id, payload, updated_at, deleted_at) VALUES (?, ?, ?, ?, NULL)")
        .bind(user, uuid(70), '{"name":"Me","isOwner":true}', "2026-08-10T09:00:00.000Z"),
      env.DB.prepare("INSERT INTO profiles (user_id, profile_id, payload, updated_at, deleted_at) VALUES (?, ?, '', ?, ?)")
        .bind(user, uuid(71), "2026-08-10T12:00:00.000Z", "2026-08-10T12:00:00.000Z"),
    ]);

    const r = await call("/sync", {
      headers: { "X-Tadah-Session": token },
      body: {
        since: "", changes: [], deletes: [],
        // Older than the tombstone → loses LWW → not a new profile.
        profiles: [{ id: uuid(71), payload: '{"name":"Mom"}', updatedAt: "2026-08-10T10:00:00.000Z" }],
        profileDeletes: [],
      },
    });
    expect(r.status).toBe(200);
  });

  // AT THE CEILING, which is the only place this arithmetic matters. Seeding one
  // task against a ceiling of 200 proved nothing — the old broken implementation
  // passed it too. 200 live tasks, then swap one out for one in: the delete frees
  // its slot, so the request must be accepted and the count must stay at 200.
  it("a winning delete in the same request frees a task slot, at the ceiling", async () => {
    const user = "apple-sub-atceiling";
    const token = "session-token-atceiling";
    await seedSession(token, user);
    await seedTasks(user, 200);

    const doomed = uuid(1000);          // the first seeded id
    const r = await call("/sync", {
      headers: { "X-Tadah-Session": token },
      body: {
        since: "",
        changes: [change(uuid(2000), "2026-08-10T12:00:00.000Z")],
        deletes: [{ id: doomed, deletedAt: "2026-08-10T12:00:00.000Z" }],
      },
    });
    expect(r.status).toBe(200);

    const n = await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM tasks WHERE user_id = ? AND deleted_at IS NULL").bind(user).first();
    expect(n.n).toBe(200);
  });

  // The other side of the ceiling: an extra task with nothing freed is refused.
  it("adding past the ceiling is refused", async () => {
    const user = "apple-sub-overceiling";
    const token = "session-token-overceiling";
    await seedSession(token, user);
    await seedTasks(user, 200);

    const r = await call("/sync", {
      headers: { "X-Tadah-Session": token },
      body: { since: "", changes: [change(uuid(3000), "2026-08-10T12:00:00.000Z")], deletes: [] },
    });
    expect(r.status).toBe(409);
    expect(r.body.error).toBe("task_limit");
  });

  // A STALE update to an already-tombstoned task revives nothing, so at the
  // ceiling it must not be counted as an extra live task and must not 409.
  it("a stale update to a tombstoned task does not consume the ceiling", async () => {
    const user = "apple-sub-stale-task";
    const token = "session-token-stale-task";
    await seedSession(token, user);
    await seedTasks(user, 200);

    const dead = uuid(4000);
    await env.DB.prepare(
      "INSERT INTO tasks (user_id, item_id, payload, updated_at, deleted_at) VALUES (?, ?, '', ?, ?)"
    ).bind(user, dead, "2026-08-10T12:00:00.000Z", "2026-08-10T12:00:00.000Z").run();

    const r = await call("/sync", {
      headers: { "X-Tadah-Session": token },
      // Older than the tombstone → loses LWW → not a live task.
      body: { since: "", changes: [change(dead, "2026-08-10T09:00:00.000Z")], deletes: [] },
    });
    expect(r.status).toBe(200);
  });

  // A TIE between a change and a delete for the same id resolves to the DELETE.
  //
  // This asserts the STORED RESULT, not just a 200. Checking only the status let
  // a real divergence hide: the preflight counted the id as deleted while the
  // database (changes first, strict `>` on conflict) actually kept it live — so a
  // request could pass the cap check and still leave 201 live rows. The write now
  // applies deletions first, and this pins that.
  it("a same-timestamp create and delete ends up tombstoned, and stays capped", async () => {
    const user = "apple-sub-tie";
    const token = "session-token-tie";
    await seedSession(token, user);
    await seedTasks(user, 200);

    const fresh = uuid(6000);
    const at = "2026-08-10T10:00:00.000Z";
    const r = await call("/sync", {
      headers: { "X-Tadah-Session": token },
      body: { since: "", changes: [change(fresh, at)], deletes: [{ id: fresh, deletedAt: at }] },
    });
    expect(r.status).toBe(200);

    const row = await env.DB.prepare(
      "SELECT deleted_at FROM tasks WHERE user_id = ? AND item_id = ?").bind(user, fresh).first();
    expect(row?.deleted_at).toBeTruthy();          // tombstoned, exactly as preflight assumed

    const n = await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM tasks WHERE user_id = ? AND deleted_at IS NULL").bind(user).first();
    expect(n.n).toBe(200);                          // never 201
  });

  // The same trick on the profile side bypassed the profile cap. Free tier = 1
  // profile, so an account already holding its owner must not be able to smuggle
  // a second one in by pairing it with a same-stamp delete.
  it("a same-timestamp profile create and delete ends up tombstoned, and stays capped", async () => {
    const user = "apple-sub-tie-profile";
    const token = "session-token-tie-profile";
    await seedSession(token, user);
    await env.DB.prepare(
      "INSERT INTO profiles (user_id, profile_id, payload, updated_at, deleted_at) VALUES (?, ?, ?, ?, NULL)"
    ).bind(user, uuid(6100), '{"name":"Me","isOwner":true}', "2026-08-10T09:00:00.000Z").run();

    const fresh = uuid(6101);
    const at = "2026-08-10T10:00:00.000Z";
    const r = await call("/sync", {
      headers: { "X-Tadah-Session": token },
      body: {
        since: "", changes: [], deletes: [],
        profiles: [{ id: fresh, payload: '{"name":"Mom"}', updatedAt: at }],
        profileDeletes: [{ id: fresh, deletedAt: at }],
      },
    });
    expect(r.status).toBe(200);

    const row = await env.DB.prepare(
      "SELECT deleted_at FROM profiles WHERE user_id = ? AND profile_id = ?").bind(user, fresh).first();
    expect(row?.deleted_at).toBeTruthy();

    const live = await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM profiles WHERE user_id = ? AND deleted_at IS NULL").bind(user).first();
    expect(live.n).toBe(1);                         // the owner only — cap intact
  });

  // An id in BOTH arrays with the delete newer ends up tombstoned, so it must not
  // be counted as live. Counting by pass order returned a 409 for a request that
  // would have stored nothing.
  it("an id created and deleted in one request is not counted as live", async () => {
    const user = "apple-sub-createdelete";
    const token = "session-token-createdelete";
    await seedSession(token, user);
    await seedTasks(user, 200);

    const fresh = uuid(5000);
    const r = await call("/sync", {
      headers: { "X-Tadah-Session": token },
      body: {
        since: "",
        changes: [change(fresh, "2026-08-10T10:00:00.000Z")],
        deletes: [{ id: fresh, deletedAt: "2026-08-10T11:00:00.000Z" }],   // delete wins
      },
    });
    expect(r.status).toBe(200);

    const n = await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM tasks WHERE user_id = ? AND deleted_at IS NULL").bind(user).first();
    expect(n.n).toBe(200);
  });
});

// ── AI proxy guards ──────────────────────────────────────────────────────────

describe("AI proxy", () => {
  it("rejects a disallowed model before spending anything", async () => {
    const r = await call("/", {
      headers: { "X-Cuevi-Install": "install-abcdefgh" },
      body: { model: "gpt-4-turbo", messages: [{ role: "user", content: "hi" }] },
    });
    expect(r.status).toBe(400);
    expect(r.body.error).toBe("Model not allowed");
  });

  it("rejects image/multimodal content", async () => {
    const r = await call("/", {
      headers: { "X-Cuevi-Install": "install-abcdefgh" },
      body: {
        model: "gpt-5-mini",
        messages: [{ role: "user", content: [{ type: "image_url", image_url: { url: "https://x/y" } }] }],
      },
    });
    expect(r.status).toBe(400);
  });
});

// ── AI spend ceilings ────────────────────────────────────────────────────────
//
// The per-install quota is keyed on X-Cuevi-Install, a header the CLIENT sends,
// and the proxy token that gates this route ships inside the app — so it must be
// assumed public. Anyone holding both can send a fresh install id per request and
// get a fresh budget every time. These two ceilings are the ones a caller cannot
// rotate their way out of, and they are the last thing between a leaked token and
// a real credit card, so they get tests that actually push them over.
//
// Both are driven by seeding `ai_usage` directly: the quota check runs BEFORE the
// upstream OpenAI call, so a request that trips a ceiling returns 429 without any
// network access.

describe("AI spend ceilings", () => {
  const today = () => new Date().toISOString().slice(0, 10);
  const IP = "203.0.113.77";                       // TEST-NET-3, never routable

  // The Worker never stores the address itself, so tests can't seed `ip:<addr>`
  // — they have to derive the same opaque key the Worker will. Deriving it via
  // the Worker's OWN helper rather than re-implementing the hash means a change
  // to the derivation shows up as a failure here instead of silently making
  // these tests seed rows nothing reads.
  const ipDayKey = async () => `ip:${await hashedIP(env, IP, ipDayScope())}`;
  const ipMonthKey = async () => `ipm:${await hashedIP(env, IP, ipMonthScope())}`;

  async function seed(key, count) {
    await env.DB.prepare(
      `INSERT INTO ai_usage (install_id, period, count) VALUES (?, ?, ?)
       ON CONFLICT(install_id, period) DO UPDATE SET count = excluded.count`
    ).bind(key, today(), count).run();
  }

  const scan = (install) => call("/", {
    headers: { "X-Cuevi-Install": install, "CF-Connecting-IP": IP },
    body: { model: "gpt-5-mini", messages: [{ role: "user", content: "hi" }] },
  });

  it("ROTATING THE INSTALL ID DOES NOT BUY A FRESH BUDGET", async () => {
    await seed(await ipDayKey(), IP_DAY_LIMIT);

    // Three different install ids, none of which has ever been seen before —
    // exactly what an attacker with the shipped token would send.
    for (const id of ["brand-new-install-1", "brand-new-install-2", "totally-different-3"]) {
      const r = await scan(id);
      expect(r.status).toBe(429);
      expect(r.body.message).toMatch(/network/i);
    }
  });

  it("lets the same IP through while it is under the ceiling", async () => {
    await seed(await ipDayKey(), 0);
    await seed("*global*", 0);
    const r = await scan("install-under-the-cap");
    // Not 429: it gets past both ceilings. (It fails later at the upstream call,
    // which has no key in tests — the point is which gate it reached.)
    expect(r.status).not.toBe(429);
  });

  it("trips the global circuit breaker regardless of IP or install", async () => {
    await seed(await ipDayKey(), 0);
    await seed("*global*", GLOBAL_DAY_LIMIT);

    const r = await call("/", {
      headers: { "X-Cuevi-Install": "someone-else-entirely", "CF-Connecting-IP": "198.51.100.9" },
      body: { model: "gpt-5-mini", messages: [{ role: "user", content: "hi" }] },
    });
    expect(r.status).toBe(429);
    // Distinguishable from the per-network message: this one means "stop
    // spending", not "you personally did too much".
    expect(r.body.message).toMatch(/temporarily unavailable/i);
  });

  it("counts every request against the IP row, whatever install id it claims", async () => {
    await seed(await ipDayKey(), IP_DAY_LIMIT);
    await scan("rotating-id-a");
    await scan("rotating-id-b");

    const row = await env.DB.prepare(
      "SELECT count FROM ai_usage WHERE install_id = ? AND period = ?"
    ).bind(await ipDayKey(), today()).first();
    // Both refused requests still counted — the ceiling can't be worn down by
    // retrying under new identities.
    expect(row.count).toBe(IP_DAY_LIMIT + 2);
  });

  it("NEVER writes the address itself", async () => {
    await seed(await ipDayKey(), 0);
    await scan("some-install-id");
    // The whole point of hashing: no row anywhere may contain the raw address.
    const hit = await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM ai_usage WHERE install_id LIKE ?").bind(`%${IP}%`).first();
    expect(hit.n).toBe(0);
  });

  it("keeps a MONTHLY count for clients that send no install header", async () => {
    // These clients fall back to an IP-derived quota key. It rotates monthly,
    // not daily — scoping it to the day reset the monthly cap every 24h, which
    // quietly removed the monthly limit for exactly the oldest builds.
    const monthKey = await ipMonthKey();
    await env.DB.prepare("DELETE FROM ai_usage WHERE install_id = ?").bind(monthKey).run();

    await call("/", {                       // no X-Cuevi-Install at all
      headers: { "CF-Connecting-IP": IP },
      body: { model: "gpt-5-mini", messages: [{ role: "user", content: "hi" }] },
    });

    const month = await env.DB.prepare(
      "SELECT count FROM ai_usage WHERE install_id = ? AND period = ?"
    ).bind(monthKey, new Date().toISOString().slice(0, 7)).first();
    expect(month?.count).toBe(1);
  });

  it("refuses rather than storing a reversible key when the pepper is missing", async () => {
    // DB explicitly re-attached: the same route also 503s when DB is missing, so
    // a spread that dropped the binding would make this pass for the wrong reason.
    const noPepper = { ...env, DB: env.DB, PASSWORD_PEPPER: undefined };
    const request = new Request("https://worker.test/", {
      method: "POST",
      headers: { "Content-Type": "application/json", "CF-Connecting-IP": IP },
      body: JSON.stringify({ model: "gpt-5-mini", messages: [{ role: "user", content: "hi" }] }),
    });
    const ctx = createExecutionContext();
    const response = await worker.fetch(request, noPepper, ctx);
    await waitOnExecutionContext(ctx);
    // Fails CLOSED: no pepper means no way to key the quota without keeping the
    // address, so the request is refused instead.
    expect(response.status).toBe(503);
  });
});

// ── scheduled retention sweep ────────────────────────────────────────────────
//
// sweepRetention() sat uncalled for two days because the route it hung off was
// deleted, so every retention period the privacy policy promises was silently
// not happening. It runs from a cron now, and this proves the handler is wired
// to it — the failure mode is "nothing calls it", which no unit test of the
// function itself would ever catch.

describe("scheduled retention", () => {
  it("deletes expired rows and keeps fresh ones", async () => {
    const old = new Date(Date.now() - 400 * 86400_000).toISOString();
    const fresh = new Date().toISOString();

    await env.DB.prepare(
      "INSERT OR REPLACE INTO tasks (user_id, item_id, payload, updated_at, deleted_at) VALUES (?, ?, '', ?, ?)"
    ).bind("sweep-user", uuid(901), old, old).run();
    await env.DB.prepare(
      "INSERT OR REPLACE INTO tasks (user_id, item_id, payload, updated_at, deleted_at) VALUES (?, ?, '', ?, ?)"
    ).bind("sweep-user", uuid(902), fresh, fresh).run();
    await env.DB.prepare(
      "INSERT OR REPLACE INTO ai_usage (install_id, period, count) VALUES (?, ?, 1)"
    ).bind("sweep-install", old.slice(0, 10)).run();

    const ctx = createExecutionContext();
    await worker.scheduled({ cron: "12 4 * * *" }, env, ctx);
    await waitOnExecutionContext(ctx);

    const gone = await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM tasks WHERE user_id = ? AND item_id = ?").bind("sweep-user", uuid(901)).first();
    const kept = await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM tasks WHERE user_id = ? AND item_id = ?").bind("sweep-user", uuid(902)).first();
    const usage = await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM ai_usage WHERE install_id = ?").bind("sweep-install").first();

    expect(gone.n).toBe(0);      // 400-day-old tombstone swept
    expect(kept.n).toBe(1);      // today's is untouched
    expect(usage.n).toBe(0);     // usage counter past its 60 days
  });
});

// ── metrics ingest ───────────────────────────────────────────────────────────

describe("events", () => {
  it("stores valid events and ignores junk ones", async () => {
    const r = await call("/events", {
      body: {
        installID: "install-1", appVersion: "1.0 (4)",
        events: [
          { id: "e1", kind: "confirmed", date: "2026-08-10T10:00:00Z", source: "scanned" },
          { id: "e2", kind: "not-a-kind", date: "2026-08-10T10:00:00Z" },
          // The retention signal. Carries no item and no source — if the kind
          // allow-list ever loses this, D1/D7/D30 goes silently to zero and
          // nothing else breaks, which is the worst way for it to fail.
          { id: "e-open", kind: "opened", date: "2026-08-10T00:00:00Z" },
        ],
      },
    });
    expect(r.status).toBe(200);
    expect(r.body.accepted).toBe(2);   // the confirmed one and the open; junk kind dropped

    const stored = await env.DB.prepare(
      "SELECT kind, item_id, source FROM events WHERE event_id = 'e-open'"
    ).first();
    expect(stored.kind).toBe("opened");
    expect(stored.item_id).toBe(null);
    expect(stored.source).toBe(null);
  });

  it("413s a batch over the limit", async () => {
    const events = Array.from({ length: 30 }, (_, i) => ({
      id: `e${i}`, kind: "confirmed", date: "2026-08-10T10:00:00Z",
    }));
    const r = await call("/events", { body: { installID: "i", appVersion: "v", events } });
    expect(r.status).toBe(413);
  });

  // Re-sending the same batch must not double-count (INSERT OR IGNORE on the
  // event id), or the funnel numbers would drift upward on every flaky upload.
  it("is idempotent on re-send", async () => {
    const body = {
      installID: "install-2", appVersion: "1.0 (4)",
      events: [{ id: "dup", kind: "confirmed", date: "2026-08-10T10:00:00Z" }],
    };
    await call("/events", { body });
    await call("/events", { body });
    const n = await env.DB.prepare("SELECT COUNT(*) AS n FROM events WHERE event_id = 'dup'").first();
    expect(n.n).toBe(1);
  });
});

// ── email + password auth ────────────────────────────────────────────────────
//
// The password itself never reaches the Worker: the app runs PBKDF2 and sends the
// derived key, which is why these send a 64-char hex string. See schema.sql.

const KEY_A = "a".repeat(64);
const KEY_B = "b".repeat(64);
const register = (email, derivedKey = KEY_A, extra = {}) =>
  call("/auth/email/register", {
    body: { email, derivedKey, iterations: 600000, deviceId: "device-1", ...extra },
  });
const login = (email, derivedKey = KEY_A, extra = {}) =>
  call("/auth/email/login", {
    body: { email, derivedKey, deviceId: "device-1", ...extra },
  });

describe("login throttle", () => {
  // The global limiter keys on headers the caller sets, so rotating
  // X-Cuevi-Install makes every guess look like a new phone. These pin the one
  // thing an attacker cannot rotate: the address they are trying to break into.
  const wrong = (email) => login(email, KEY_B);

  it("blocks after ten wrong guesses, even from a fresh install id each time", async () => {
    await register("target@example.com");

    for (let i = 0; i < 9; i++) {
      const r = await call("/auth/email/login", {
        headers: { "X-Cuevi-Install": `install-${i}` },   // a new "phone" every time
        body: { email: "target@example.com", derivedKey: KEY_B, deviceId: "d" },
      });
      expect(r.status).toBe(401);                          // still just wrong
    }

    const tenth = await wrong("target@example.com");
    expect(tenth.status).toBe(401);

    // Door closed — and the RIGHT password does not open it either, or the
    // throttle would be trivially bypassed by guessing it.
    const blocked = await login("target@example.com");
    expect(blocked.status).toBe(429);
    expect(blocked.body.error).toBe("too_many_attempts");
  });

  it("counts unknown addresses too, so it cannot be used to enumerate accounts", async () => {
    // A distinct address on purpose: blocking one poisons it for 15 minutes, and
    // the enumeration test below reuses `ghost@example.com` expecting a 401.
    for (let i = 0; i < 10; i++) await wrong("never-registered@example.com");
    const r = await wrong("never-registered@example.com");
    expect(r.status).toBe(429);   // same treatment as a real account
  });

  it("a correct password clears the record", async () => {
    await register("clears@example.com");
    for (let i = 0; i < 3; i++) expect((await wrong("clears@example.com")).status).toBe(401);

    expect((await login("clears@example.com")).status).toBe(200);
    const row = await env.DB.prepare(
      "SELECT * FROM login_attempts WHERE email = ?").bind("clears@example.com").first();
    expect(row).toBeFalsy();
  });

  it("is scoped per email — one account under attack doesn't lock out another", async () => {
    await register("victim@example.com");
    await register("bystander@example.com");
    for (let i = 0; i < 10; i++) await wrong("victim@example.com");

    expect((await login("victim@example.com")).status).toBe(429);
    expect((await login("bystander@example.com")).status).toBe(200);
  });
});

describe("email auth", () => {
  it("registers an account and returns a usable session", async () => {
    const r = await register("rachel@example.com");
    expect(r.status).toBe(200);
    expect(r.body.token).toBeTruthy();
    expect(r.body.userID).toBeTruthy();
    expect(r.body.hasServerData).toBe(false);   // brand new: nothing to reconcile

    // The token really works against a protected route.
    const sync = await call("/sync", {
      headers: { "X-Tadah-Session": r.body.token },
      body: { since: "", changes: [], deletes: [] },
    });
    expect(sync.status).toBe(200);
  });

  it("never stores the derived key itself", async () => {
    await register("stored@example.com");
    const row = await env.DB.prepare(
      "SELECT pw_hash, pw_salt FROM accounts WHERE email = ?").bind("stored@example.com").first();
    expect(row.pw_hash).not.toBe(KEY_A);       // hashed, not echoed
    expect(row.pw_hash).not.toContain(KEY_A);
    expect(row.pw_salt).toBeTruthy();          // and salted
  });

  it("logs in with the right password and rejects the wrong one", async () => {
    await register("login@example.com", KEY_A);

    const ok = await login("login@example.com", KEY_A);
    expect(ok.status).toBe(200);
    expect(ok.body.token).toBeTruthy();

    const bad = await login("login@example.com", KEY_B);
    expect(bad.status).toBe(401);
    expect(bad.body.token).toBeUndefined();
  });

  // ACCOUNT ENUMERATION. If "no such account" and "wrong password" answered
  // differently, anyone could test addresses against the API and walk away with a
  // list of your users.
  it("gives an identical answer for a wrong password and an unknown account", async () => {
    await register("real@example.com", KEY_A);
    const wrongPassword = await login("real@example.com", KEY_B);
    const noSuchAccount = await login("ghost@example.com", KEY_A);

    expect(wrongPassword.status).toBe(noSuchAccount.status);
    expect(wrongPassword.body).toEqual(noSuchAccount.body);
    expect(wrongPassword.body.error).toBe("invalid_credentials");
  });

  it("treats an address as one account regardless of case or spacing", async () => {
    await register("Case@Example.com");
    const dupe = await register("  CASE@example.COM  ");
    expect(dupe.status).toBe(409);
    expect(dupe.body.error).toBe("email_taken");

    const ok = await login("case@example.com");
    expect(ok.status).toBe(200);
  });

  it("refuses a second account on the same address", async () => {
    await register("taken@example.com");
    const again = await register("taken@example.com", KEY_B);
    expect(again.status).toBe(409);
  });

  it("rejects junk input rather than storing it", async () => {
    expect((await register("not-an-email")).status).toBe(400);
    expect((await register("ok@example.com", "not-hex")).status).toBe(400);
    expect((await register("ok2@example.com", "a".repeat(63))).status).toBe(400);
    // A client claiming far less stretching than the app does would make a stolen
    // hash cheap to attack.
    expect((await register("ok3@example.com", KEY_A, { iterations: 100 })).status).toBe(400);
    expect((await register("ok4@example.com", KEY_A, { deviceId: "" })).status).toBe(400);
  });

  it("an existing account reports hasServerData so the app reconciles", async () => {
    const made = await register("hasdata@example.com");
    await call("/sync", {
      headers: { "X-Tadah-Session": made.body.token },
      body: { since: "", changes: [change(uuid(300), "2026-08-14T10:00:00.000Z")], deletes: [] },
    });
    const back = await login("hasdata@example.com");
    expect(back.body.hasServerData).toBe(true);
  });
});

// ── deleting an EMAIL account ────────────────────────────────────────────────
//
// App Store guideline 5.1.1(v) requires in-app deletion. The Apple path proves
// identity with a fresh Apple grant; an email account has none, so it proves it
// with the password instead — and must not be blocked by Apple config it will
// never have.

describe("email account deletion", () => {
  it("refuses without the right password", async () => {
    const made = await register("del-wrong@example.com", KEY_A);
    const r = await call("/account/delete", {
      headers: { "X-Tadah-Session": made.body.token },
      body: { derivedKey: KEY_B },
    });
    expect(r.status).toBe(401);

    // Still there — a failed re-auth must not delete anything.
    const still = await env.DB.prepare(
      "SELECT 1 AS ok FROM accounts WHERE email = ?").bind("del-wrong@example.com").first();
    expect(still).toBeTruthy();
  });

  it("refuses with no password at all", async () => {
    const made = await register("del-none@example.com", KEY_A);
    const r = await call("/account/delete", {
      headers: { "X-Tadah-Session": made.body.token },
      body: {},
    });
    expect(r.status).toBe(401);
  });

  // The account row itself has to go, not just the to-dos: leaving it would keep
  // the address registered forever, so the user could never sign up again — and
  // we'd still hold a password hash for an account we said we deleted.
  it("with the right password, removes the credentials and the data", async () => {
    const made = await register("del-ok@example.com", KEY_A);
    await call("/sync", {
      headers: { "X-Tadah-Session": made.body.token },
      body: { since: "", changes: [change(uuid(400), "2026-08-14T10:00:00.000Z")], deletes: [] },
    });

    const r = await call("/account/delete", {
      headers: { "X-Tadah-Session": made.body.token },
      body: { derivedKey: KEY_A },
    });
    // 501 only when RevenueCat isn't configured in the test env — either way it
    // must NOT be the 400 "authorization_required" that the Apple branch returns,
    // which would mean email accounts can never be deleted.
    expect([200, 501]).toContain(r.status);

    if (r.status === 200) {
      const acct = await env.DB.prepare(
        "SELECT 1 AS ok FROM accounts WHERE email = ?").bind("del-ok@example.com").first();
      expect(acct).toBeFalsy();
      const task = await env.DB.prepare(
        "SELECT 1 AS ok FROM tasks WHERE user_id = ?").bind(made.body.userID).first();
      expect(task).toBeFalsy();
      // And the address is free again.
      expect((await register("del-ok@example.com", KEY_B)).status).toBe(200);
    }
  });
});

// ── password reset ──────────────────────────────────────────────────────────

import { createHmac } from "node:crypto";

// Mirrors the Worker's resetCodeHash: HMAC-SHA256 keyed with the pepper, over
// `reset:<code>:<64 zeros>` — NOT a bare SHA-256. Keying is what makes a leaked
// password_resets table useless: six digits would otherwise be searched instantly.
// Must stay in step with derivePasswordHash's message format.
const resetHash = (code) =>
  createHmac("sha256", "test-pepper").update(`reset:${code}:${"0".repeat(64)}`).digest("base64");

// Plant a reset code directly rather than recovering the emailed one.
//
// Recovering it means brute-forcing the stored SHA-256 across a million
// candidates, which is both slow and a strange thing for a test to assert. The
// route that ISSUES codes is covered separately; these tests are about what
// happens once a code exists, so the state is set up explicitly — including the
// expiry and attempt count, which is the only practical way to test them.
async function plantResetCode(user, code = "123456", { minutesFromNow = 15, attempts = 0 } = {}) {
  await env.DB.prepare(
    `INSERT OR REPLACE INTO password_resets (user_id, code_hash, expires_at, attempts, created_at)
     VALUES (?, ?, ?, ?, ?)`
  ).bind(user, resetHash(code), new Date(Date.now() + minutesFromNow * 60000).toISOString(),
         attempts, new Date().toISOString()).run();
  return code;
}

const confirmReset = (email, code, derivedKey = KEY_B, extra = {}) =>
  call("/auth/email/reset/confirm", {
    body: { email, code, derivedKey, iterations: 600000, ...extra },
  });

describe("password reset", () => {
  it("issuing a code stores only its hash", async () => {
    const made = await register("issue@example.com", KEY_A);
    const asked = await call("/auth/email/reset/request", { body: { email: "issue@example.com" } });
    expect(asked.status).toBe(200);

    const row = await env.DB.prepare(
      "SELECT code_hash, attempts FROM password_resets WHERE user_id = ?"
    ).bind(made.body.userID).first();
    expect(row).toBeTruthy();
    // A KEYED digest (base64 HMAC), not six digits and not a bare SHA-256 — the
    // key is what stops a leaked table being brute-forced in a million guesses.
    expect(row.code_hash).not.toMatch(/^\d{6}$/);
    expect(row.code_hash.length).toBeGreaterThan(20);
    expect(row.attempts).toBe(0);
  });

  it("accepts the code once, changes the password, and revokes every session", async () => {
    const made = await register("reset@example.com", KEY_A);
    const user = made.body.userID;
    const code = await plantResetCode(user);

    expect((await confirmReset("reset@example.com", code)).status).toBe(200);

    // New password works, old one doesn't.
    expect((await login("reset@example.com", KEY_B)).status).toBe(200);
    expect((await login("reset@example.com", KEY_A)).status).toBe(401);

    // A reset is what you do when you fear the account is compromised, so other
    // devices must be signed out — only the session the new login just made
    // should be live.
    const live = await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM sessions WHERE user_id = ? AND revoked = 0").bind(user).first();
    expect(live.n).toBe(1);

    // Single use.
    expect((await confirmReset("reset@example.com", code, KEY_A)).status).toBe(400);
  });

  // ENUMERATION. "No such account" here would hand over a list of who uses Tadah.
  it("answers identically for an unknown address, and issues nothing", async () => {
    // A DELTA, not an absolute count: D1 persists across tests in this file, so
    // rows planted by earlier ones are still there.
    const before = (await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM password_resets").first()).n;

    const r = await call("/auth/email/reset/request", { body: { email: "nobody@example.com" } });
    expect(r.status).toBe(200);
    expect(r.body).toEqual({ ok: true });     // indistinguishable from a real one

    const after = (await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM password_resets").first()).n;
    expect(after).toBe(before);               // nothing issued for a stranger
  });

  // Six digits is a million guesses. The cap, not the code, is the real defence.
  it("burns the code after too many wrong guesses", async () => {
    const made = await register("brute@example.com", KEY_A);
    const code = await plantResetCode(made.body.userID, "123456");

    for (let i = 0; i < 5; i++) {
      expect((await confirmReset("brute@example.com", "000000")).status).toBe(400);
    }
    // Even the RIGHT code is dead now, and the password never changed.
    expect((await confirmReset("brute@example.com", code)).status).toBe(400);
    expect((await login("brute@example.com", KEY_A)).status).toBe(200);
  });

  it("refuses an expired code", async () => {
    const made = await register("expired@example.com", KEY_A);
    const code = await plantResetCode(made.body.userID, "123456", { minutesFromNow: -1 });

    expect((await confirmReset("expired@example.com", code)).status).toBe(400);
    expect((await login("expired@example.com", KEY_A)).status).toBe(200);   // unchanged
  });

  it("replaces an outstanding code rather than stacking live ones", async () => {
    const made = await register("twice@example.com", KEY_A);
    await call("/auth/email/reset/request", { body: { email: "twice@example.com" } });
    await call("/auth/email/reset/request", { body: { email: "twice@example.com" } });
    const rows = await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM password_resets WHERE user_id = ?").bind(made.body.userID).first();
    expect(rows.n).toBe(1);
  });

  it("rejects a malformed code or a weak derivation", async () => {
    const made = await register("malformed@example.com", KEY_A);
    await plantResetCode(made.body.userID);
    for (const bad of [{ code: "abc" }, { code: "12345" }, { code: "1234567" },
                       { code: "123456", iterations: 10 }]) {
      expect((await confirmReset("malformed@example.com", "123456", KEY_B, bad)).status).toBe(400);
    }
    expect((await login("malformed@example.com", KEY_A)).status).toBe(200);  // unchanged
  });
});

// ── deployment-safety guarantees ────────────────────────────────────────────
//
// These pin things whose ABSENCE is invisible: a forgotten secret used to change
// behaviour silently rather than fail, which is the worst property a security
// control can have.

describe("auth refuses to run misconfigured", () => {
  // Simulated by handing the routes an env WITHOUT the pepper, the way a deploy
  // that skipped `wrangler secret put PASSWORD_PEPPER` would.
  const noPepper = { ...env, PASSWORD_PEPPER: undefined };

  async function callWith(bindings, path, body) {
    const request = new Request(`https://worker.test${path}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    const ctx = createExecutionContext();
    const response = await worker.fetch(request, bindings, ctx);
    await waitOnExecutionContext(ctx);
    return { status: response.status, body: await response.clone().json().catch(() => null) };
  }

  it("503s instead of hashing with a default pepper", async () => {
    for (const [path, body] of [
      ["/auth/email/register", { email: "a@b.co", derivedKey: KEY_A, iterations: 600000, deviceId: "d" }],
      ["/auth/email/login", { email: "a@b.co", derivedKey: KEY_A, deviceId: "d" }],
      ["/auth/email/reset/request", { email: "a@b.co" }],
      ["/auth/email/reset/confirm", { email: "a@b.co", code: "123456", derivedKey: KEY_A, iterations: 600000 }],
    ]) {
      const r = await callWith(noPepper, path, body);
      expect(r.status, `${path} should refuse without a pepper`).toBe(503);
      expect(r.body.error).toBe("not_configured");
    }
  });
});

describe("reset abuse resistance", () => {
  it("won't reissue a code immediately, so an inbox can't be flooded", async () => {
    const made = await register("flood@example.com", KEY_A);
    await call("/auth/email/reset/request", { body: { email: "flood@example.com" } });
    const first = await env.DB.prepare(
      "SELECT code_hash, created_at FROM password_resets WHERE user_id = ?"
    ).bind(made.body.userID).first();

    // Second request inside the cooldown: still 200 (identical response, so it
    // leaks nothing) but the stored code is untouched — nothing was re-sent.
    const again = await call("/auth/email/reset/request", { body: { email: "flood@example.com" } });
    expect(again.status).toBe(200);
    const second = await env.DB.prepare(
      "SELECT code_hash, created_at FROM password_resets WHERE user_id = ?"
    ).bind(made.body.userID).first();
    expect(second.code_hash).toBe(first.code_hash);
    expect(second.created_at).toBe(first.created_at);
  });

  // The cap is claimed by a conditional UPDATE ... RETURNING, so five concurrent
  // guesses can't all pass a check-then-increment.
  it("caps attempts even when guesses arrive at once", async () => {
    const made = await register("race@example.com", KEY_A);
    await plantResetCode(made.body.userID, "123456");

    const guesses = Array.from({ length: 12 }, () =>
      confirmReset("race@example.com", "000000"));
    const results = await Promise.all(guesses);
    expect(results.every((r) => r.status === 400)).toBe(true);

    // At most RESET_MAX_ATTEMPTS were ever claimed; the row is gone or exhausted.
    const row = await env.DB.prepare(
      "SELECT attempts FROM password_resets WHERE user_id = ?").bind(made.body.userID).first();
    expect(row === null || row.attempts <= 5).toBe(true);

    // And the real code is dead.
    expect((await confirmReset("race@example.com", "123456")).status).toBe(400);
    expect((await login("race@example.com", KEY_A)).status).toBe(200);   // unchanged
  });

  it("deleting the account takes any outstanding reset code with it", async () => {
    const made = await register("cleanup@example.com", KEY_A);
    await plantResetCode(made.body.userID);
    expect((await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM password_resets WHERE user_id = ?"
    ).bind(made.body.userID).first()).n).toBe(1);

    await call("/account/delete", {
      headers: { "X-Tadah-Session": made.body.token },
      body: { derivedKey: KEY_A },
    });

    expect((await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM password_resets WHERE user_id = ?"
    ).bind(made.body.userID).first()).n).toBe(0);
  });
});
