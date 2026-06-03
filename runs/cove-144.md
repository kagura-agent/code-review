# PR #144 — refactor: rename scenes → channels

**Repo**: kagura-agent/cove
**Reviewed**: 2026-06-03
**Files**: 13 (+110/-85)
**FlowForge**: #3424

## Verdicts
| Reviewer | Model | Verdict |
|----------|-------|---------|
| Stella | GPT-5.5 | ⚠️ Needs Changes |
| Nova | Claude Opus 4.7 | ⚠️ Needs Changes |
| Vega | Gemini 3.1 Pro | ❌ Major Issues |

## Overall: ⚠️ Needs Changes

## Critical Finding (3/3 consensus)
**Migration ordering causes silent data loss on existing DBs.**
`CREATE TABLE IF NOT EXISTS channels` runs before `ALTER TABLE scenes RENAME TO channels`.
On existing DB: creates empty table → rename fails silently → old data orphaned → app sees empty channels.

This is the strongest consensus finding so far — all 3 models independently identified the same data-loss path with the same root cause and same fix.

## Reviewer Assessment
- **Stella**: Reproduced the bug with a minimal SQLite test. Also caught API field rename compatibility concern and stale bundle.js. ⚠️ rating correct.
- **Nova**: Most detailed analysis again. Traced the full failure path including why column renames work (CREATE is no-op) but table renames don't. Also caught SQL alias inconsistency and STATE_DELETE/UPDATE casing mismatch. ⚠️ correct.
- **Vega**: Correctly identified the same critical bug. ❌ rating is defensible given data loss severity. Concise but accurate. 4th consecutive reliable run.

## Process Notes
- All 3 reviewers converging on the same critical with the same fix suggests this is a genuine, unambiguous bug.
- This is the first PR where the review panel caught a real data-loss path. Good validation of the multi-model approach.
- Stella's SQLite reproduction is the gold standard — actually running code to verify the theory.
