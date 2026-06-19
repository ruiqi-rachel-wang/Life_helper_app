//  LegalConfig.swift
//
//  One place for the legal/privacy URLs and contact the app links out to, so
//  there are no string literals scattered through the UI (mirrors BackendConfig).
//
//  The documents themselves live in the repo under `legal/` (privacy-policy.md,
//  terms-of-service.md). These URLs point at the GitHub-hosted copies, which are
//  public as soon as the files are committed + pushed. If you later enable GitHub
//  Pages or use your own domain, just update the two URLs below — nothing else
//  changes. See `legal/README.md`.
//

import Foundation

enum LegalConfig {
    static let privacyPolicyURL = URL(string:
        "https://github.com/ruiqi-rachel-wang/Life_helper_app/blob/main/legal/privacy-policy.md")!
    static let termsURL = URL(string:
        "https://github.com/ruiqi-rachel-wang/Life_helper_app/blob/main/legal/terms-of-service.md")!
    static let contactEmail = "ruiqiwang_rachel@outlook.com"
}
