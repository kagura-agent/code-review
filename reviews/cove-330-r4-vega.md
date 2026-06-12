# Code Review: PR #330 (Round 4)
**Reviewer:** 💫 Vega

## Summary
The critical issue from Round 3 (`loadingOlder` stuck spinner on channel switch) has been successfully fixed by syncing the component's `loadingOlder` state from the module-level `fetchingOlder` map when `channelId` changes. 

However, per our review policy, several issues raised as suggestions in Round 3 were left entirely unaddressed. These must now be escalated to blocking issues. 

## ❌ Major Issues (Escalated from R3)

**1. `pendingPrependRestoreRef` leak on dedupe no-op**
If `prependMessages` deduplicates all newly fetched messages (e.g., due to an overlapping API response or race condition), it returns the existing state `s`. React bails out of re-rendering, so effect `4b` never fires to consume `pendingPrependRestoreRef.current`. The ref leaks and will arbitrarily corrupt the scroll position on the *next* unrelated re-render (like a new message arriving). 
*Fix:* You need a mechanism to clear this ref if no prepend occurs, or rely on the `wasPrepend` logic instead of a dangling layout effect.

**2. `pendingPrependRestoreRef` is not channel-keyed or reset**
Related to the above leak: if the ref leaks and the user switches channels, the new channel's first render could consume the stale `scrollHeight` offset. 
*Fix:* At minimum, explicitly set `pendingPrependRestoreRef.current = null` inside the `useLayoutEffect` that watches `channelId` changes.

**3. `fetchingOlder` cache map is unbounded**
The `fetchingOlder` module-level variable is a `new Map<string, boolean>()` and is directly mutated with `.set(id, ...)`. Over a long session jumping between many channels, this grows indefinitely.
*Fix:* Use the `cappedMapSet` helper to enforce the `MAP_CAP` limit, just as you do for `hasMoreHistory` and `lastFetchTime`.

## 💡 Suggestions

**1. Initial fetch `msgs.reverse()` mutation**
In the initial mount fetch, you do `const reversed = msgs.reverse();`. While harmless right now because `msgs` is a fresh array from the `api` response, it's safer to avoid mutating responses directly. Your `onScroll` fetch correctly does `[...fetched].reverse()`. Standardize on the non-mutating spread version.

## 📈 Product Impact
The channel switching experience is now much cleaner without the phantom loading spinners hanging around. Once we patch the scroll-ref leak and cache bounding, this PR will be rock solid and ready to merge.

## Rating
❌ **Major Issues** (Please address the escalated items to unblock)