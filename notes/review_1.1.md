# Tadah 1.1 review — Call-E and changes since 1.0

Reviewed 2026-09-16. The original findings are preserved below; the status table records the subsequent fixes. The first fixes are committed as `7f6d966` and were deployed as `ddcc4a7e-3f88-4443-84ed-f8328d6fa36d`. The continuation below is a subsequent working-tree change; the updated app has not been uploaded.

## Focused recheck of `13913dd` (September 17)

Three deterministic app regressions reproduced in new tests before the fixes:

- Opening a to-do while call creation is returning can consume its rejected status, delete the pending pointer, and discard the original clarifying question. Status refresh and foreground resumption now leave creation to finish its own reply.
- A status read begun before a new call can return afterward and overwrite the newer refusal. Refresh now checks that the local phase and pending call are unchanged across the await.
- Rejection clears the phase but previously left an older cached answer, which immediately reappeared instead of the call offer. Both rejection paths now clear that cached answer.

Tests use injected call/session readers, so the race order is controlled and no real calls or account changes are needed. The three regression tests failed before the fixes. Worker recheck: 68 helper and 116 route tests passed; Worker source is unchanged and needs no redeploy. Final iOS validation: **357 tests in 32 suites passed**, including all three new race tests. `git diff --check` passed. Logs: `/tmp/tadah-rereview-before.log` (reproduced failures), `/tmp/tadah-rereview-final.log` (passing app suite), `/tmp/tadah-rereview-worker.log` (passing Worker suites). “For your call” and the safety-filter policy are unchanged. These follow-up edits are not yet committed or uploaded.

## Status after fixes (2026-09-16, evening)

Continuation validated: **354 iOS tests** (31 suites), **68 Worker helper tests**, and **116 route tests** pass. `git diff --check` passes. Worker deployed on September 16 as **`0d2b1746-6e3a-4e05-8d2c-7a76cc6788fe`**, including both the daily retention and minute call-recovery triggers. Unauthenticated item-status lookup returns 401. These follow-up source changes are not yet committed or uploaded as an app build. A new live call still needs testing.

| Item | Status | What changed |
| --- | --- | --- |
| C1 deletion | **Fixed (account + local)** | Account delete also removes `actions`, their `action_events`, the user's `action_usage` and `email_verifications`; the global counter stays. A create racing a deletion re-checks the account before dialling. Deleting a to-do (here or synced from another device) clears its local call answer and pointer. CALL-E's own records are not deleted. Server `actions` rows survive a single to-do's deletion, as the privacy policy describes. |
| C2 account change | **Fixed (minimal)** | Pending calls record their owner. Only the owner's session watches or resumes them; a different account stops the watch without deleting the pointer; the Plus-recovery retry refuses to send under a changed account; calls resume on sign-in. |
| C3 lost responses | **Implemented, with a provider limitation** | The app persists a request UUID before sending; Worker replays that ID without another provider POST or charge, regardless of hour/month. Uncertain creation stays live, malformed success is checked, and authenticated webhook metadata recovers an unknown provider ID. No automatic redial. See remaining limitations below. |
| C4 admission race | **Fixed** | One conditional INSERT claims the live slot before charging; quota refusals release it. Test: two simultaneous creates → one 200, one 409, one charge. |
| C5 reference consent | **Fixed** | The suggested question is built without the account number (plain, spaced, dashed, `#`, inside Chinese text), and the request strips it whenever the switch is off. Switch on sends it once. |
| C6 saved tasks | **Implemented** | New saves persist/sync the reviewed offer through a V4 migration. Saved to-dos offer a call with sign-in/Plus/verification gates; when no number is available, retained scripts appear in a separate “For your call” card. Status lookup by to-do retrieves answers on another device in the same account. The removed step-detail section stays removed. |
| C7 recipient pairing | **Improved conservatively** | Explicit phone matches select the corresponding step/question, instead of the first script. Multiple unnumbered call steps, conflicting numbers, or multiple numbers in one step fall back to an editable neutral question. One unnumbered call step is still an inferred match; explicit per-office extraction remains a follow-up. |
| C8 lengths | **Fixed** | The confirm page counts the question as sent (UTF-16, like the Worker) and blocks Call now over 600, with how much to cut; custom permission over 200 is blocked. The Worker refuses an over-long authorisation instead of truncating it, and the app says "too long" instead of the catch-all. |
| C9 safety filter | **Implemented for supported languages** | Added Spanish and simplified/traditional Chinese sensitive-data patterns, Unicode/full-width normalization, zero-width removal and dotted card numbers; legitimate bill references remain allowed. User-authorized payment plans/due dates remain permitted. This is a text heuristic, not comprehensive detection of arbitrary encodings. |
| C10 webhook recovery | **Implemented** | Minute cron reads up to 25 known provider calls; app/cron share an atomic refresh claim. Webhook fetch failures return 503 and are not deduplicated until successful processing. Verified metadata can recover an uncertain creation. Neither path places another call. |

Also fixed tonight: CALL-E's `call_not_ready` question is shown on the to-do instead of "couldn't place the call", and a definite CALL-E refusal is stored as `rejected`.

## Continuation: validation and remaining limits

Validation logs: `/tmp/tadah-remaining-ios-verified.log`, `/tmp/tadah-remaining-worker-final.log`, `/tmp/tadah-remaining-deploy.log`.

- Automated coverage: durable request replay, simultaneous delivery/one charge, malformed provider success, lost provider reply recovered by webhook, webhook retry after a provider outage, mismatched authenticated metadata, app/cron refresh races, scheduled completion without app polling, and account-scoped lookup by to-do.
- iOS coverage: V1 and V3 stores migrate, V3 profiles/reminders/steps survive, a model-extracted number survives save and DTO sync, office/question pairing, and uncertain transport/decode errors are not presented as safe retries.
- **C3 residual:** if both the provider creation reply and every webhook are lost, Tadah has no provider ID to read. [CALL-E's documented API](https://docs.heycall-e.com/api-reference/calls) exposes call reads by ID; no lookup by Tadah's request UUID was found. The app keeps an uncertain state. A request that never reached the Worker can likewise remain uncertain; recovery/abandonment UX still needs a design that cannot redial an accepted call. Old app builds without request IDs retain the legacy hour-key behavior.
- **C6 legacy data:** old to-dos that discarded the extracted phone cannot reconstruct it unless a retained step contains a number. New saves preserve it. Older app versions can also drop the new field when editing/syncing; use the new build on devices testing this path.
- **C7 residual:** fully reliable named-office pairing needs a structured recipient/number/question tuple from extraction. Current matching uses explicit numbers when available and declines to borrow an ambiguous script; a single unnumbered script remains inferred.
- **Device test still required:** new scan → confirm → background/close app → reopen saved to-do; a saved to-do call; Spanish/Chinese text; account switch; same-account answer on another device. No live call was placed by this continuation.
- Minute scheduling uses [Cloudflare Cron Triggers](https://developers.cloudflare.com/workers/configuration/cron-triggers/); the daily retention schedule remains separate.

## Scope and release baseline

Compared `5970512` (1.0 build 6, identified by `release_1.0_checklist.md`) with `f7718db` (current HEAD): 11 commits, 46 changed files. This is a source comparison; the exact binary currently in the App Store and the deployed Worker were not independently inspected. The only repository tags are older build tags. Much of the apparent diff volume is string-catalog reformatting.

Concurrent workspace edits appeared during validation: definite-rejection retry keys, CALL-E clarification questions, their app error handling/translations, and tests. They were preserved, not authored by this review. The combined Worker suite and focused iOS call suites were rerun after those edits. They do not resolve C3's durable-intent/uncertain-placement problem.

| Area | Change since 1.0 | Review result |
| --- | --- | --- |
| Document extraction | Explicit document phone field, validated call offers, editable confirmation | Extensions fixed; recipient/goal association and reference-number consent need follow-up |
| Calling | Plus + verified-email gates, 5 calls/month/account, global cap, provider creation, status polling, webhooks | Good sequential flow; concurrent admission and uncertain creation remain unsafe to describe as handled |
| iOS call lifecycle | App-owned placement/polling, background time, immediate navigation to the saved to-do | Better than screen-owned tasks; missing durable intent and account ownership remain |
| Results | Structured result in the explanation language; local call card; server transcript retention | Status races fixed; local-only results and deletion gaps remain |
| Account | Email verification UI/API; RevenueCat receipt reattachment after a Plus refusal | Failed-send resend fixed; account changes during async work need coverage |
| Product/UI | Confirm screen, permissions, translated copy, scan error messages, removal of step scripts | Saved-task call access and manual scripts regress |
| Metrics | `action_offered`, `action_accepted`, `action_completed` and matching server allow-list | Existing consent applies; these measure interaction/call termination, not successful task completion |
| Release/privacy | Call disclosure, phone-number label instructions, 1.1/build 8 | Release checklist still applies; deletion behavior does not yet meet the documented retention lifecycle |

## Small fixes made in this review

1. **Finished calls stay finished.** `actions.js`: status persistence now conditionally updates only live rows. A delayed poll cannot overwrite a webhook's final answer, transcript, or end date. A late successful create response also preserves a terminal status already written by a webhook.
2. **Provider requests reject redirects.** Both authenticated CALL-E fetches use `redirect: "error"`. This prevents forwarding the authorization header and call content to a redirected destination. Cloudflare documents that Workers' follow mode forwards headers, including Authorization, across destinations: [Request API](https://developers.cloudflare.com/workers/runtime-apis/request/).
3. **The spoken name gets the same safety scan as the question.** Previously a profile name containing an SSN-shaped number bypassed validation and was interpolated into the opening sentence. This closes that field bypass; it does not make the text filter comprehensive (see C9).
4. **A failed verification-email send no longer leaves a false cooldown.** An immediate retry previously returned `sent: false` while the UI told the user to check their inbox. The failed request now removes only its own code row, so another request's newer code is preserved.
5. **Phone extensions work in the offer and confirmation.** iOS now removes `ext.`, `extension`, and `x` suffixes before validating, matching the Worker. The original number remains visible, identifier exclusion still applies, and non-ASCII digit strings no longer pass the NANP check.

## Open issues, in priority order

P1 means resolve before broad release. P2 means an actionable product/correctness follow-up. These are source-level findings unless an automated reproduction is explicitly noted.

### C1 · P1 · Call data is omitted from deletion

**Where:** `worker.js` → `handleAccountDelete` (around line 826), sync deletion handling; `CallOffer.swift` → `CallHistory` / `PendingCall` (around line 397).

Deleting an account removes credentials, tasks, profiles, reset codes, and sessions, but never `actions`, `action_events`, `action_usage`, or `email_verifications`. Thus phone numbers, approved questions, names, results, and transcripts remain associated with a deleted user. Deleting an individual to-do also leaves its server action and local result. The transcript sweep eventually clears terminal transcripts, but it does not clear input/result data or transcripts on rows without `ended_at`. No production records were deleted during this review.

**Reproduce:** seed a completed call and an outstanding verification; delete its account with valid credentials; query those four tables. For item deletion, delete a called to-do and inspect its action and UserDefaults entry.

**Required change:** define the complete call-data lifecycle; add scoped deletion in the existing transaction, clear local per-item state, and cover an action/create or webhook already in flight during deletion. Preserve aggregate spend protection without retaining a deleted user's call content. Determine provider-side deletion separately; deleting D1 does not delete CALL-E's records.

**Acceptance:** account/item deletion tests include calls and verification rows; unrelated accounts survive; delayed async work cannot recreate deleted content.

### C2 · P1 · Calls can cross an account change locally

**Where:** `CallCenter.swift` → `place`, `send`, `resumeAll`, `watch`; `ActionsService.swift` → session lookup per request; `TadahApp.swift` → sign-out callback; `CallOffer.swift` → unscoped defaults dictionaries.

Pending calls carry no owner ID. Polling reads whichever session is current on each request. If A starts a call and B signs in, a poll under B receives 404 and deletes A's recovery pointer. An A request already in flight can also finish after sign-out and write local results or metrics into the new session. The Plus recovery retry reads the current session again, so an account change during recovery can submit A's confirmed request under B. Server status reads are correctly user-scoped; this is a client lifecycle problem, not proof of a server cross-account read.

**Required change:** capture owner/session generation at confirmation, scope pending/history by account, stop or detach watchers on identity changes, and check ownership after every await and before any retry. Resume the right account's calls after sign-in completes, not only launch/foreground.

**Acceptance:** A→sign-out→B→A during creation, polling, and Plus recovery neither dials under B nor loses A's result.

### C3 · P1 · Lost creation responses cannot be recovered reliably

**Where:** `CallCenter.swift:96` (pointer saved only after success); `actions.js` → `createProviderCall`, `callIdempotencyKey`, create failure branch; `ActionsService.swift` → error decoding.

If CALL-E accepts a call but the reply is lost, the Worker marks the action failed and retains its allowance. The webhook then ignores that terminal row. If instead the Worker succeeds but the app loses its reply, the app never learns the action ID. Both become “couldn't place the call” with a retry button, even though a phone may already be ringing. There is no lookup by client intent or item to recover it. A successful provider response without an `id` also becomes an unpollable live row.

The hour-based key is not a durable intent: an identical retry across an hour boundary gets a new key, while a same-hour retry reserves another allowance and creates another action. Its metadata contains the new action ID, so the request body changes even when the key matches; actual CALL-E conflict/replay behavior was not verified live. Concurrent edits add a suffix counting rejected actions for the same item. That count is not scoped to phone/task: an uncertain request A, then an edited request B that is rejected, then a retry of A gives A a fresh key too. Recovery of an uncertain accepted call still needs a persisted intent.

**Required change:** persist a client intent before dispatch, uniquely store/reuse it server-side, charge once per intent, validate the provider's response, and model uncertain placement separately from refusal. Recover by intent without creating a new call. Keep automatic redial disabled.

**Acceptance:** dropped app replies, dropped provider replies, malformed 2xx bodies, and retries across an hour/month boundary produce at most one call and one charge, with a recoverable result.

### C4 · P1 · “One call at a time” is a read-then-write race

**Where:** `actions.js:609` through the action insert around line 635.

Two concurrent requests can both read “no live action” before either inserts its queued row. The quota batch limits total spend, but does not serialize admission. Requests for different to-dos have different idempotency keys and can both dial. The existing test checks sequential requests only.

**Required change:** atomically claim the per-user live slot before charging/dialing, with a documented stale-slot recovery path. Coordinate this with C3 rather than adding another independent check.

**Acceptance:** synchronize two create requests at admission; exactly one reaches the provider, the other gets 409, and only one allowance is spent. Test separate sessions for the same Plus account too.

### C5 · P1 · Reference-number opt-in does not cover the generated script

**Where:** `CallOffer.swift` → `from` / `firstCallableGoal`; `CallCenter.swift` → `request`.

The generated `detail.script` is copied verbatim into the goal. `shareAccount == false` only prevents appending the explicit account field; it does not remove a number already present in that script. A result with account `829105512347` and script “Ask about account 829105512347” sends that number with the toggle off. The number is an allowed non-card reference, so the Worker permits it. This contradicts the opt-in copy even though the editable question is visible.

**Required change:** construct the default call question without document identifiers, and make the sharing control govern the final outbound payload. Define how an explicitly user-entered reference should behave. Cover formatted variants and translated scripts.

**Acceptance:** a scan that embeds its reference in the generated script sends no reference while the switch is off; switching it on includes it once.

### C6 · P2 · Saved tasks lose call access and manual scripts

**Where:** `ReviewView.swift` call card; `DetailView.swift:66`; `StepDetailView.swift:141`; `ActionItem.swift` / `TaskDTO.swift`.

The offer exists only on Review; Detail shows a card only after a call has started. Save normally, cancel confirmation, or reopen an older item: there is no offer. The newly extracted phone is not persisted in the task DTO. Meanwhile “What to say” was removed from every step, including tasks with no call record and users who call manually. Results are also stored only on the originating device, so synced tasks on another device have no call answer.

**Required change:** retain recipient/offer data on the saved task or expose owned actions through the backend; decide where a manual script remains available. Persist/sync call references and retrieve results by ownership. Treat this as one coherent saved-task design change.

**Acceptance:** saving without calling preserves a later call entry point and a readable manual script; a second signed-in device can retrieve an existing call's answer.

### C7 · P2 · Recipient and goal can refer to different offices

**Where:** `CallOffer.swift` → model-phone branch and `firstCallableGoal`.

The model's single document-level phone is combined with the first nonempty script, without checking whether that script names another number or office. For example, a document can print an insurer service number while its first action is to call a clinic. Existing structural/identifier validation does not establish that the goal belongs to the selected recipient.

**Required change:** extract or derive a recipient/number/goal tuple for a particular step; decline ambiguous offers or require explicit selection.

**Acceptance:** multi-office and multi-number document fixtures never silently pair one office's number with another office's request.

### C8 · P2 · Length limits can reject or change the approved request

**Where:** `CallConfirmView.swift` → `canCall`; `CallCenter.swift` → request assembly; `actions.js:581`–`586`.

The editor has no length validation. The server rejects goals over 600 JS characters after the app adds the business and optional reference; the resulting error is generic. Custom permission text is silently truncated to 200 characters, so an important restriction at its end can disappear from what the agent receives. Name text is truncated too.

**Required change:** validate the final assembled request before confirmation and reject overlong authorizations rather than truncating them. Align counting semantics across Swift and JavaScript, especially for emoji/non-BMP characters.

**Acceptance:** limits are visible and actionable before dialing; the approved authorization reaches the provider unchanged.

### C9 · P2 · The safety filter is narrower than the promise

**Where:** `actions.js` → `UNSAFE_PHRASES`, `goalIsUnsafe`, `buildCallTask`; confirmation/privacy copy.

The new name scan closes one bypass, but the remaining filter is English phrases, a hyphenated SSN shape, and Luhn-valid card numbers. Translated descriptions of bank accounts, alternate SSN formatting, and other sensitive text can pass. The Luhn comment is also inaccurate: about one in ten random digit strings passes its checksum. The prompt still tells the agent not to disclose these details; that is different from preventing them reaching the provider.

**Required change:** define supported sensitive-data cases in all three app languages, validate every outbound field, and distinguish programmatic restrictions from instructions given to the calling model. Also resolve the permission to agree to a payment plan versus the prompt's prohibition on any payment or negotiation.

**Acceptance:** multilingual fixtures and allowed reference-number examples demonstrate both protection and acceptable false-positive behavior; displayed promises match the actual controls.

### C10 · P2 · Webhook recovery relies heavily on a client returning

**Where:** `actions.js` → webhook event insertion, provider read, live status refresh.

Events are recorded before their fetch succeeds. A transient provider-read failure is acknowledged as 200/deferred, and repeating the event is then ignored. Status polling can recover an action with a known provider ID, but only while a client still knows and polls it. Reads also check the refresh timestamp before fetching without atomically claiming it, so concurrent readers can exceed the intended throttle.

**Required change:** separate event receipt from successful processing and provide bounded server reconciliation of accepted/uncertain calls. Claim refresh work atomically if the throttle is intended to be a shared limit.

**Acceptance:** a temporary read failure followed by webhook redelivery or scheduled reconciliation produces a final result with the app closed, without redialing.

## Validation and limits

- Baseline Worker: 62 helper tests and 99 route tests passed.
- Four added regressions were run before the fixes and failed as expected: spoken-name safety, redirect policy, stale poll overwrite, failed-email resend.
- After the fixes and an additional early-webhook regression: 62 helper tests and 104 route tests passed. Rerunning against concurrent backend edits also passed: **67 helper + 104 route tests (171 total)**.
- iOS: **338 tests in 29 suites passed** on the iPhone 17 Pro / iOS 26.5 simulator, including both new phone-validation tests and the existing Call Center tests (`xcodebuild test`, scheme `Tadah`, only `TadahTests`, parallel testing disabled). After the concurrent app edits, a focused rerun of `CallOfferTests`, `CallCenterTests`, and `CallRefusalTests` also passed: **44 tests in 4 suites**. UI automation and a Release archive were not run.
- String-catalog audit: 94 new keys; the only new key lacking explicit Spanish/Chinese entries is the punctuation-only `%@ · %@`. This checks catalog presence, not native-speaker quality or visual layout.
- `git diff --check` passed during review. No release/build numbers changed.
- No real calls, emails, account deletions, purchases, deployments, or App Store uploads were performed. Worker tests used isolated D1 and dry-run/mocked providers. Production balance, provider retention, live webhook delivery, subscription transfer behavior, accessibility, and device background termination remain integration checks.

## Suggested work order

1. C3 + C4: durable call intent, uncertain status, one atomic admission and charge.
2. C1 + C2: account/item ownership and full deletion lifecycle, including in-flight requests.
3. C5: make reference-number consent govern the actual payload.
4. C6–C10: saved-task usability, recipient pairing, request validation, multilingual safety, and server recovery.
5. Run the controlled real-device call/relaunch/account-change matrix, then follow `release_1.1.md`. The current upload predates the evening fixes; this review does not authorize a new upload or submission.
