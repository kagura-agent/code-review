# PR #330 Review Run Record

**Date:** 2026-06-12
**PR:** kagura-agent/cove#330
**Title:** feat: infinite scroll — load older messages when scrolling to top (closes #299)
**Scope:** 3 files (api.ts, useMessageStore.ts, MessageList.tsx), ~78 LOC net
**Round:** 1

## Verdict: ⚠️ Needs Changes (3/3 unanimous)

## Critical Issues Found
1. Channel-switch race condition in fetch callback (Stella + Nova)
2. Prepend triggers bottom auto-scroll via Effect #5 (Stella)
3. React 18 batching breaks scroll-restore timing (Vega)

## Reviewer Performance

| Reviewer | Verdict | Key Finds | Unique Finds |
|----------|---------|-----------|-------------|
| 🌟 Stella | ⚠️ | Channel race, prepend-triggers-scroll, .reverse() mutation | Prepend-triggers-scroll interaction with Effect #5 |
| 🌠 Nova | ⚠️ | Channel race, hasMoreHistory fragility, AbortController suggestion | hasMoreHistory Map driving render fragility, pending-message edge case |
| 💫 Vega | ⚠️ | React 18 timing, unbounded maps, flushSync fix | React 18 batching + flushSync recommendation, cappedMapSet inconsistency |

## Reflection

### Layer 2 — Prompt Evolution
- "Channel switch race condition in async callbacks" has appeared in multiple PRs now (scroll-related). Consider adding explicit check to React rules: "async callbacks in scroll/effect handlers must verify component is still mounted and context hasn't changed".
- React 18 batching + scroll restoration is a newer pattern worth tracking. If it recurs, add to TypeScript/React rules.

### Layer 3 — Reviewer Assessment
- Vega found the most actionable critical (React 18 timing with concrete flushSync fix) — strong on framework-level analysis
- Stella found the prepend-triggers-Effect-#5 interaction — good cross-effect reasoning
- Nova had the most thorough analysis overall with 5 numbered criticals, though #4 (pending-only channel) and #5 (Map driving render) are more edge-case/design than blocking

### Layer 4 — Process Evolution
- Workflow ran smoothly. All 3 reviewers completed successfully.
- Stella took longest (~1m44s) but all within acceptable range.
