# Stella R3 Re-review — kagura-agent/cove#278

**PR:** fix: rewrite MessageList scroll — position restore, no flash, lazy rendering  
**Round:** 3  
**Verdict:** ✅ Approve / no blocking findings

I re-reviewed the latest PR diff with the Round 2 issues in hand and re-ran local checks. The three R2 must-fix items have been addressed. The remaining concerns are follow-up quality/performance items, not merge blockers for this PR.

## Verification performed

- Fetched latest PR metadata and diff with `gh pr view 278` / `gh pr diff 278`.
- Inspected `packages/client/src/components/MessageList.tsx` and `LazyMessageItem.tsx` in the local checkout at `af6b9c4`.
- Ran `pnpm -F @cove/client lint`:
  - ✅ 0 errors
  - ⚠️ 2 warnings, only 1 introduced here: unused `cappedSetAdd` in `MessageList.tsx`
- Ran `pnpm -F @cove/client exec tsc --noEmit`: ✅ passed
- Ran `pnpm -r build`: ✅ passed

## R2 Must-Fix follow-up

### 1. Stale-cache refetch clobbers restored scroll position — ✅ addressed

R2 issue: stale cached channels restored position, then refetch resolved and unconditionally set `pendingScrollToBottomRef.current = true`, forcing the channel to bottom.

Latest code now only schedules the forced bottom scroll when there is no saved memory or the saved state was already at bottom:

```ts
const mem = scrollMemory.get(channelId);
if (!mem || mem.wasAtBottom) {
  pendingScrollToBottomRef.current = true;
}
```

That preserves the expected behavior:

- uncached first load → bottom
- stale refetch while user was at bottom → bottom
- stale refetch while user had a saved scrolled-up position → do not clobber position

No escalation needed; fixed.

### 2. ESLint error: ref mutation during render — ✅ addressed

R2 issue: `channelIdRef.current = channelId` was mutating a ref during render and tripping `react-hooks/refs`.

Latest code moves the mutation into a layout effect:

```ts
const channelIdRef = useRef(channelId);
useLayoutEffect(() => {
  channelIdRef.current = channelId;
}, [channelId]);
```

I verified with `pnpm -F @cove/client lint`: the previous error is gone. No escalation needed; fixed.

### 3. Unbounded module-level state / memory leak — ✅ addressed

R2 issue: `scrollMemory`, `lastFetchTime`, `lastAckedIds`, and `revealedIds` could grow forever.

Latest code adds caps:

- `scrollMemory`, `lastFetchTime`, `lastAckedIds`: cap 100, evict 20 oldest entries
- `revealedIds`: cap 10,000, evict 2,000 oldest IDs

This addresses the unbounded-growth concern. The eviction is FIFO rather than true LRU because re-setting an existing `Map` key does not refresh insertion order, but that is a product-quality tradeoff rather than the original leak. No escalation needed; fixed.

## Fresh review findings

### 🟡 Minor: unused `cappedSetAdd` helper leaves a new lint warning

`MessageList.tsx` defines `SET_CAP`, `SET_EVICT`, and `cappedSetAdd`, but `revealedIds` capping is implemented inside `LazyMessageItem.tsx`, so the helper in `MessageList.tsx` is unused.

Current impact is low:

- `eslint` reports a warning, not an error.
- Current CI does not run the lint script.
- `tsc` and build pass.

Still worth cleaning before or after merge to keep lint output meaningful.

Suggested fix: remove `SET_CAP`, `SET_EVICT`, and `cappedSetAdd` from `MessageList.tsx`, or move the shared capped-set helper into a small utility and actually use it from `LazyMessageItem.tsx`.

## R2 Suggestions status — carried forward / escalated to follow-up concerns

These were non-blocking suggestions in R2 and are mostly unchanged. Per the re-review escalation rule, I am not downgrading them; they remain follow-up concerns, but I do not consider them blockers for this PR.

1. **Date parsing overhead** — unchanged. `new Date(...).getTime()` still runs in the render loop for grouping. Fine for now, but worth precomputing if long channels become expensive.
2. **Fixed placeholder height** — unchanged. `PLACEHOLDER_HEIGHT = 60` can still cause height shifts for tall messages when scrolling into old history. The 2000px root margin mitigates this.
3. **No targeted tests** — unchanged. This scroll rewrite has complex behavior and still deserves regression tests around cached channel switching, stale-cache refetch, and first-load behavior.
4. **Silent fetch failure** — unchanged. Errors are still only `console.error("loadMessages:", err)` with no user-visible retry state.
5. **IntersectionObserver missing `root`** — unchanged. It still observes against the document viewport rather than the scroll container. This may be acceptable in the current layout, but a container `root` would be more precise.
6. **One observer per lazy item** — unchanged. For very large histories, a shared observer would be cheaper.

## Overall assessment

The Round 2 blockers are fixed cleanly. The scroll restoration logic is now much safer for stale cached channels, the React refs lint violation is gone, and the persistent maps/sets are bounded. I would approve this PR, with a small follow-up to remove the unused helper and ideally add regression tests for the scroll scenarios.