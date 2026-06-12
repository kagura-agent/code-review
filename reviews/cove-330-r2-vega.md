# Code Review: PR #330 (Round 2)
**Reviewer:** 💫 Vega
**Verdict:** ✅ Ready

## Summary
Great job on the fixes! All critical issues from Round 1 have been effectively addressed. The scrolling behavior is now much more robust, preventing jumps when prepending and avoiding the React 18 batching race condition. The channel-switching guard is correctly in place for the messages fetch. I'm approving this PR, but I've left a couple of minor edge cases below that you might want to patch before merging.

## Critical Issues
None.

## Product Impact
Infinite scrolling now provides a seamless experience. Loading older messages correctly pushes the existing content down without causing jarring jumps or forcing the user to the bottom of the channel.

## Suggestions (Minor / Edge Cases)
1. **Cross-channel spinner race condition (Minor):** 
   In `onScroll`'s fetch logic, the early return `if (channelIdRef.current !== id) return;` successfully prevents stale data. However, the `.finally()` block still runs and executes `setLoadingOlder(false)`. Because `setLoadingOlder` is component state, this will clear the loading spinner on the *new* channel if the user switched while a fetch was pending. 
   **Quick fix:** Add a guard:
   ```typescript
   .finally(() => {
     fetchingOlder.set(id, false);
     if (channelIdRef.current === id) {
       setLoadingOlder(false);
     }
   });
   ```

2. **Missed bounded map for `fetchingOlder` (Nitpick):**
   You correctly applied `cappedMapSet` to `hasMoreHistory`, but `fetchingOlder.set(id, true)` is still using the native Map method. It's a microscopic memory leak as users visit hundreds of channels, but using `cappedMapSet` here too would keep it perfectly bounded.

## Positive Notes
- `useLayoutEffect` was the perfect choice to eliminate the React 18 rAF batching bug.
- The state logic in `prependMessages` properly deduplicates incoming messages, making the client highly resilient to backend pagination overlaps.
- Good job adding the React state for `hasMore` to properly drive the beginning-of-channel indicator.