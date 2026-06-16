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

## R2 Results

| Reviewer | Verdict | Key Findings |
|----------|---------|-------------|
| 🌟 Stella | ⚠️ Needs Changes | R1 schema blocker ✅ fixed. Escalated: error swallowing (#6→Major), zero multi-account tests (#7→Major). New: `resolveAccount` ignores `defaultAccount`. |
| 🌠 Nova | ⚠️ Needs Changes | Schema blocker confirmed fixed. Same escalations. New: per-account schema lacks `additionalProperties: false`. |
| 💫 Vega | ❌ Major Issues | Same escalations (over-escalated severity). |

### R2 Resolution
- R1 schema blocker: ✅ Fixed (all 3 confirmed)
- Misleading "missing token" error: 🔴 Escalated to Major (3/3)
- Zero multi-account tests: 🔴 Escalated to Major (3/3)
- `defaultAccount` not applied: 🟡 New (Stella)
- Per-account schema permissive: 🟡 New (Nova)

## R3 Results

| Reviewer | Verdict | Key Findings |
|----------|---------|-------------|
| 🌟 Stella | ⚠️ Needs Changes | Root-level credentials still functional (design question, not bug) |
| 🌠 Nova | ✅ Ready | All blockers fixed. 9 tests added. Error forwarding clean. |
| 💫 Vega | ✅ Ready | All blockers fixed. Duplicate test suites noted. |

### R3 Resolution
- Misleading error: ✅ Fixed (error forwarded via `resolveError`)
- Multi-account tests: ✅ Fixed (9 tests added)
- `defaultAccount`: ✅ Fixed
- Per-account `additionalProperties: false`: ✅ Fixed
- Dead `?? "default"`: ✅ Fixed

## Consolidated Verdict: ✅ Ready (R3)

3-round review. R1 caught critical schema blocker (Stella+Nova, Vega missed). R2 escalated error swallowing and test coverage. R3 all blockers resolved — 2/3 Ready (Stella over-scoped root-level design question). Merged 2026-06-16T01:32Z.

## Ground Truth

- **Human:** daniyuu approved without comments
- **Accuracy:** correct — all R1-R2 blockers were genuine bugs
- **Blind spots:** none (human didn't catch anything we missed)
- **Effective dimensions:** manifest-schema-validation, error-forwarding, dead-code-fallback, multi-account-test-coverage, defaultAccount-resolution
- **Noise:** Stella R3 over-scoped root-level credentials (design question)
- **Vega miss analysis:** R1 approved Ready while schema blocker existed — cross-file/manifest validation blind spot confirmed
- **Nova timeout:** R1 initially timed out, re-spawned successfully (2nd incident after #352 R5)

## Process Notes
- Nova initially timed out and had to be re-spawned (second timeout incident after #352 R5). Worth monitoring.
