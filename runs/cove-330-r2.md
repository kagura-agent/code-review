# PR #330 Review Run Record (Round 2)

**Date:** 2026-06-12
**PR:** kagura-agent/cove#330
**Title:** feat: infinite scroll — load older messages when scrolling to top (closes #299)
**Round:** 2 (re-review after R1 fixes)

## Verdict: ⚠️ Needs Changes (2/3: Stella ⚠️, Nova ⚠️, Vega ✅)

## R1 Issues Resolution
- C1 channel-switch race: ✅ Fixed
- C2 prepend triggers scroll: ✅ Fixed
- C3 React 18 batching: ✅ Fixed
- S4-S7 non-blocking: ✅ Mostly fixed (fetchingOlder still unbounded)

## New Critical Issues (R2)
1. firstMessageIdRef not reset on channel switch (Stella + Nova)
2. Spinner inside scroll container causes double jolt (Nova unique)
3. loadingOlder leaks across channels (Nova + Vega)

## Reviewer Performance

| Reviewer | Verdict | Key Finds | Notes |
|----------|---------|-----------|-------|
| 🌟 Stella | ⚠️ | firstMessageIdRef channel safety, pendingRestore not channel-keyed, fetchingOlder escalation | Most thorough on state management, but pendingRestore race is very narrow |
| 🌠 Nova | ⚠️ | Spinner scroll jolt (unique), loadingOlder leak, scrollContainerRef verification | Excellent UX-level analysis with spinner jolt sequence |
| 💫 Vega | ✅ | loadingOlder .finally() guard, fetchingOlder unbounded | Accurate but less thorough — approved despite real issues |

## Reflection

### Layer 2 — Prompt Evolution
- "Spinner/loading indicator inside scroll container affecting scrollHeight" is a new pattern worth noting. Not common enough to add to prompt yet.
- "Component-level state not guarded in async callbacks after context change" — this is the same channel-switch pattern from R1, just manifesting differently. The existing prompt covers it.

### Layer 3 — Reviewer Assessment
- Vega approved despite real issues (spinner jolt, firstMessageIdRef) — slightly over-lenient on R2
- Nova found the most impactful unique issue (spinner double jolt with clear sequence analysis)
- Stella was most rigorous on state management but escalated fetchingOlder to Critical which is debatable

### Layer 4 — Process Evolution
- R2 workflow smooth. All reviewers correctly verified R1 fixes before looking for new issues.
