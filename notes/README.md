# Tadah notes

Working documents. Nothing here is compiled or deployed.

| File | What it is |
| --- | --- |
| `shipaton_2026.md` | **Current focus.** RevenueCat Shipaton entry — eligibility, categories, the new video, submission checklist. Due Sept 30. |
| `roadmap.md` | **What's next.** Fixes, updates, new features, in order. |
| `how_tadah_is_built.md` | **What exists.** Stack, folders, Worker routes, limits, the names that must never change. |
| `review_1.1.md` | Source review since 1.0 build 6. **C6–C10 are still open** — P2 issues, read before touching Calls. |
| `app_store_listing.md` | Paste-ready App Store copy + questionnaire answers. |
| `how_to_view_tester_data.md` | `wrangler d1 execute` queries for the metrics DB. |
| `sample_documents.md` | Real OCR samples with the ideal extraction, for tuning the scan prompt. |

## Shipped

- **1.0 — live on the App Store September 10, 2026.** Understand the letter.
- **1.1 — live September 17, 2026.** Tadah Calls: the app phones a business for you.

Cleaned up 2026-09-18: `release_1.0_checklist.md` and `release_1.1.md` were
deleted — both releases are live, so they were checklists for finished work.
`review_1.1.md` was kept because C6–C10 are still open issues, not history.
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
- `../../misc/calle_video/` — the video pipeline (`make_video.py`, frames,
  voice takes). Outside the repo. Source material for the Shipaton recut.
