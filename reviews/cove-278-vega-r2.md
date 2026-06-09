# Code Review: PR #278 (Round 2) - by 💫 Vega

## 🔄 Round 1 Follow-up

- ✅ **Scroll listener never attached on first channel visit**: Addressed. `hasMessages` was correctly added to the scroll listener effect dependencies.
- ✅ **Scroll restore breaks for deep history**: Addressed. The new `revealedIds` Set effectively persists visibility state across remounts, ensuring that `distanceFromBottom` calculation remains accurate for previously viewed items.
- ✅ **channelSwitchRef RAF guard is dead code**: Addressed. The new `restoringRef` correctly suppresses programmatic scroll events from overwriting the saved user position.

---

## 🚨 ESCALATED TO CRITICAL (Unaddressed R1 Issues)

As per review policy, issues raised in Round 1 that were not addressed in Round 2 are automatically escalated to **Critical**. These must be fixed before merging:

1. **Unbounded Maps/Sets (Memory Leaks)**: `scrollMemory`, `lastFetchTime`, and `lastAckedIds` are still unbounded Maps. Furthermore, the newly introduced `revealedIds` in `LazyMessageItem.tsx` is an unbounded Set. In a long-running client, these will grow indefinitely. Implement an eviction strategy or use an LRU cache.
2. **Date parsing overhead in render loop**: 
   ```typescript
   new Date(msg.timestamp).getTime() - new Date(prev.timestamp).getTime() > 7 * 60 * 1000
   ```
   This performs expensive Date parsing for every message on *every single render*. Pre-parse these timestamps in the store or memoize the parsed values.
3. **Silent fetch failure**: `api.fetchMessages(channelId).then(...).catch((err) => console.error(...))` still silently swallows network errors. The user receives no visual feedback if the fetch fails.
4. **No tests**: The complex new scroll architecture and lazy rendering logic are still lacking any unit/integration tests.
5. **Fixed placeholder height**: `PLACEHOLDER_HEIGHT = 60` is still hardcoded. While `revealedIds` prevents jank for previously viewed items, scrolling up into unrendered history containing multi-line messages will still cause visual jumping when the 60px placeholder is replaced by the real DOM node.

---

## 🆕 New Issues Found in Round 2

### 🟡 Medium: `useLayoutEffect` runs on every render
In `MessageList.tsx`, Effect #4 (After fresh-fetch render) is missing a dependency array:
```typescript
useLayoutEffect(() => {
  if (!pendingScrollToBottomRef.current) return;
  // ...
});
```
Because it lacks dependencies, this effect runs on *every single render* of the `MessageList`. While the early return mitigates the performance hit, this is a React anti-pattern. You should ideally include dependencies (e.g., `[messages]`) or handle the scroll immediately after the state update if possible.

### 🟡 Medium: `IntersectionObserver` missing `root`
In `LazyMessageItem.tsx`:
```typescript
const observer = new IntersectionObserver(
  ([entry]) => { ... },
  { rootMargin: ROOT_MARGIN },
);
```
Without specifying a `root` in the options, the observer defaults to the document viewport. If `MessageList` is constrained within a smaller flex or grid container, the intersection calculation might trigger at the wrong times. Pass the `.scroll-container` element as the `root` (e.g., via a React Context) for precise lazy loading.

## Summary
The major architectural blockers from Round 1 have been solved, and the distance-from-bottom approach is a robust fix for the scroll flash. However, the unaddressed R1 suggestions have now escalated to Critical. Please resolve the memory leaks, Date parsing overhead, and silent failures to proceed.