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

    // Optional shared secret sent to the Worker as `X-Cuevi-Token`. Set the SAME
    // value as a Worker secret: `wrangler secret put PROXY_TOKEN`. NOTE: anything
    // shipped in the app is extractable and this repo is public, so treat this as a
    // casual-abuse deterrent — NOT real security. The real $/volume ceilings are the
    // Worker's max_tokens cap + model allow-list, a Cloudflare rate-limit rule on the
    // route, and your OpenAI spending cap.
    static let proxyToken = ""

    // True once the Worker is configured — the app then sends no key of its own.
    static var usesWorker: Bool { workerURL != nil }

    // Where chat completions go: the Worker when configured, else OpenAI direct.
    static var chatEndpoint: URL {
        workerURL ?? URL(string: "https://api.openai.com/v1/chat/completions")!
    }
}
