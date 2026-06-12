# PR #330 Round 5 Re-review — Stella

## Summary

✅ **Ready**

I re-reviewed the latest diff for `kagura-agent/cove` PR #330 (`feat: infinite scroll — load older messages when scrolling to top`) with special attention to the Round 4 escalated issues. The three escalated items appear to be addressed in the current patch, and I did not find any new blocking issues in the changed code.

## Critical Issues

None found in this round.

### Round 4 escalated issue verification

1. **`pendingPrependRestoreRef` leak on dedupe no-op** — ✅ Addressed
   - The prepend restore effect now reads and immediately clears `pendingPrependRestoreRef.current` before computing the delta.
   - It also guards `delta === 0`, so if `prependMessages()` dedupes everything and no height changes, the stale pending restore does not later apply a scroll jump.
   - Even when the store update is a no-op, the `loadingOlder` state transition back to `false` should still cause a render/effect pass while the user remains on the same channel, allowing the ref to be cleared.

2. **`pendingPrependRestoreRef` not channel-keyed** — ✅ Addressed
   - The `channelId` layout effect now clears `pendingPrependRestoreRef.current = null` when switching channels.
   - This prevents an old channel's pending scroll-height restore from being applied to the new channel's DOM.
   - The stale async result guard (`channelIdRef.current !== id`) is still present before prepending, which further reduces cross-channel risk.

3. **`fetchingOlder` unbounded map writes** — ✅ Addressed
   - Both `true` and `false` writes now go through `cappedMapSet(fetchingOlder, id, ...)`, matching the bounded-map pattern used elsewhere in this component.

## Product Impact

The infinite-scroll UX should now be stable for the reviewed edge cases:

- Loading older messages should preserve the user's viewport instead of jumping.
- Switching channels during or after a history fetch should not apply stale prepend restoration to the wrong channel.
- The module-level `fetchingOlder` cache should no longer grow without bounds.
- The loading indicator and beginning-of-conversation state are channel-synchronized via module-level maps on channel switch.

## Suggestions

Non-blocking items still worth considering later:

1. **Avoid mutating API arrays with `msgs.reverse()` during initial fetch**
   - Current code still does `const reversed = msgs.reverse();`.
   - Safer pattern: `const reversed = [...msgs].reverse();`, matching the older-page fetch path.

2. **Effect #5 still only tracks message growth through `messages.length`**
   - This is likely acceptable for the current feature, but content/order changes with the same length will not re-run the prepend/append detection effect.
   - If future behavior depends on first/last message identity changes without length changes, consider depending on derived IDs instead.

3. **Potential future robustness: dedupe-aware `hasMore`**
   - `hasMoreHistory` is updated from fetched page size before knowing how many messages were actually unique.
   - This is fine if the backend's `before` pagination is exclusive and reliable, but if it can return fully duplicated pages, the client may continue thinking more history exists. Not blocking based on the current contract, just a defensive consideration.

## Positive Notes

- Good use of `useLayoutEffect` for prepend restoration; this is the right timing for scroll-height compensation before paint.
- The channel switch cleanup is simple and directly addresses the cross-channel stale-ref risk.
- `fetchingOlder` now follows the component's existing bounded map discipline.
- The code keeps stale async fetch guards in place, which is important for this reused-component/channel-switch architecture.
