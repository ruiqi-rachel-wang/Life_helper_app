# Tadah notes

Every working document lives here. Nothing in this folder is compiled or
deployed — it is the written record of what was decided and why.

## Start here

| File | What it is |
| --- | --- |
| `build_plan.md` | **Canonical status.** Architecture + what is built. Read first. |
| `future_features.md` | The current roadmap, organised as numbered Parts. |
| `later_ideas.md` | Deferred further out than `future_features.md`. Includes §8 engineering debt. |
| `testflight_build4_notes.md` | **Authoritative for the current build.** Upload checklist + What to Test. |

## Reference

| File | What it is |
| --- | --- |
| `how_to_view_tester_data.md` | `wrangler d1 execute` queries for the metrics database. |
| `hackathon_calls_plan.md` | **Part 6 — Tadah Calls.** Phases, guardrails, cost caps. |
| `tadah_plus_setup.md` | RevenueCat + App Store Connect subscription setup. |
| `paywall_copy.md` | Paywall wording. |
| `sample_documents.md` | The scan-parser tuning corpus. Files live in `../testing files/`. |
| `guides_content.txt` | Source content for the in-app guides. |
| `guide_depth_before_after.md` | Guide rewrite, build 2 vs. now, per step. |
| `translations_review.md` | Spanish + Simplified Chinese review pass. |
| `testflight_build3_notes.md` | History only. Build 3 was never uploaded; build 4 supersedes it. |

## Not in here, on purpose

- `../legal/` — privacy policy and terms **source**, plus `make_legal_pages.py`.
  Edit `LegalContent.swift`, then run that script. Never edit the HTML by hand.
- `../docs/` — the generated legal pages. Deployed with
  `npx wrangler pages deploy docs --project-name cuevi-legal` **from the repo root**.
- `../testing files/` — personal test documents (PII). Gitignored, never commit.
