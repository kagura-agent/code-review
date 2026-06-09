# Consolidated Review R2 — cove#278: MessageList scroll rewrite

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)
**Round:** 2

## R1 Issue Resolution

| R1 Issue | Status | Agreement |
|----------|--------|-----------|
| #1 Scroll listener not attached on first visit | ✅ Fixed | 3/3 |
| #2 Deep-history restore (LazyMessageItem reset) | ✅ Fixed via `revealedIds` Set | 3/3 |
| #3 `channelSwitchRef` dead code | ✅ Removed, replaced with `restoringRef` | 3/3 |

All three R1 Must-Fix issues are resolved. The `revealedIds` approach (persisting visibility in a module-level Set) is elegant — it ensures previously-rendered messages stay rendered on remount, keeping `distanceFromBottom` stable.

## Verdict: ⚠️ Needs Changes (3/3)

Two new real bugs found + R1 suggestions escalated.

---

## 🔴 Must Fix (New in R2)

### 1. Stale-cache refetch clobbers restored scroll position (Nova + Stella — 2/3 consensus, verified)

For cached channels older than `STALE_MS` (5 min), the flow is:
1. `useLayoutEffect([channelId])` correctly restores the saved scroll position
2. Fetch effect sees `hasCached && isStale` → fetches from API
3. Fetch resolves → unconditionally sets `pendingScrollToBottomRef.current = true`
4. No-deps `useLayoutEffect` scrolls to bottom, overwriting the just-restored position

**Result:** Position restore only works for channels visited within the last 5 minutes. Older channels always jump to bottom on return — defeating the PR's core goal.

**Fix:** Only force scroll-to-bottom on truly uncached first loads. For stale refetches, check if the user's saved position was at-bottom before forcing:
```ts
const mem = scrollMemory.get(channelId);
if (!mem || mem.wasAtBottom) {
  pendingScrollToBottomRef.current = true;
}
```

### 2. ESLint error: ref mutation during render (Stella — verified ✅)

```ts
const channelIdRef = useRef(channelId);
channelIdRef.current = channelId;  // line 119
```

`react-hooks/refs` rule flags this as an error — mutating refs during render can cause stale values in concurrent mode. Confirmed by running `npx eslint` on the file. This will block CI.

**Fix:** Move the ref update into a `useLayoutEffect`:
```ts
useLayoutEffect(() => {
  channelIdRef.current = channelId;
}, [channelId]);
```

Or make the scroll listener close over `channelId` from its own effect instance.

### 3. Unbounded module-level state — memory leak (3/3 consensus, escalated from R1)

Four module-level structures grow without bound for the lifetime of the tab:
- `scrollMemory` (Map)
- `lastFetchTime` (Map)
- `lastAckedIds` (Map)
- `revealedIds` (Set) — **new in R2**, adds every scrolled-past message ID forever

No eviction, no cleanup on channel deletion, no cap.

**Fix:** Add an LRU cap (~100 channels for Maps, ~10K message IDs for Set), or prune on channel-delete events.

---

## 🟡 Suggestions (escalated from R1, non-blocking for personal project)

- **S1 — Date parsing overhead:** `new Date(msg.timestamp).getTime()` runs twice per message pair on every render. Pre-parse or use epoch comparison. (Vega + Stella)
- **S2 — Fixed placeholder height (60px):** Real message heights vary. Fast scroll-up into unrendered history will still show content shifts. 2000px rootMargin mitigates but doesn't eliminate. (Stella + Vega)
- **S3 — No tests:** 7 effects, 6 refs, 3 module Maps — this needs at minimum: first-visit listener attachment, cached A→B→A restore, stale-cache behavior. (Nova + Vega + Stella)
- **S4 — Silent fetch failure:** `console.error` only, no user-visible feedback or retry. (Nova + Vega + Stella)
- **S5 — `IntersectionObserver` missing `root`:** Defaults to document viewport instead of scroll container. If MessageList is in a constrained layout, intersection triggers at wrong times. (Vega)
- **S6 — One observer per `LazyMessageItem`:** 5000 history messages = 4970 observers. A single shared observer with element→callback map would be cheaper. (Nova)

---

## ✅ Positive Notes

- **R1 fixes are well done.** The `revealedIds` approach is elegant — persisting visibility outside component state solves the deep-history restore without complex height caching. (Nova)
- **`restoringRef` pattern is correct.** Scroll events fire during "run scroll steps" before RAF callbacks, so the flag is still `true` when the handler fires from programmatic scrolls. (Nova, verified)
- **Architecture documentation remains excellent.** The block comment clearly explains design decisions. (3/3)
- **`hasMessages` dependency fix** is clean and minimal — exactly the right change for R1 #1. (3/3)
