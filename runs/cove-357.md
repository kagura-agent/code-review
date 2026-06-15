# Run Record: cove-357

**PR:** kagura-agent/cove#357 — feat: Discord-style message threads (#221)
**Date:** 2026-06-15

## Round 1
**Verdict:** ⚠️ Needs Changes (3/3)

### Consensus Issues
1. Missing `requireBotChannelPermission` on thread-member routes (Stella, Nova)
2. No tests for new auth surface (all 3)
3. Missing input validation on `auto_archive_duration` (all 3)
4. Parent message thread indicator state sync (Stella, Nova)

## Round 2
**Verdict:** ⚠️ Needs Changes (2/3) · ❌ Major Issues (1/3)

### R1 Blockers: All 4 ✅ Fixed
### New Consensus Issues
1. Nested thread creation not blocked (all 3)
2. N+1 active-threads fetch on READY (Nova, Vega)
3. Drag handler listener leak (Nova, Vega)

### Verdict Calibration
- Vega rated ❌ citing N+1 and nested threads; Stella/Nova rated ⚠️
- At small-team scale ⚠️ more appropriate

## Round 3
**Verdict:** ⚠️ Needs Changes (1/3) · ❌ Major Issues (2/3)

### R2 Blockers: All 3 ✅ Fixed
### Must-fix (security)
1. Guild active-threads endpoint leaks threads from hidden channels (all 3)
2. PATCH archive/lock has no permission gate (Nova — new finding)

### Should-fix (correctness)
3. Archived/locked threads still accept message writes (all 3)
4. Bulk delete / clear-all don't update thread message_count (all 3)

### Verdict Calibration
- Stella and Nova rated ❌; Vega rated ⚠️ (reversed from R2)
- Nova escalated aggressively (11 new items) — thorough but some are cleanup-tier
- Applied small-team calibration: 2 security blockers + 2 correctness items, rest post-merge
- Overall ⚠️ with clear fix list

### Reviewer Assessment (R3)
- **Nova**: Most thorough again — 11 new findings, correctly identified the MANAGE_THREADS gate gap (unique). Tendency to escalate everything, but findings are real.
- **Stella**: Found duplicate-thread race condition (unique, good catch). Escalation calibration reasonable.
- **Vega**: Mechanically escalated ALL 9 R2 suggestions to blockers without assessing actual severity. Found ThreadPanel.tsx replicating the emoji bug (unique). Needs better severity calibration — reviewer escalation protocol is meant for real issues, not blanket promotion.

### Process Notes
- R1 → R2 → R3 turnaround very fast (all within same session)
- Communication bug in R1 (forgot webhook + channel reply) — fixed in R2/R3
- Reviewers escalating all non-blocking items is becoming a pattern — may need to update the escalation rule in the review prompt to clarify: escalation applies to items with real correctness/security impact, not cosmetic/cleanup items
