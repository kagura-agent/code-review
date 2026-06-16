# Code Review — cove PR #369

**Title:** feat(plugin): multi-account support — Discord-style SDK account resolution (#289)
**Date:** 2026-06-16

## R1 Results

| Reviewer | Verdict | Key Findings |
|----------|---------|-------------|
| 🌟 Stella (GPT-5.5) | ⚠️ Needs Changes | Plugin manifest schema missing `accounts` field — runtime validates what schema doesn't declare. Test fixture staleness. |
| 🌠 Nova (Claude Opus 4.7) | ⚠️ Needs Changes | Same schema blocker as Stella. Dead code fallback in account resolution. Traced SDK internals to verify resolution path. |
| 💫 Vega (Gemini 3.1 Pro) | ✅ Ready | Clean review, no blockers found. Did NOT catch the schema/manifest validation gap. |

### Consensus Findings (2/3+)
- **Plugin manifest schema missing `accounts` (Stella + Nova):** The runtime code validates and resolves multi-account configurations, but the plugin manifest JSON schema (used for validation at install/load time) does not declare the `accounts` field. This means invalid configurations could pass schema validation and only fail at runtime — a classic schema-runtime divergence bug. **This was the critical blocker.**

### Unique Findings
- **Stella:** Test fixture staleness — existing test fixtures don't cover multi-account manifest shapes
- **Nova:** Dead code fallback in account resolution path (unreachable branch after SDK changes). Deep trace through SDK account resolution internals to verify correctness.
- **Vega:** No unique findings (no blockers identified)

### Vega Miss Analysis
Vega approved ✅ Ready while a real schema/manifest consistency issue existed. This is the **under-detection** pattern seen previously (#330 R2/R3, #335 R1, #348 R2, #356 R1). Cross-file validation — where the bug lives in the gap between what two files declare rather than in either file alone — remains Vega's weakest dimension.

## Consolidated Verdict: ⚠️ Needs Changes

Schema/manifest consistency is a real blocker: users can write invalid plugin configs that pass schema validation but fail at runtime. Dead code fallback is a secondary concern.

## Process Notes
- Nova initially timed out and had to be re-spawned (second timeout incident after #352 R5). Worth monitoring.
