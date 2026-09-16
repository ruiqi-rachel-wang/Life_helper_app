# Tadah notes

Working documents. Nothing here is compiled or deployed.

| File | What it is |
| --- | --- |
| `release_1.1.md` | **Current release.** Remaining deployment and App Review steps for 1.1. |
| `review_1.1.md` | **Source review since 1.0 build 6.** Small fixes, prioritized Call-E issues, and validation. |
| `release_1.0_checklist.md` | Previous release checklist and build 6 review history. |
| `roadmap.md` | **What's next.** Fixes, updates, new features, in order. |
| `how_tadah_is_built.md` | **What exists.** Stack, folders, Worker routes, limits, the names that must never change. |
| `app_store_listing.md` | Paste-ready App Store copy + questionnaire answers. |
| `how_to_view_tester_data.md` | `wrangler d1 execute` queries for the metrics DB. |
| `sample_documents.md` | Real OCR samples with the ideal extraction, for tuning the scan prompt. |

Cleaned up 2026-09-04: the old build plan, twenty review-pass logs, the
translation snapshot, the hackathon plan and the later-ideas piles were folded
into `roadmap.md` / `how_tadah_is_built.md` or deleted. `git log -- notes/`
still has every one of them.

## Not in here, on purpose

- `../legal/` — privacy + terms **source**, and `make_legal_pages.py`.
  Edit `LegalContent.swift`, then run that script. Never edit the HTML by hand.
- `../docs/` — the generated legal pages. Deploy from the repo root:
  `npx wrangler pages deploy docs --project-name tadah-legal --branch main --commit-dirty=true`
- `../testing files/` — personal test documents (PII). Gitignored, never commit.
