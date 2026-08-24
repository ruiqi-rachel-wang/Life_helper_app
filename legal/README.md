# Legal & privacy documents

Drafts of everything Tadah needs for a **free** TestFlight / App Store release.

| File | What it's for |
|---|---|
| `privacy-policy.md` | Public Privacy Policy (App Store **requires** a public URL) |
| `terms-of-service.md` | Terms + the liability & AI-accuracy disclaimers (Tadah's biggest risk) |
| `app-store-privacy-label.md` | Exact answers for the App Store Connect "privacy nutrition label" |

> ⚠️ **These are templates, not legal advice.** Tadah advises on tax, immigration,
> insurance, medical, and legal topics, so have a professional review them before a
> **paid or public** launch. They do not block the free 10-person TestFlight beta.

## Owner details (filled in 2026-06-18)
The documents are completed for the current setup:
- **Responsible party:** sole proprietor, New York, United States (add your legal name or LLC before a public launch — keep it off the public doc if you prefer).
- **Governing law:** New York, United States (Terms §12).
- **Contact:** `support.tadah@gmail.com` (placeholder role address — set up a dedicated inbox; not a personal email).

If you form an LLC or move states later, update the responsible-party and
governing-law sections in both documents.

## Hosting (live now — Cloudflare Pages, free)
These docs are deployed to **https://tadah-legal.pages.dev/** (`privacy.html`, `terms.html`).
GitHub Pages is **not** used: this repo is private, and GitHub Pages needs a paid plan for
private repos (and raw GitHub file URLs aren't public).

To re-publish after editing the policy: regenerate the HTML in `docs/` (the generator
lives in the project history), then from the repo root run
`npx wrangler@3 pages deploy docs --project-name=tadah-legal --branch=main`.
Verify the URL loads in a **private/incognito** window (anonymously) before submitting.

## How the app shows these
The in-app **Profile → About & Legal** screens render this text directly (not a web
link): the privacy policy and terms are embedded in
[`Tadah/Tadah/App/LegalContent.swift`](../Tadah/Tadah/App/LegalContent.swift) and shown
by `LegalDocumentView`. Keep `LegalContent.swift` in sync with these `.md` files (it's
generated from them). For the App Store **privacy-policy URL** field, host
`privacy-policy.md` (see above) and use that link.
