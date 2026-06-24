# Run Record: cove-429-r3

**PR:** kagura-agent/cove#429
**Title:** feat(client): URL-based channel routing (#428)
**Date:** 2026-06-25
**Round:** 3
**Verdict:** ⚠️ Needs Changes (3/3)

## Context

Re-review after fix commits:
- `521858c` — CHANNEL_DELETE race, thread fetch loop (ChannelView), unhandled rejection
- `001433b` — React #185 infinite update loop (navigateRef pattern)

QA: 8/8 pass including rapid channel switching.

## Fix Verification (3/3 confirm all fixes work)

1. ✅ CHANNEL_DELETE race — reordered correctly
2. ✅ ChannelView thread fetch loop — threadFetchRef + targeted selector
3. ✅ Unhandled fetchThread rejection — .catch() added
4. ✅ React #185 infinite update loop — navigateRef + getState() in effects

## Remaining Issue (3/3 consensus)

**ThreadPanel fetch loop on deep-linked threads** — Same class of bug fixed in ChannelView by 001433b, but not applied to ThreadPanel:
- Subscribes to entire `s.threads` store (all channels)
- No `threadFetchRef` guard
- `fetchThread()` doesn't persist via `addThread()`

Fix: Apply 001433b pattern (getState() reads + fetch guard ref + reduced deps).

## Reviewer Performance

| Reviewer | Verdict | Key |
|----------|---------|-----|
| 🌟 Stella | ⚠️ Needs Changes | ThreadPanel C1 + double-fetch C2, escalated both from R2 |
| 🌠 Nova | ⚠️ Needs Minor Changes | Reclassified useScrollRestoration from Critical→Suggestion (correct self-correction) |
| 💫 Vega | ⚠️ Needs Changes | Consistent with R2 — same ThreadPanel concern, correctly escalated |

## Observations

- **Nova's self-correction**: Downgraded useScrollRestoration from Critical (R2) to Suggestion (R3) with reasoning: "dead code doesn't cause bugs/security/data loss, per verdict calibration." Good calibration improvement.
- **Stella escalated** ThreadPanel to Critical (R3 from R2 Suggestion). Correct application of escalation rule.
- **Vega remained consistent** — same concern, same analysis, correctly escalated per rules.
- All 3 praised 001433b as "high-quality surgical fix"
- Finding verification: 100% across all 3 reviews (7/7, 14/14, 8/8)

## Prompt Evolution Check

Reading last 5 runs for patterns...
- "ThreadPanel broad store subscription" appeared in R1, R2, R3 (3 rounds same PR). Not a cross-PR pattern yet.
- "useScrollRestoration dead code" — Nova's R2 Critical was arguably miscalibrated per review standard ("Needs Changes means real problems if merged — bugs, security, data loss"). Nova self-corrected in R3. No prompt update needed — the calibration guidance is already there.
- No new prompt blind spots identified this round.

## Process Notes

- FlowForge ran smoothly
- Completion events from subagents didn't push to parent session (sessions_yield gap) — Luna had to ask for status. Known limitation, not actionable from review side.
