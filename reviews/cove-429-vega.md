# Re-Review: PR #429 — URL-based Channel Routing (Round 4)

**Reviewer:** 💫 Vega  
**Focus:** Verify commit 3cfd965 fixes ThreadPanel fetch loop  
**Date:** 2026-06-25

---

## Verdict: ✅ Ready

The blocking issue from Round 3 is **properly fixed**. The ThreadPanel no longer subscribes reactively to the thread store, eliminating the fetch loop.

---

## Primary Assessment: ThreadPanel Fetch Loop Fix

### Checklist

| Requirement | Status | Evidence |
|---|---|---|
| Remove reactive `threads` subscription | ✅ | No `useThreadStore((s) => s.activeThread)` or any reactive selector on threads. Component receives `threadId` as prop. |
| Use `getState()` for imperative reads | ✅ | `useThreadStore.getState().threads` — no subscription, no re-render trigger |
| `threadFetchRef` guard | ✅ | `const threadFetchRef = useRef<string | null>(null)` + `if (threadFetchRef.current === threadId) return;` before fetch |
| Call `addThread()` to persist | ✅ | `useThreadStore.getState().addThread(t)` after successful fetch |
| `.catch()` error handling | ✅ | `.catch(() => setThread(null))` — graceful degradation |

### Why this fixes the loop

**Before (broken):**
- ThreadPanel subscribed to `s.activeThread` which internally depended on the entire thread store
- Any mutation to `threads` (from ANY channel) triggered re-render → useEffect re-fires → `fetchAndOpenThread()` → API call → store mutation → re-render → ∞

**After (fixed):**
- `threadId` comes from URL params (prop), not from store subscription
- Store reads are imperative (`getState()`) — no reactive dependency
- `threadFetchRef` prevents duplicate fetches for the same threadId
- `addThread()` persists the result, so the store lookup succeeds on subsequent renders without fetching again

### Consistency with ChannelView pattern

ChannelView uses the same pattern for its thread validation:
- `threadFetchRef` ref guard
- `useThreadStore.getState().threads[channelId]` imperative read
- `fetchThread(threadId)` with navigation on failure

Both components are now consistent. ✅

---

## New Issues Found (Non-blocking)

### 1. Minor: Stale fetch race on rapid threadId change (Low)

```typescript
// ThreadPanel.tsx
useEffect(() => {
  // ...
  useThreadStore.getState().fetchThread(threadId).then((t) => {
    if (t) {
      useThreadStore.getState().addThread(t);
      setThread(t);  // ← no staleness check
    }
  }).catch(() => setThread(null));
}, [threadId]);
```

If `threadId` changes while a fetch is in flight (A → B), thread A's fetch resolves and calls `setThread(threadA)` AFTER thread B has been set synchronously. This would briefly flash stale data.

**Mitigation:** In practice, thread switching is URL-driven and causes component remount (different route params), making this extremely unlikely. A cleanup flag (`let cancelled = false`) would be defensive but optional.

### 2. Duplicate fetch on deep-link (Low, carried from Round 3)

On deep-link, both ChannelView and ThreadPanel independently call `fetchThread(threadId)`:
- ChannelView: validates existence (navigates away on 404)
- ThreadPanel: fetches data for rendering

Result: 2 API calls for the same resource. Not harmful but wasteful. The Round 3 suggestion to consolidate still applies as a future improvement.

---

## Round 3 Suggestions Status

| # | Suggestion | Status |
|---|---|---|
| 1 | Remove dead `useScrollRestoration.ts` | ⚠️ File exists, appears unused (no imports found in diff) |
| 2 | Add `errorElement` to lazy routes | Not addressed |
| 3 | `window.history.state?.idx` is RR internal | Still used in `closeThread` |
| 4 | Validate OAuth `cove_return_path` | Not addressed |
| 5 | Add 404/catch-all route | Not addressed |
| 6 | Consolidate duplicate `fetchThread` | Not addressed (see §2 above) |
| 7 | `useBotStore` router coupling | ✅ Fixed — uses `getActiveIdsFromRouter()` |

None of these are blocking. They can be addressed in follow-up PRs.

---

## Summary

The fix in commit 3cfd965 correctly eliminates the fetch loop by:
1. Converting ThreadPanel from store-driven to prop-driven (`threadId` from URL)
2. Using imperative `getState()` reads instead of reactive subscriptions
3. Adding `threadFetchRef` guard to prevent duplicate fetches
4. Persisting fetched threads with `addThread()`
5. Proper error handling with `.catch()`

QA confirms no extra API calls after 5 seconds. The architectural change is sound and consistent with the rest of the routing migration.

**No blocking issues remain. Approve.**
