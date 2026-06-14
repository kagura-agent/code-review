# Run Record: cove-348

**PR:** kagura-agent/cove#348 — feat: custom display name (global_name) support
**Date:** 2026-06-14
**Round:** 1
**Verdict:** ⚠️ Needs Changes (unanimous)

## Reviewers
- 🌟 Stella (GPT-5.5): ⚠️ Needs Changes
- 🌠 Nova (Claude Opus 4.7): ⚠️ Needs Changes
- 💫 Vega (Gemini 3.1 Pro): ⚠️ Needs Changes

## Key Findings
1. `toUser()` in members.ts hardcodes `global_name: null` (Stella unique find)
2. Empty string not normalized to null server-side (Stella + Nova)
3. No control char / zero-width validation on global_name (Nova + Stella)
4. OAuth COALESCE overwrites user-cleared names (Vega unique find)
5. Missing tests for PATCH /users/@me and resolveUser fix (all three)

## Process Notes
- Vega (Gemini 3.1 Pro) failed on first spawn (terminated after 1m27s), succeeded on retry
- Stella and Nova completed on first try
- Vega wrote review to workspace-ruantang instead of workspace (minor path issue)

## Reviewer Performance
- **Stella**: Found the most impactful bug (toUser() propagation gap). Solid overall.
- **Nova**: Most thorough review — detailed C1-C3 criticals, extensive product impact analysis, good suggestions. Excellent.
- **Vega**: Caught the OAuth COALESCE semantic issue others missed. Shorter review but unique insight.

## Round 2 (2026-06-14)

### Reviewers
- 🌟 Stella (GPT-5.5): ❌ Major Issues
- 🌠 Nova (Claude Opus 4.7): ⚠️ Needs Changes
- 💫 Vega (Gemini 3.1 Pro): ✅ Ready

### R1 Resolution
- Most R1 criticals fixed (normalization, validation, toUser, OAuth COALESCE, body passthrough)
- Partial: tests still missing OAuth re-login + resolveMentions coverage

### New Issues Found
1. **CI webhook shell injection** via PR title interpolation in .github/workflows/ci.yml (Stella + Nova)
2. OAuth given_name bypasses validateDisplayName (Stella + Nova)
3. Mention map keyed by non-unique display name (Stella)

### Reviewer Performance
- **Stella**: Found CI injection (critical) + mention key collision + thorough R1 tracking. Escalated to ❌ Major — possibly over-scoped but caught the real blocker.
- **Nova**: Also found CI injection + OAuth validation gap. Most detailed analysis. Appropriate ⚠️ calibration (feature ready, CI blocks).
- **Vega**: Marked ✅ Ready — missed CI injection and OAuth validation gap entirely. Over-optimistic on R2.

### Assessment Note
- Vega's R2 was a significant miss — two reviewers found a shell injection vulnerability that Vega completely overlooked. This matches R1 pattern (Vega needed retry). Gemini 3.1 Pro reliability/thoroughness needs monitoring.

## Round 3 (2026-06-14)

### Reviewers
- 🌟 Stella (GPT-5.5): ❌ Failed (2 attempts — garbled output, no review file)
- 🌠 Nova (Claude Opus 4.7): ❌ Major Issues
- 💫 Vega (Gemini 3.1 Pro): ❌ Major Issues

### R2 Fix Verification
- CI webhook shell injection: ✅ Fixed (env + jq)
- OAuth given_name validation: ✅ Fixed
- OAuth re-login COALESCE: ❌ REGRESSION — re-introduced the R1 bug

### Key Finding
- **COALESCE regression**: R3 added `COALESCE(global_name, ?)` back to existing-user OAuth UPDATE, re-introducing the exact R1 concern (user-cleared names overwritten on re-login). R2 had fixed this by not touching global_name on re-login.
- Both Nova and Vega caught this independently.

### Reviewer Performance
- **Stella**: GPT-5.5 failed twice — first attempt garbled output, second attempt reasoning dump with no review file. Reliability concern for R3.
- **Nova**: Excellent again. Found COALESCE regression, new given_name length issue, detailed R2 status tracking. Most thorough.
- **Vega**: Caught COALESCE regression + mention collision + optimistic msg. Redemption from R2 miss.

### Assessment Notes
- Stella (GPT-5.5) reliability degrading across rounds: R1 OK, R2 OK, R3 failed twice
- Vega (Gemini 3.1 Pro) improving: R1 needed retry, R2 missed CI injection, R3 caught regression
- Nova (Claude Opus 4.7) consistently strongest reviewer across all 3 rounds

## Pending
- Awaiting COALESCE regression fix
- May need Round 4 review
