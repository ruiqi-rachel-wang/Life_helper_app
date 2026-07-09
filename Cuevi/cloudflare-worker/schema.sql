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
