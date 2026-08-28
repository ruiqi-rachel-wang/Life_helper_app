# Tadah notes

Working documents. Nothing here is compiled or deployed.

## Shipping 1.0 — the ones you're using now

| File | What it is |
| --- | --- |
| `release_1.0_checklist.md` | **Start here.** Every step left before submitting. |
| `app_store_listing.md` | Paste-ready App Store copy + questionnaire answers. |
| `tadah_plus_setup.md` | Subscription fields + the App Review notes to paste. |

## Where the project stands

| File | What it is |
| --- | --- |
| `build_plan.md` | **Canonical status.** Architecture + what is built. |
| `future_features.md` | Roadmap, as numbered Parts. |
| `photo_sync_plan.md` | Part 7 — photo sync, planned for 1.1. |
| `hackathon_calls_plan.md` | Part 6 — Tadah Calls. |
| `later_ideas.md` | Deferred further out. §8 is engineering debt. |
| `how_to_view_tester_data.md` | `wrangler d1 execute` queries for the metrics DB. |

## `archive/` — history, don't edit

Kept because they explain *why*, not what to do next. Nothing current points at
them for instructions.

`testflight_build3_notes.md` · `testflight_build4_notes.md` ·
`guide_depth_before_after.md` · `translations_review.md` · `paywall_copy.md` ·
`sample_documents.md` · `guides_content.txt`

## Not in here, on purpose

- `../legal/` — privacy + terms **source**, and `make_legal_pages.py`.
  Edit `LegalContent.swift`, then run that script. Never edit the HTML by hand.
- `../docs/` — the generated legal pages. Deploy from the repo root:
  `npx wrangler pages deploy docs --project-name tadah-legal --branch main --commit-dirty=true`
- `../testing files/` — personal test documents (PII). Gitignored, never commit.
