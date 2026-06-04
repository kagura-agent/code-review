# cove#178 — replace ad-hoc migrations with versioned system

**Date:** 2026-06-04
**Verdict:** ⚠️ Needs Changes (3/3 unanimous)

## Consensus Critical
- PRAGMA foreign_keys = OFF is no-op inside transaction (3/3) — Stella reproduced locally

## Reviewer Performance (Round 1)
| Reviewer | Verdict | Notes |
|----------|---------|-------|
| 🌟 Stella | ⚠️ | Reproduced the bug locally with real data. Deepest — 4m43s. Found future-version handling gap + FK check suggestion |
| 🌠 Nova | ⚠️ | Most suggestions (7). createAllTables idempotency fragility was unique. Transaction rollback test gap unique |
| 💫 Vega | ⚠️ | Cleanest fix suggestion (move pragma outside runMigrations). Concise and accurate |

## Layer 2 — Prompt Evolution Check
- SQLite PRAGMA-in-transaction is a known gotcha — appeared in cove#168 R3 too (PRAGMA finally block)
- This is now the 3rd PR where SQLite migration correctness is a finding
- **Consider adding SQLite-specific dimension to prompt?** No — too project-specific. Better as a cove.prompt.md entry if created
- "Future version" test gap — test not testing what it claims — appeared only in this PR. Track
- No prompt changes needed ✅

## Process Notes
- FlowForge workflow: 3rd consecutive run ✅
- All 3 reviewers wrote to files, all readable ✅
- Stella ran full build + reproduced bug locally — her approach (reading source beyond diff) pays off
