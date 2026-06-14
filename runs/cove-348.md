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

## Pending
- Awaiting PR author's response
- May need Round 2 review
