# Tadah metrics — commands

Pseudonymous, non-PII tester events (`confirmed` / `completed` / `opened`) in
Cloudflare D1.
⚠️ Nothing uploads until you deploy AND ship a build with the upload code — and
usage sharing is **opt-in**: the first-launch sheet asks, and only a yes uploads.

> **Read the retention section first.** The funnel (`confirmed` → `completed`)
> tells you the loop works for someone already in the app that day. `opened`,
> added 2026-08-20, is the one that tells you whether anybody came back — which
> is the number the business actually turns on. For two months the app had a
> healthy 66% completion rate and only ONE install that had ever returned across
> weeks, and nothing was measuring the second fact.

## One-time setup (run in `cloudflare-worker/`)

wrangler runs via `npx`. It needs **Node 22**, which is installed but not on the
default PATH — export it first or every command fails with a version error:

```sh
export PATH="/usr/local/opt/node@22/bin:$PATH"
```

If a fresh checkout has no `node_modules`: `npm install`.

```sh
npx wrangler d1 create cuevi-metrics     # prints database_id → paste into wrangler.toml
npx wrangler d1 execute cuevi-metrics --remote --file=schema.sql
npx wrangler deploy
```

Smoke test (token is in `BackendConfig.swift`):

```sh
curl -s -X POST https://cuevi-ai.ruiqiwang.workers.dev/events \
  -H "Content-Type: application/json" \
  -H "X-Cuevi-Token: 2bd98d5ff9b14b0133ee843e0f6e37b165f39fdca9488356" \
  -d '{"installID":"test","appVersion":"0 (0)","events":[
        {"id":"11111111-1111-1111-1111-111111111111","kind":"confirmed","date":"2026-06-23T10:00:00Z","source":"scanned"}]}'
# → {"ok":true,"accepted":1}
npx wrangler d1 execute cuevi-metrics --remote --command "DELETE FROM events WHERE install_id='test';"
```

## Retention — the numbers that decide things

Prefix: `npx wrangler d1 execute cuevi-metrics --remote --command "<SQL>"`

`opened` is one row per install per local calendar day, so every query here is
just counting days. No time-of-day is stored, on purpose.

```sql
-- ARE PEOPLE COMING BACK? Days-active per install, newest activity first.
-- One row with days_active=1 is someone who tried it once and left.
SELECT substr(install_id,1,6) AS who,
       COUNT(DISTINCT date(occurred_at)) AS days_active,
       MIN(date(occurred_at)) AS first_day,
       MAX(date(occurred_at)) AS last_day,
       julianday(MAX(occurred_at)) - julianday(MIN(occurred_at)) AS span_days
FROM events WHERE kind='opened'
GROUP BY install_id ORDER BY last_day DESC;

-- D1 / D7 / D30. Of the installs first seen at least N days ago, how many came
-- back on a day at least N days after their first? (The `first_seen` cut stops
-- a brand-new install counting as a D30 failure it hasn't had time to pass.)
WITH firsts AS (
  SELECT install_id, MIN(date(occurred_at)) AS d0
  FROM events WHERE kind='opened' GROUP BY install_id
)
SELECT
  SUM(CASE WHEN julianday('now') - julianday(d0) >= 1 THEN 1 ELSE 0 END)  AS eligible_d1,
  SUM(CASE WHEN EXISTS (SELECT 1 FROM events e WHERE e.install_id=f.install_id
        AND e.kind='opened' AND julianday(date(e.occurred_at)) - julianday(d0) >= 1) THEN 1 ELSE 0 END) AS returned_d1,
  SUM(CASE WHEN julianday('now') - julianday(d0) >= 7 THEN 1 ELSE 0 END)  AS eligible_d7,
  SUM(CASE WHEN EXISTS (SELECT 1 FROM events e WHERE e.install_id=f.install_id
        AND e.kind='opened' AND julianday(date(e.occurred_at)) - julianday(d0) >= 7) THEN 1 ELSE 0 END) AS returned_d7,
  SUM(CASE WHEN julianday('now') - julianday(d0) >= 30 THEN 1 ELSE 0 END) AS eligible_d30,
  SUM(CASE WHEN EXISTS (SELECT 1 FROM events e WHERE e.install_id=f.install_id
        AND e.kind='opened' AND julianday(date(e.occurred_at)) - julianday(d0) >= 30) THEN 1 ELSE 0 END) AS returned_d30
FROM firsts f;

-- WEEKLY ACTIVE INSTALLS — the trend line. Flat-and-low is the failure mode.
SELECT strftime('%Y-W%W', occurred_at) AS week,
       COUNT(DISTINCT install_id) AS active_installs,
       COUNT(*) AS days_opened
FROM events WHERE kind='opened'
GROUP BY week ORDER BY week;

-- DOES OPENING TURN INTO DOING? Of the days someone opened the app, on how many
-- did they add or complete something? A high open count with a low act count
-- means people look and leave.
SELECT COUNT(DISTINCT o.day) AS days_opened,
       COUNT(DISTINCT a.day) AS days_with_an_action
FROM (SELECT DISTINCT install_id, date(occurred_at) AS day FROM events WHERE kind='opened') o
LEFT JOIN (SELECT DISTINCT install_id, date(occurred_at) AS day FROM events WHERE kind<>'opened') a
  ON a.install_id=o.install_id AND a.day=o.day;
```

⚠️ **The install id resets on reinstall**, so a tester who deletes and reinstalls
looks like a new person who never returned. Retention here is a FLOOR, not an
exact figure — read the direction, not the decimal.

## Funnel queries

```sql
-- headline funnel (confirmed → completed → on time), all testers
SELECT
  COUNT(DISTINCT CASE WHEN kind='confirmed' THEN item_id END) AS confirmed,
  COUNT(DISTINCT CASE WHEN kind='completed' THEN item_id END) AS completed,
  SUM(CASE WHEN kind='completed' AND on_time=1 THEN 1 ELSE 0 END) AS completed_on_time
FROM events;

-- how many testers are sending data
SELECT COUNT(DISTINCT install_id) AS testers, COUNT(*) AS events FROM events;

-- item creation by source
SELECT source, COUNT(*) AS confirmed
FROM events WHERE kind='confirmed' GROUP BY source ORDER BY confirmed DESC;

-- activity per tester
SELECT install_id, SUM(kind='confirmed') AS confirmed,
       SUM(kind='completed') AS completed, MAX(occurred_at) AS last_seen
FROM events GROUP BY install_id ORDER BY last_seen DESC;

-- recent raw events
SELECT occurred_at, install_id, kind, source, on_time, app_version
FROM events ORDER BY occurred_at DESC LIMIT 20;
```

Or browse visually: Cloudflare dashboard → Workers & Pages → D1 → cuevi-metrics → Console.
