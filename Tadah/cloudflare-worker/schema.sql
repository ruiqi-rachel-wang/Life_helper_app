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
-- Sync pulls "everything for this user changed since <cursor>", where the cursor
-- is the COMPOSITE (updated_at, item_id) — updated_at alone isn't unique, so a
-- bulk write sharing one stamp would page badly. Index matches that sort order.
CREATE INDEX IF NOT EXISTS idx_tasks_user_updated ON tasks(user_id, updated_at, item_id);

-- Login sessions. One per (user, device) sign-in. The free tier keeps ONE active
-- (non-revoked) session per user — a new device sign-in revokes the others;
-- Plus keeps many. A revoked session makes /sync return 401 (the "signed out on
-- another device" signal). Tokens are opaque random strings, never a password.
-- A session also EXPIRES after SESSION_TTL_DAYS of inactivity (checked in
-- resolveSession), so a token copied off a device can't be used forever.
CREATE TABLE IF NOT EXISTS sessions (
  token           TEXT PRIMARY KEY,   -- opaque random session token
  user_id         TEXT NOT NULL,      -- verified Apple `sub`
  device_id       TEXT NOT NULL,      -- the app's anonymous Install.id
  created_at      TEXT NOT NULL,      -- ISO-8601
  last_seen       TEXT NOT NULL,      -- ISO-8601, bumped on each /sync
  revoked         INTEGER NOT NULL DEFAULT 0,  -- 1 = taken over by another device / signed out
  plus_checked_at TEXT                -- ISO-8601 of the last RevenueCat tier check
);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);

-- Single-use Sign-in-with-Apple nonces. The identity token carries
-- sha256(rawNonce); we burn that value here so the same token can't be replayed
-- inside its validity window to mint extra sessions. Swept after a day.
CREATE TABLE IF NOT EXISTS used_nonces (
  nonce   TEXT PRIMARY KEY,   -- the hashed nonce as it appears in the token claim
  used_at TEXT NOT NULL       -- ISO-8601
);

-- Family profiles (Part 3, family sharing). One account = one Apple sign-in, but
-- several person-spaces inside it ("Mom", "Dad"), each with its own to-do list.
-- Same LWW + soft-delete contract as `tasks`; payload is the app's Profile JSON.
-- The names in here belong to REAL PEOPLE who never used the app — treat as
-- personal data and disclose it (see the privacy policy).
CREATE TABLE IF NOT EXISTS profiles (
  user_id     TEXT NOT NULL,      -- verified Apple `sub` (the account)
  profile_id  TEXT NOT NULL,      -- the Profile UUID
  payload     TEXT NOT NULL,      -- Profile JSON (name, colorIndex, isOwner)
  updated_at  TEXT NOT NULL,      -- ISO-8601; the LWW comparison key
  deleted_at  TEXT,               -- ISO-8601 soft delete, or NULL when live
  PRIMARY KEY (user_id, profile_id)
);
-- Composite, matching the (updated_at, profile_id) pull cursor — see tasks above.
CREATE INDEX IF NOT EXISTS idx_profiles_user_updated ON profiles(user_id, updated_at, profile_id);
