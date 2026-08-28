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
  kind        TEXT NOT NULL,      -- 'confirmed' | 'completed' | 'opened'
                                  -- 'opened' = one row per install per local
                                  -- calendar day (no item, no time of day):
                                  -- the D1/D7/D30 retention signal.
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

-- AI-call counters (chat proxy quota; see worker.js AI_DAY_LIMIT).
-- The worker lazy-creates this table too, so applying this file is optional;
-- kept here so schema.sql stays the one honest description of the database.
--
-- ⚠️ `install_id` IS NO LONGER ALWAYS AN INSTALL ID. Despite the column name it
-- now holds four kinds of key, and the prefix tells them apart:
--   <uuid>   the app's per-install UUID (same id metrics use) — the normal case
--   ip:<hex> a DAILY salted hash of the client IP — the per-network ceiling
--   ipm:<hex> a MONTHLY salted hash of the client IP — the fallback quota for
--            older builds that send no install header, which needs a key stable
--            across the month because it carries a monthly count
--   *global* the single circuit-breaker row counting every AI call
-- The hashes are salted with PASSWORD_PEPPER and are NOT reversible; the raw
-- address is never written. Renaming the column would need a migration on a live
-- database, so the name stays and this comment carries the truth.
CREATE TABLE IF NOT EXISTS ai_usage (
  install_id TEXT NOT NULL,   -- install UUID, or ip:/ipm:/*global* quota key (see above)
  period     TEXT NOT NULL,   -- '2026-07-08' (a day) or '2026-07' (a month)
  count      INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (install_id, period)
);

-- ── Account task sync (Part 3) ───────────────────────────────────────────────
-- The server-side backup + cross-device copy of a signed-in user's tasks. One
-- row per (user, item). user_id is the account id the Worker resolved from the
-- session (never trusted from the client). payload is the app's TaskDTO JSON —
-- the server treats it as opaque and only reasons about updated_at (last-writer-
-- wins) and deleted_at (soft delete; NULL = live). Photos are NOT synced here.
CREATE TABLE IF NOT EXISTS tasks (
  user_id     TEXT NOT NULL,      -- the account id (from the session)
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
  user_id         TEXT NOT NULL,      -- the account id (from the session)
  device_id       TEXT NOT NULL,      -- the app's anonymous Install.id
  created_at      TEXT NOT NULL,      -- ISO-8601
  last_seen       TEXT NOT NULL,      -- ISO-8601, bumped on each /sync
  revoked         INTEGER NOT NULL DEFAULT 0,  -- 1 = taken over by another device / signed out
  plus_checked_at TEXT                -- ISO-8601 of the last RevenueCat tier check
);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);

-- (The `used_nonces` table went with Sign in with Apple on 2026-08-15/16. An
-- already-deployed database still has it; nothing reads or writes it, and it can
-- be dropped by hand: DROP TABLE IF EXISTS used_nonces;)

-- Progress through account deletion. Deleting an account touches RevenueCat (the
-- subscriber record) and D1 (our rows). RevenueCat's deletion isn't undoable, so
-- the sequence CANNOT be made atomic — instead the completed step is recorded
-- here and /account/delete is idempotent, resuming at the unfinished one. The row
-- is removed once everything has succeeded.
--
-- Deployments made before 2026-08-16 also carry an `apple_revoked` column from the
-- Sign-in-with-Apple grant-revocation step. It is never read or written now.
CREATE TABLE IF NOT EXISTS account_deletions (
  user_id            TEXT PRIMARY KEY,             -- the account id
  revenuecat_deleted INTEGER NOT NULL DEFAULT 0,
  started_at         TEXT NOT NULL                 -- ISO-8601
);

-- Family profiles (Part 3, family sharing). One account = one sign-in, but
-- several person-spaces inside it ("Mom", "Dad"), each with its own to-do list.
-- Same LWW + soft-delete contract as `tasks`; payload is the app's Profile JSON.
-- The names in here belong to REAL PEOPLE who never used the app — treat as
-- personal data and disclose it (see the privacy policy).
CREATE TABLE IF NOT EXISTS profiles (
  user_id     TEXT NOT NULL,      -- the account id
  profile_id  TEXT NOT NULL,      -- the Profile UUID
  payload     TEXT NOT NULL,      -- Profile JSON (name, colorIndex, isOwner)
  updated_at  TEXT NOT NULL,      -- ISO-8601; the LWW comparison key
  deleted_at  TEXT,               -- ISO-8601 soft delete, or NULL when live
  PRIMARY KEY (user_id, profile_id)
);
-- Composite, matching the (updated_at, profile_id) pull cursor — see tasks above.
CREATE INDEX IF NOT EXISTS idx_profiles_user_updated ON profiles(user_id, updated_at, profile_id);

-- ── Email + password accounts (Part 3b, replacing Sign in with Apple) ────────
--
-- WHY THE HASH LOOKS "CHEAP": the expensive key-stretching happens ON THE PHONE.
-- The app runs PBKDF2-HMAC-SHA256 at a high iteration count and sends the derived
-- value; the Worker stores HMAC-SHA256(pepper, salt || derived). That is not a
-- shortcut — an attacker holding this table still has to run the same expensive
-- derivation for every password they guess, so offline cracking costs exactly
-- what it would have. It moves WHERE the work is paid, because a Worker on the
-- free plan has 10ms of CPU per request and real PBKDF2 needs hundreds.
--
-- `user_id` is the account id used everywhere else (sessions, tasks, profiles),
-- so nothing downstream knows or cares which auth method minted it.
CREATE TABLE IF NOT EXISTS accounts (
  user_id       TEXT PRIMARY KEY,   -- our own id; what sessions/tasks/profiles key on
  email         TEXT NOT NULL,      -- lower-cased, trimmed
  pw_hash       TEXT NOT NULL,      -- base64 HMAC-SHA256(pepper, salt || client-derived)
  pw_salt       TEXT NOT NULL,      -- base64, 16 random bytes, per account
  pw_iterations INTEGER NOT NULL,   -- what the CLIENT used; stored so it can be raised later
  pw_version    INTEGER NOT NULL DEFAULT 1,  -- derivation scheme, for future migration
  verified_at   TEXT,               -- ISO-8601 once the email is confirmed, else NULL
  created_at    TEXT NOT NULL
);
-- One account per address. UNIQUE is the real guard against a race between two
-- simultaneous registrations — checking first and inserting after is not atomic.
CREATE UNIQUE INDEX IF NOT EXISTS idx_accounts_email ON accounts(email);

-- ── password resets (Part 3b) ───────────────────────────────────────────────
--
-- A 6-digit code emailed to the account's address. Deliberately a CODE and not a
-- link: a link needs a web page to land on, and there isn't one yet — a code is
-- typed straight into the app and needs no site at all.
--
-- Six digits is only a million combinations, so the code alone is not the
-- security boundary. What makes it safe is the combination of: a short expiry, a
-- hard attempt cap per code, single use, and the Worker's rate limiter in front.
--
-- The code is NEVER stored — only its SHA-256. A leak of this table therefore
-- doesn't let anyone reset an account.
--
-- PRIMARY KEY on user_id means requesting a new code REPLACES any outstanding
-- one, so a stack of live codes can't accumulate for the same account.
CREATE TABLE IF NOT EXISTS password_resets (
  user_id    TEXT PRIMARY KEY,
  code_hash  TEXT NOT NULL,      -- SHA-256 of the 6-digit code
  expires_at TEXT NOT NULL,      -- ISO-8601; short (see RESET_TTL_MINUTES)
  attempts   INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);

-- Failed sign-in attempts, keyed on the EMAIL BEING ATTACKED.
-- The global rate limiter keys on session/install/IP, all caller-supplied, so
-- rotating the install header makes every guess look like a new phone. The one
-- thing an attacker cannot change is which account they are trying to open.
CREATE TABLE IF NOT EXISTS login_attempts (
  email         TEXT PRIMARY KEY,
  failures      INTEGER NOT NULL DEFAULT 0,
  window_start  TEXT NOT NULL,
  blocked_until TEXT            -- NULL until the threshold is crossed
);
