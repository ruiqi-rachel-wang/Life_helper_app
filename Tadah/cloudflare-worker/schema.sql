-- Cuevi anonymous tester metrics (Part 1).
-- One row per logged moment in the confirm -> complete loop. NON-PII only:
-- no titles, amounts, notes, or document text ever land here.
--
-- Apply once after creating the DB:
--   wrangler d1 execute cuevi-metrics --remote --file=schema.sql
-- (drop --remote to seed the local dev copy instead.)

CREATE TABLE IF NOT EXISTS events (
  event_id    TEXT PRIMARY KEY,   -- the device's per-event UUID. PRIMARY KEY makes
                                  -- re-sends idempotent (INSERT OR IGNORE = no dupes).
  install_id  TEXT NOT NULL,      -- anonymous per-install UUID (no PII, not a person)
  kind        TEXT NOT NULL,      -- 'confirmed' | 'completed'
  source      TEXT,               -- 'scanned' | 'guide' | 'custom' (on 'confirmed')
  on_time     INTEGER,            -- 1 = on/before due, 0 = late, NULL = no due date
  item_id     TEXT,               -- the item's UUID (lets the funnel match confirm->complete)
  occurred_at TEXT NOT NULL,      -- ISO-8601 timestamp from the device
  app_version TEXT,               -- e.g. "1.0 (3)"
  received_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))  -- when the Worker stored it
);

CREATE INDEX IF NOT EXISTS idx_events_install ON events(install_id);
CREATE INDEX IF NOT EXISTS idx_events_kind    ON events(kind);
CREATE INDEX IF NOT EXISTS idx_events_item    ON events(item_id);

-- Per-install AI-call counters (chat proxy quota; see worker.js AI_DAY_LIMIT).
-- The worker lazy-creates this table too, so applying this file is optional;
-- kept here so schema.sql stays the one honest description of the database.
CREATE TABLE IF NOT EXISTS ai_usage (
  install_id TEXT NOT NULL,   -- anonymous per-install UUID (same id metrics use)
  period     TEXT NOT NULL,   -- '2026-07-08' (a day) or '2026-07' (a month)
  count      INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (install_id, period)
);

-- ── Account task sync (Part 3) ───────────────────────────────────────────────
-- The server-side backup + cross-device copy of a signed-in user's tasks. One
-- row per (user, item). user_id is the Sign-in-with-Apple `sub` (verified by the
-- Worker, never trusted from the client). payload is the app's TaskDTO JSON —
-- the server treats it as opaque and only reasons about updated_at (last-writer-
-- wins) and deleted_at (soft delete; NULL = live). Photos are NOT synced here.
CREATE TABLE IF NOT EXISTS tasks (
  user_id     TEXT NOT NULL,      -- verified Apple `sub`
  item_id     TEXT NOT NULL,      -- the ActionItem UUID
  payload     TEXT NOT NULL,      -- TaskDTO JSON (opaque to the server; "" for a tombstone)
  updated_at  TEXT NOT NULL,      -- ISO-8601; the LWW comparison key
  deleted_at  TEXT,               -- ISO-8601 soft-delete stamp, or NULL when live
  PRIMARY KEY (user_id, item_id)
);
-- Sync pulls "everything for this user changed since <cursor>".
CREATE INDEX IF NOT EXISTS idx_tasks_user_updated ON tasks(user_id, updated_at);

-- Login sessions. One per (user, device) sign-in. The free tier keeps ONE active
-- (non-revoked) session per user — a new device sign-in revokes the others;
-- Plus keeps many. A revoked session makes /sync return 401 (the "signed out on
-- another device" signal). Tokens are opaque random strings, never a password.
CREATE TABLE IF NOT EXISTS sessions (
  token       TEXT PRIMARY KEY,   -- opaque random session token
  user_id     TEXT NOT NULL,      -- verified Apple `sub`
  device_id   TEXT NOT NULL,      -- the app's anonymous Install.id
  created_at  TEXT NOT NULL,      -- ISO-8601
  last_seen   TEXT NOT NULL,      -- ISO-8601, bumped on each /sync
  revoked     INTEGER NOT NULL DEFAULT 0   -- 1 = taken over by another device / signed out
);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);
