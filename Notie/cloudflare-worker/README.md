# Plaino AI proxy (Cloudflare Worker)

Keeps the OpenAI key **off the phone**. The app calls this Worker with no key;
the Worker adds the secret key (held server-side) and forwards to OpenAI.

## One-time deploy

1. Install the CLI and log in (free Cloudflare account):
   ```sh
   npm install -g wrangler
   wrangler login
   ```
2. From this folder, set your OpenAI key as a secret (you'll be prompted to paste it):
   ```sh
   wrangler secret put OPENAI_API_KEY
   ```
3. Deploy:
   ```sh
   wrangler deploy
   ```
   Copy the URL it prints, e.g. `https://plaino-ai.<you>.workers.dev`.
4. In the app, set that URL in `Notie/AI/BackendConfig.swift`:
   ```swift
   static let workerURL: URL? = URL(string: "https://plaino-ai.<you>.workers.dev")
   ```

## Before you ship to TestFlight

- **Rotate the OpenAI key** that was previously pasted into `APIKeys.swift` (it
  sat in plaintext locally) and put the placeholder back in `APIKeys.swift`.
- Confirm the Release build has no key baked in:
  ```sh
  # Archive, then from the .app bundle:
  strings Notie.app/Notie | grep -c "sk-"   # must print 0
  ```
- Keep your OpenAI spending cap on. The app also limits scans (10/day, 50/month).
- Optional: add a Cloudflare **Rate limiting rule** in the dashboard for the
  Worker route to blunt abuse if the endpoint is discovered.

## Local test

```sh
wrangler dev
# then POST a chat-completions body to http://localhost:8787
```
