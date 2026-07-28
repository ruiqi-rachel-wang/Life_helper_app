# Tadah metrics — commands

Anonymous, non-PII tester events (`confirmed`/`completed`) in Cloudflare D1.
⚠️ Nothing uploads until you deploy AND ship a build with the upload code — and do
the privacy-policy/label update (Part 1 Phase 3) before that TestFlight upload.

## One-time setup (run in `cloudflare-worker/`)

wrangler is installed locally (Node 20 → pinned v3; v4 needs Node 22), so run it via
`npx`. If a fresh checkout has no `node_modules`: `npm install`.

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

## Queries

Prefix: `npx wrangler d1 execute cuevi-metrics --remote --command "<SQL>"`

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
