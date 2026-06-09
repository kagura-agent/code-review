# Consolidated Review R4 — cove#278: MessageList scroll rewrite

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (unavailable this round)
**Round:** 4

## R3 Issue Resolution

| R3 Issue | Status | Agreement |
|----------|--------|-----------|
| Dead code: unused `cappedSetAdd`/`SET_CAP`/`SET_EVICT` | ✅ Fixed | 2/2 |

The R3 cleanup item is resolved — dead code removed, all helpers are now used.

## New Work in R4

The author also addressed two R3 follow-up suggestions:
- **Shared IntersectionObserver** — replaced per-item observers with a single shared observer ✅
- **Explicit `root` option** — observer now targets the scroll container instead of document viewport ✅
- **Date parsing** — switched to `Date.parse()` (minor improvement)

## Verdict: ⚠️ Needs Changes (1 lint blocker)

One new issue introduced by the shared-observer implementation.

---

## 🔴 Must Fix

### ESLint error: `scrollContainerRef.current` read during render (Stella — verified ✅)

```tsx
<LazyMessageItem
  scrollRoot={scrollContainerRef.current}  // ← line 354
>
```

`react-hooks/refs` rule flags this as an error — reading `.current` during render is unsafe in concurrent mode and can cause stale values. Verified locally:

```
354:23  error  Cannot access refs during render  react-hooks/refs
✖ 1 problem (1 error, 0 warnings)
```

This will block CI. Also, on first render `scrollContainerRef.current` is `null` (ref assigned after commit), so lazy items initially register against the viewport, then all re-register on second render — O(N) observer churn.

**Fix (callback ref pattern):**
```tsx
const [scrollRoot, setScrollRoot] = useState<HTMLDivElement | null>(null);

<div ref={setScrollRoot} style={listStyle} className="scroll-container">
  {messages.map((msg, i) => (
    <LazyMessageItem scrollRoot={scrollRoot} ...>
```

This makes `scrollRoot` a real render dependency, avoids the ref read, and eliminates the first-render null issue (items won't mount until the container state is set).

---

## 💡 Follow-up (non-blocking)

Carried from previous rounds — file issues if not addressed here:
- **P1 — Tests:** Scroll state machine needs regression coverage
- **P2 — Fixed 60px placeholder height:** Varies with real content
- **P3 — Silent fetch failure:** `console.error` only, no user-visible retry
- **P4 — `lastFetchTime` not updated by WebSocket:** Active channels still refetch every 5min

---

## ✅ Positive Notes

- **Shared observer is a great improvement** — addresses the per-item observer scaling concern from R3. Architecture is correct, just needs the ref-read fix.
- **All R1/R2/R3 blockers remain resolved** across 4 rounds of review.
- **TypeScript and build pass** (`tsc --noEmit` ✅, `pnpm -r build` ✅).
- **Code quality has improved significantly** through 4 rounds — from 3 critical bugs to 1 lint fix away from merge.
