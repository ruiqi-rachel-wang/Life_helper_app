# Part 7 — Photo sync (planned for 1.1, NOT in 1.0)

> Decided 2026-08-26. Rachel: "I want all users to see the picture." Agreed the
> destination is right — a to-do without its document image on your second device
> is half a feature — and agreed to ship 1.0 without it, because it needs a
> privacy policy reversal that testers have already read the opposite of.

## Why it isn't in 1.0

The published privacy policy promises the opposite in **six places**, e.g.
*"Your scanned photos stay on your device. They are not uploaded to your
account, even when you are signed in."* Reversing that is entirely legitimate —
it is an improvement people are asking for — but it should be a deliberate,
announced change, not something bundled quietly into a first release. It also
requires an App Store privacy-label change, and a wrong label is a rejection.

Note `ReviewView.scanImageData` already carries the comment *"backing them up to
the account is a planned OPTION, not a promise that they stay local"* — the code
anticipated this; only the published policy went further.

It is purely additive: no migration, nothing breaks, 1.0 users lose nothing.

## What exists already (done in 1.0, reusable)

- **`PhotoStash`** — photos set aside by item id at sign-out and re-attached when
  the item is pulled back. Same-device only. The upload path replaces its ROLE
  but not the type: it is still the right place to hold bytes that have not
  reached the server yet.
- **Compression on both entry points.** Scans were always
  `jpegData(compressionQuality: 0.7)`; the picker path was storing the raw
  3-8 MB original until 2026-08-26 and now downscales to 1500px first. Uploading
  uncompressed originals was never viable.

## Backend

- R2 bucket + binding in `wrangler.toml` (none today).
- `PUT /photos/:itemId` — session-authenticated, key `${user_id}/${item_id}`, a
  hard size cap (~2 MB after client compression), content-type allow-list.
- `GET /photos/:itemId` — same scoping. Never trust an item id alone; the key
  must be derived from the session's user_id or one account can read another's.
- Delete the object when the task is deleted, and purge the whole `${user_id}/`
  prefix on account deletion. An orphaned document image is the worst possible
  leftover.
- Per-tier storage cap with real accounting (free vs Plus), same shape as
  `ai_usage`.

## Client

- Upload AFTER the task push succeeds, retryable, and **never blocking task
  sync** — a failed photo must not stall someone's to-dos.
- Download lazily. Pulling every image on first sign-in is a bad first
  experience on cellular; fetch when the Detail screen opens, cache locally.
- Resize to ~1600px / quality 0.6 before upload (200-400 KB typical).

## Legal + store (do these FIRST, they gate submission)

- Rewrite `LegalContent.swift` — six passages, then `make_legal_pages.py`, then
  deploy with `--branch main`.
- App Store privacy label: add **User Content → Photos**, *Linked to You*.
- In-app **Profile → Privacy** copy, including what the existing "Save uploaded
  photos" toggle now means.
- Tell existing testers before it lands.

## Cost — not the constraint

R2 free tier is 10 GB storage and 1M writes/month, and **egress is free**. At
~300 KB compressed that is roughly 33,000 photos before paying anything, then
$0.015/GB-month. 100 GB is $1.50/month.

## Open question

Opt-in or on by default? On-by-default delivers the feature people want; opt-in
keeps the current promise true for anyone who declines, at the cost of most
people never seeing photos on a second device. Rachel leaned toward everyone
seeing them; revisit when the policy is rewritten.
