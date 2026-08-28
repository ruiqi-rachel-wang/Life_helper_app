# Tadah notes

Working documents. Nothing here is compiled or deployed.

| File | What it is |
| --- | --- |
| `release_1.0_checklist.md` | **Start here.** Every step left before submitting. |
| `app_store_listing.md` | Paste-ready App Store copy + questionnaire answers. |
| `tadah_plus_setup.md` | Subscription fields + the App Review notes to paste. |
| `build_plan.md` | **Where the project is.** Architecture + what is built. |
| `roadmap.md` | **Where it's going.** Next parts, deferred pile, engineering debt. |
| `photo_sync_plan.md` | Part 7 — photo sync, the next thing after 1.0. |
| `how_to_view_tester_data.md` | `wrangler d1 execute` queries for the metrics DB. |

## `archive/` — history, don't edit

Kept because they explain *why*. Nothing current points at them for instructions.

## Not in here, on purpose

- `../legal/` — privacy + terms **source**, and `make_legal_pages.py`.
  Edit `LegalContent.swift`, then run that script. Never edit the HTML by hand.
- `../docs/` — the generated legal pages. Deploy from the repo root:
  `npx wrangler pages deploy docs --project-name tadah-legal --branch main --commit-dirty=true`
- `../testing files/` — personal test documents (PII). Gitignored, never commit.
