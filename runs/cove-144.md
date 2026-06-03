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

## Round 2 (after migration fix)
| Reviewer | Model | Verdict |
|----------|-------|--------|
| Stella | GPT-5.5 | ⚠️ Needs Changes |
| Nova | Claude Opus 4.7 | ✅ Ready |
| Vega | Gemini 3.1 Pro | ✅ Ready |

### R1 Critical: RESOLVED
Migration ordering fixed — renames before CREATE TABLE.

### New finding (Stella only)
Recovery path for "both old and new tables exist" does DROP TABLE without checking if new table has data. Narrow edge case (requires running buggy R1 code + creating data during that window). Nova and Vega didn't flag it.

## Reviewer Assessment (R1+R2)
- **Stella**: Found R1 critical, then in R2 went deeper than others — reproduced the recovery path edge case. Most thorough on migration safety. 2 rounds of running actual SQLite tests.
- **Nova**: Best at tracing full migration paths. Correctly ✅ R2 — the edge case is genuinely narrow. Good architectural analysis.
- **Vega**: 5th consecutive clean run. Correctly identified R1 critical, correctly ✅ R2. Improving steadily.

## Process Notes
- R1: All 3 converging on same critical = high confidence, genuine bug.
- R2: Stella finding a deeper edge case that others missed = value of model diversity. GPT-5.5 was the most cautious/thorough on migration safety.
- First PR with a real data-loss catch (R1) and a split verdict (R2). Both are milestones.
