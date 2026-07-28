//  BackendConfig.swift
//
//  Where the app sends its AI requests. This file is COMMITTED and holds NO
//  secrets — it only points at the Cloudflare Worker that keeps the OpenAI key
//  server-side so the key never ships inside the app binary.
//
//  • Simulator / early dev: leave `workerURL` nil → OpenAIClient calls OpenAI
//    directly with the dev key in APIKeys.swift (gitignored, simulator only).
//  • TestFlight / Release: set `workerURL` to your deployed Worker. The app then
//    sends requests to the Worker with NO key, and the Worker adds the secret
//    key it holds. Verify a Release build contains no "sk-" string before you
//    ship (see cloudflare-worker/README.md).
//
//  Swapping between the two is exactly the "one-line change" the Extractor
//  protocol was designed for — nothing else in the pipeline changes.
//

import Foundation

nonisolated enum BackendConfig {
    // TODO (Rachel): after `wrangler deploy`, paste your Worker URL here, e.g.
    //   static let workerURL: URL? = URL(string: "https://cuevi-ai.<you>.workers.dev")
    // Leave nil to keep calling OpenAI directly with the dev key (simulator only).
    static let workerURL: URL? = URL(string: "https://cuevi-ai.ruiqiwang.workers.dev")

    // Shared secret sent to the Worker as `X-Cuevi-Token`; the Worker rejects requests
    // without it (its PROXY_TOKEN secret is set to this value). Safe to keep here while
    // the repo is PRIVATE — keep it private, or rotate both sides if it ever goes public
    // (it's still extractable from a shipped binary, so it's a deterrent, not a wall).
    // The real $ ceiling is your OpenAI spending cap; the Worker also caps max_tokens
    // and the model list.
    static let proxyToken = "2bd98d5ff9b14b0133ee843e0f6e37b165f39fdca9488356"

    // True once the Worker is configured — the app then sends no key of its own.
    static var usesWorker: Bool { workerURL != nil }

    // Where chat completions go: the Worker when configured, else OpenAI direct.
    static var chatEndpoint: URL {
        workerURL ?? URL(string: "https://api.openai.com/v1/chat/completions")!
    }

    // Where anonymous metrics go: the Worker's /events route, or nil when no Worker
    // is set (simulator dev) — then metrics stay local and nothing uploads.
    static var eventsEndpoint: URL? {
        workerURL?.appendingPathComponent("events")
    }
}
