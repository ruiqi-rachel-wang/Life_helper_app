//  APIKeys.swift
//
//  NO secret is stored here or compiled into the app binary. In Release the
//  Cloudflare Worker holds the OpenAI key (see BackendConfig); the app sends no
//  key at all.
//
//  For SIMULATOR-ONLY direct calls (used only when BackendConfig.workerURL is nil),
//  set the key as an environment variable named OPENAI_API_KEY in the Run scheme:
//    Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables.
//  It's read at runtime, never embedded in the binary, and never committed. This
//  file is therefore safe to commit (a clean checkout compiles with no setup).
//

import Foundation

nonisolated enum APIKeys {
    /// Dev-only key for the direct-OpenAI path; empty in Release (Worker holds it).
    static var openAI: String { ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "" }

    static var hasOpenAIKey: Bool { openAI.hasPrefix("sk-") }
}
