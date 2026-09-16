//  ActionsService.swift
//
//  Talks to the Worker about ACTIONS — things Tadah does for the user rather
//  than tells them to do. The first kind is a phone call: the Worker authorises
//  it, hands it to the calling provider, and writes the answer back onto the
//  to-do.
//
//  The phone is never on the call and never holds the provider's key. This file
//  only ever says "please start this" and "is it done yet", both against our own
//  Worker with the ordinary session token.
//
//  Nothing here retries. A call that failed is reported to the user and stops —
//  redialling a paid phone line automatically is the one bug in this feature
//  that can spend real money while nobody is watching. Same rule as the Worker's.
//

import Foundation

enum ActionsService {

    // ── What a call needs ───────────────────────────────────────────────────

    struct CallRequest {
        /// As printed on the document or given by a guide. The Worker normalizes
        /// and validates it; we deliberately don't try to pre-format it here, so
        /// there is exactly one place that decides what is dialable.
        var phone: String
        /// What the user wants out of the call, in their own words.
        var goal: String
        /// Exactly what the agent may commit them to, from the confirm screen.
        /// Empty means "nothing at all", which is the default.
        var mayAgreeTo: String = ""
        /// Who the call is on behalf of. Shown to the person who answers.
        var name: String = ""
        /// The to-do this belongs to, so the result lands back on it.
        var itemID: String?
        /// The language the ANSWER comes back in, as the app's explanation
        /// language ("en", "es", "zh-Hans"). The call itself is always in
        /// English — that gap is the whole point of the feature — but the
        /// write-up is for the user to read.
        var language: String = "en"
    }

    struct Placed {
        let actionID: String
        let status: String
        /// True when the Worker is in dry-run: everything ran, nothing was
        /// dialled. Worth surfacing in a debug build so a silent no-op can't be
        /// mistaken for a real call.
        let dryRun: Bool
        let callsUsed: Int
        let callsLimit: Int
    }

    // ── What comes back ─────────────────────────────────────────────────────

    /// The structured answer, extracted by the provider against the schema the
    /// Worker sends. Enums carry `unknown` on purpose — forcing a yes/no out of
    /// a call nobody answered would put a confident wrong answer on a to-do.
    struct CallOutcome: Decodable, Equatable {
        var outcome: String?          // done | partially | not_done | unknown
        var detail: String?
        var agreed: String?
        var needsUserAction: String?  // yes | no | unknown
        var nextStep: String?

        enum CodingKeys: String, CodingKey {
            case outcome, detail, agreed
            case needsUserAction = "needs_user_action"
            case nextStep = "next_step"
        }
    }

    struct Confidence: Decodable, Equatable {
        var score: Double?
        var label: String?
    }

    struct CallResult: Decodable, Equatable {
        var summary: String?
        var structured: CallOutcome?
        var taskCompleted: Bool?
        var confidence: Confidence?
        var evidence: [String] = []
    }

    struct ActionStatus: Decodable, Equatable {
        var actionID: String
        var status: String            // queued | in_progress | completed | failed | canceled
        var result: CallResult?
        var transcript: String?
        var failureCode: String?
        /// When the Worker saw the call end, as ISO 8601. A call picked up the
        /// next morning is dated by this, not by when the phone noticed.
        var endedAt: String? = nil

        enum CodingKeys: String, CodingKey {
            case actionID = "actionId"
            case status, result, transcript, failureCode, endedAt
        }

        /// Nothing more will change. The caller can stop polling.
        var isFinished: Bool { ["completed", "failed", "canceled"].contains(status) }

        /// `endedAt` as a date. The Worker writes `toISOString()`, which carries
        /// milliseconds, and the default ISO parser rejects those.
        var endedDate: Date? {
            guard let endedAt else { return nil }
            return try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(endedAt)
        }
    }

    // ── Errors ──────────────────────────────────────────────────────────────
    //
    // These map the Worker's machine-readable codes, because the UI has to react
    // differently to each: a free account needs the paywall, a used-up allowance
    // needs a plain sentence, and an unsafe goal needs the user to edit the text.

    enum ActionError: LocalizedError, Equatable {
        case notConfigured
        case noSession
        case notInvited
        case emailUnverified
        case plusRequired
        case tierUnavailable
        case quotaExceeded(limit: Int)
        case callInProgress
        case unsafeGoal
        case undialable(String)        // invalid_phone / premium_rate / emergency_or_service
        case providerFailed(String)
        case server(Int)
        case decode

        var errorDescription: String? {
            switch self {
            case .notConfigured, .noSession:
                return String(localized: "Sign in to have Tadah make a call.")
            case .notInvited:
                return String(localized: "Tadah Calls isn't open to everyone yet.")
            case .emailUnverified:
                return String(localized: "Verify your email address before Tadah calls for you.")
            case .plusRequired:
                return String(localized: "Tadah Plus is needed to have Tadah make a call.")
            case .tierUnavailable:
                return String(localized: "Can't confirm your membership right now. Please try again shortly.")
            case .quotaExceeded(let limit):
                return String(localized: "You've used all \(limit) of this month's calls.")
            case .callInProgress:
                return String(localized: "Tadah is already on a call for you.")
            case .unsafeGoal:
                return String(localized: "Please take card, bank and Social Security numbers out of the request — Tadah never reads those out on a call.")
            case .undialable:
                return String(localized: "Tadah can't call that number.")
            case .providerFailed, .server, .decode:
                return String(localized: "Tadah couldn't place the call. Please try again.")
            }
        }

        /// Only this one should open the paywall.
        var needsPlus: Bool { self == .plusRequired }
    }

    // ── Placing a call ──────────────────────────────────────────────────────

    /// Ask the Worker to place the call. Returns as soon as it has been handed to
    /// the provider — the answer arrives later, via `status(of:)`.
    static func placeCall(_ request: CallRequest) async throws -> Placed {
        guard let endpoint = BackendConfig.actionsEndpoint else { throw ActionError.notConfigured }
        guard let token = SessionStore.token else { throw ActionError.noSession }

        var body: [String: String] = [
            "kind": "call",
            "phone": request.phone,
            "goal": request.goal,
            "mayAgreeTo": request.mayAgreeTo,
            "name": request.name,
            "language": request.language,
        ]
        if let itemID = request.itemID { body["itemId"] = itemID }

        let (data, http) = try await send(to: endpoint, session: token, body: body)
        guard (200..<300).contains(http.statusCode) else {
            throw error(from: data, status: http.statusCode)
        }
        struct Response: Decodable {
            let actionId: String
            let status: String
            let dryRun: Bool?
            let callsUsed: Int?
            let callsLimit: Int?
        }
        guard let r = try? JSONDecoder().decode(Response.self, from: data) else { throw ActionError.decode }
        return Placed(actionID: r.actionId, status: r.status, dryRun: r.dryRun ?? false,
                      callsUsed: r.callsUsed ?? 0, callsLimit: r.callsLimit ?? 0)
    }

    /// Where the call has got to. The Worker asks the provider on our behalf, so
    /// this is authoritative even if the provider's callback never arrived.
    static func status(of actionID: String) async throws -> ActionStatus {
        guard let endpoint = BackendConfig.actionStatusEndpoint else { throw ActionError.notConfigured }
        guard let token = SessionStore.token else { throw ActionError.noSession }

        let (data, http) = try await send(to: endpoint, session: token, body: ["actionId": actionID])
        guard (200..<300).contains(http.statusCode) else {
            throw error(from: data, status: http.statusCode)
        }
        guard let status = try? JSONDecoder().decode(ActionStatus.self, from: data) else { throw ActionError.decode }
        return status
    }

    // ── Plumbing ────────────────────────────────────────────────────────────

    private static func send(to endpoint: URL,
                             session: String,
                             body: [String: String]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(session, forHTTPHeaderField: "X-Tadah-Session")
        if !BackendConfig.proxyToken.isEmpty {
            req.setValue(BackendConfig.proxyToken, forHTTPHeaderField: "X-Cuevi-Token")
        }
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ActionError.server(-1) }
        return (data, http)
    }

    /// Turn the Worker's `{ error, message, limit }` into something the UI can
    /// branch on. Falls back to the status code when the body isn't ours.
    private static func error(from data: Data, status: Int) -> ActionError {
        struct Failure: Decodable { let error: String?; let limit: Int? }
        let failure = try? JSONDecoder().decode(Failure.self, from: data)
        switch failure?.error {
        case "not_invited":          return .notInvited
        case "email_unverified":     return .emailUnverified
        case "plus_required":        return .plusRequired
        case "tier_unavailable":     return .tierUnavailable
        case "quota_exceeded":       return .quotaExceeded(limit: failure?.limit ?? 0)
        case "call_in_progress":     return .callInProgress
        case "unsafe_goal":          return .unsafeGoal
        case "invalid_phone", "premium_rate", "emergency_or_service":
            return .undialable(failure?.error ?? "invalid_phone")
        case .some(let code) where status >= 500 || status == 402:
            return .providerFailed(code)
        default:
            return status == 401 ? .noSession : .server(status)
        }
    }
}
