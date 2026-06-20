# Legal & privacy documents

Drafts of everything Cuevi needs for a **free** TestFlight / App Store release.

| File | What it's for |
|---|---|
| `privacy-policy.md` | Public Privacy Policy (App Store **requires** a public URL) |
| `terms-of-service.md` | Terms + the liability & AI-accuracy disclaimers (Cuevi's biggest risk) |
| `app-store-privacy-label.md` | Exact answers for the App Store Connect "privacy nutrition label" |

> ⚠️ **These are templates, not legal advice.** Cuevi advises on tax, immigration,
> insurance, medical, and legal topics, so have a professional review them before a
> **paid or public** launch. They do not block the free 10-person TestFlight beta.

## Owner details (filled in 2026-06-18)
The documents are completed for the current setup:
- **Responsible party:** sole proprietor, New York, United States (add your legal name or LLC before a public launch — keep it off the public doc if you prefer).
- **Governing law:** New York, United States (Terms §12).
- **Contact:** `support@cuevi.app` (placeholder role address — set up a dedicated inbox; not a personal email).

If you form an LLC or move states later, update the responsible-party and
governing-law sections in both documents.

## Hosting (you need a public URL for the App Store)
**Easiest — GitHub Pages (free):**
1. Push these files to GitHub (they live in this repo under `legal/`).
2. On GitHub: **Settings → Pages → Build from branch → `main` → `/ (root)`** → Save.
3. After it builds, your policy is at:
   `https://ruiqi-rachel-wang.github.io/Life_helper_app/legal/privacy-policy.md`
   (GitHub renders Markdown to a web page.)

**Or, with zero setup:** the GitHub file URL itself is already public and works as
the App Store URL:
`https://github.com/ruiqi-rachel-wang/Life_helper_app/blob/main/legal/privacy-policy.md`
*(This only works once these files are committed and pushed.)*

## Wire the links into the app
The in-app **Profile → About & Legal** rows and the App Store fields read from
[`Cuevi/Cuevi/App/LegalConfig.swift`](../Cuevi/Cuevi/App/LegalConfig.swift) (the
Xcode project folder is still named `Cuevi` internally — see the build plan). Update
the two URLs there if you switch to GitHub Pages (or your own domain) later.
