# Consolidated Review R3 — cove#278: MessageList scroll rewrite

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)
**Round:** 3

## R2 Issue Resolution

| R2 Issue | Status | Agreement |
|----------|--------|-----------|
| #1 Stale-cache refetch clobbers scroll position | ✅ Fixed | 3/3 |
| #2 ESLint ref mutation during render | ✅ Fixed | 3/3 |
| #3 Unbounded module-level state (memory leak) | ✅ Fixed | 3/3 |

All three R2 Must-Fix issues are properly resolved:
- Stale refetch now respects saved scroll position (`!mem || mem.wasAtBottom` gate)
- Ref mutation moved into `useLayoutEffect`; lint passes clean (0 errors)
- All Maps capped at 100 entries, `revealedIds` Set capped at 10K with FIFO eviction

## Verdict: ✅ Ready to Merge (2/3 Approve, 1/3 Needs Changes)

Stella and Nova approve. Vega escalated R2 suggestions per the escalation rule, but those are quality improvements rather than functional blockers for a personal project. The core scroll architecture is solid and all real bugs from R1 and R2 are fixed.

---

## 🟡 Fix Before or After Merge

### Dead code: unused `cappedSetAdd` in MessageList.tsx (Stella + Vega — verified ✅)

`SET_CAP`, `SET_EVICT`, and `cappedSetAdd` are defined in `MessageList.tsx` but never used — `LazyMessageItem.tsx` has its own eviction logic. Currently a lint warning (not error), but should be cleaned up.

---

## 💡 Follow-up Recommendations (file issues if not addressed in this PR)

- **P1 — Tests:** This scroll state machine (7 effects, 5+ refs, 3 module Maps) needs regression tests for: cached A→B→A restore, stale-cache refetch preserving position, first-visit listener attachment. (3/3 consensus)
- **P2 — IntersectionObserver `root`:** Currently observes against document viewport, not scroll container. Works in current layout but fragile. (Nova + Vega)
- **P3 — One observer per item:** 1K messages = 1K observers. Single shared observer with element→callback map would be cheaper. (Nova + Vega)
- **P4 — Date parsing overhead:** `new Date().getTime()` twice per message pair on every render. Pre-compute or use epoch comparison. (Vega + Stella)
- **P5 — Fixed placeholder height (60px):** Real message heights vary. Fast scroll into unrendered history may show content shifts. (Nova + Stella + Vega)
- **P6 — Silent fetch failure:** `console.error` only, no user-visible retry. (Nova + Stella + Vega)

---

## ✅ What's Done Well

- **All R1 and R2 blockers systematically resolved across 3 rounds.** The author engaged seriously with each finding.
- **`revealedIds` persistence** is elegant — module-level Set ensures previously-rendered messages stay rendered on remount.
- **`restoringRef` timing is correct** — scroll events fire during "run scroll steps" before RAF callbacks, so programmatic scrolls are properly suppressed.
- **Architecture documentation remains excellent.** The block comment clearly explains the design invariants.
- **LRU eviction** is clean and pragmatic — FIFO via Map insertion order is spec-correct in JS.
- **Build, typecheck, and lint all pass** (Stella verified: `tsc --noEmit` ✅, `pnpm -r build` ✅, lint 0 errors).
