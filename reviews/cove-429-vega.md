# PR #429 Review — 💫 Vega (Round 3)

**PR:** kagura-agent/cove#429 — feat(client): URL-based channel routing (#428)
**Branch:** feat/428-url-routing
**Reviewed commits:** 521858c, 001433b (fixes since Round 2)

## Summary

Commit 001433b correctly fixes the React #185 infinite update loop in `ChannelView` and `RedirectToDefault` by replacing zustand selector subscriptions with `getState()` reads inside effects and stabilizing `navigate` via `navigateRef`. This is the right pattern. However, `ThreadPanel` was not updated with the same fix — it still subscribes to the entire `threads` store object as a useEffect dependency, creating the same class of unnecessary re-execution and redundant API calls on deep-linked threads. This was my Round 2 concern and remains unaddressed. The `useScrollRestoration` dead code from Round 2 is also still present.

## Previous Issues Status

### Round 2 Unresolved #1: useScrollRestoration dead code
**Status: ⚠️ Still unaddressed — escalated**

`useScrollRestoration.ts` is defined but never imported by any component. `MessageList.tsx` has its own independent scroll architecture (`scrollMemory` Map with distance-from-bottom tracking, lines 89+). The spec explicitly lists scroll restoration as a required behavior and provides this hook as the solution, but the existing `MessageList` implementation already handles it. The hook is dead code that should be removed (with a note that `MessageList` covers the behavior), or integrated if `MessageList`'s solution is intended to be replaced.

### Round 2 Unresolved #2: ThreadPanel subscribes to entire `threads` store
**Status: ⚠️ Still unaddressed — escalated to Needs Changes**

`ThreadPanel.tsx` line 19: `const threads = useThreadStore((s) => s.threads);` subscribes to the entire threads-by-channel object. This is used in the useEffect at line 30 with deps `[threadId, threads]`.

Commit 001433b fixed this exact anti-pattern in `ChannelView` — replacing zustand selectors with `getState()` reads inside effects, adding `navigateRef`, and using `threadFetchRef` to guard fetches. **ThreadPanel was not given the same treatment.**

Concrete problem on deep-linked threads:
1. `ThreadPanel` mounts → thread not in store → `fetchThread(threadId)` fires → returns thread → `setThread(t)` (local state only)
2. `fetchThread` does NOT call `addThread()`, so the thread is never persisted to the store
3. Any subsequent `threads` store change (e.g., `THREAD_CREATE` event for another channel) → new `threads` reference → effect re-runs → thread still not in store → `fetchThread` fires again

Unlike ChannelView, ThreadPanel has **no `threadFetchRef` guard**. This means redundant API calls on every unrelated thread store mutation for deep-linked threads.

**Fix:** Apply the same 001433b pattern — read `threads` via `getState()` inside the effect, add a fetch guard ref, reduce deps to `[threadId]`.

### Previously Fixed (confirmed ✅)
- CHANNEL_DELETE race condition — `getGuildForChannel` called before `removeChannel` ✅
- ChannelView thread fetch loop — `threadFetchRef` guard + `getState()` reads ✅
- Unhandled `fetchThread` rejection — `.catch()` added ✅

## Critical Issues

None blocking.

## Product Impact

1. **Deep-linked threads may trigger redundant fetches** — If a user opens a thread via deep link and the thread store updates from other channels' activity, ThreadPanel will re-fetch the same thread from the API. User sees no visual issue, but it generates unnecessary network traffic. Low frequency in practice (thread store changes are infrequent), but it's the same bug class that 001433b fixed in ChannelView.

## Issues Requiring Changes

### 1. ThreadPanel: Apply 001433b pattern (Medium — escalated from Round 2)
**File:** `packages/client/src/components/ThreadPanel.tsx`, lines 19, 30-42

ThreadPanel uses the pre-001433b pattern that caused the infinite update loop in ChannelView. While it's not an infinite loop here (the fetch doesn't mutate the store), it's unnecessary re-execution and redundant API calls.

```typescript
// Current (problematic):
const threads = useThreadStore((s) => s.threads);  // subscribes to ALL channels' threads
useEffect(() => { /* search + fetch */ }, [threadId, threads]);  // fires on any thread change

// Should be (matching ChannelView pattern):
const fetchRef = useRef<string | null>(null);
useEffect(() => {
  // read from getState() inside effect
  const threads = useThreadStore.getState().threads;
  // ... search logic ...
  if (fetchRef.current === threadId) return;
  fetchRef.current = threadId;
  // ... fetch logic ...
}, [threadId]);
```

### 2. useScrollRestoration: Remove dead code or integrate (Low — escalated from Round 2)
**File:** `packages/client/src/hooks/useScrollRestoration.ts`

Defined but never imported. `MessageList` already handles scroll restoration independently. Either delete the file (clean dead code) or file a follow-up issue to integrate it. Shipping unused code from a spec requirement creates confusion about whether the spec item was delivered.

## Suggestions (non-blocking)

1. **Double fetch on deep-linked threads** — Both `ChannelView` (line 60-71) and `ThreadPanel` (line 38) call `fetchThread(threadId)` independently. Consider having ChannelView's fetch call `addThread()` to persist the result, which would let ThreadPanel find it in the store on its next check.

2. **`fetchThread` doesn't persist to store** — `useThreadStore.fetchThread()` returns the channel but doesn't call `addThread()`. If it did, the thread would be in the store for subsequent lookups, eliminating the repeated-fetch issue entirely.

3. **`window.history.state?.idx`** — Used in `closeThread` (ChannelView line 76). This is a React Router internal implementation detail, not part of the public API. Could break on RR upgrades. Consider tracking entry state via a ref set on mount instead.

4. **Add `errorElement` to lazy routes** — `router.tsx` uses `lazy()` for all routes but has no `errorElement`. A chunk-load failure (common after deployments) would show a blank screen. Add an error boundary that prompts reload.

5. **No 404/catch-all route** — Unrecognized URLs under `/` render `AppShell` with no child match. Consider adding a catch-all that redirects to `/`.

6. **OAuth return path** — `cove_return_path` from sessionStorage is used without validation (`App.tsx` line 150). Since sessionStorage is same-origin only, this is low-risk, but a simple `returnPath.startsWith('/')` check would prevent any edge cases.

7. **`RedirectToDefault` guild ordering** — `Object.keys(guilds)[0]` relies on JS insertion order. Works for single-guild setups but should be explicit if multi-guild is planned.

## Positive Notes

- **001433b is a high-quality fix.** The `navigateRef` + `getState()` + reduced deps pattern is exactly right for breaking React render cycles. Clean surgical fix.
- **Architectural split is excellent.** `AppShell` / `ChannelView` / `RedirectToDefault` separation is clean and matches the spec's route definitions. Each component has a clear responsibility.
- **Store cleanup is thorough.** Removing `activeChannelId`, `activeGuildId`, and `activeThread` from stores in favor of URL params is the correct architectural decision. No half-measures.
- **`getActiveIdsFromRouter` for non-React code** is well-designed — uses `router.state.matches` (type-safe) rather than regex parsing.
- **CHANNEL_DELETE race fix** is solid — resolving guild before removing channel from store.
- **Route path helpers** (`routes.ts`) prevent URL template string duplication.
- **Test mocks updated** to match new store/router shape — tests aren't left broken.

## Verdict

**⚠️ Needs Changes**

ThreadPanel still uses the pre-fix subscription pattern that 001433b corrected in ChannelView. Same anti-pattern, same fix needed. The `useScrollRestoration` dead code is a minor cleanliness issue that should also be resolved. Neither is a merge-blocking bug in isolation, but the ThreadPanel issue is a real latent bug (redundant API calls) in the same code that was just explicitly fixed elsewhere, and it was flagged in Round 2 without being addressed.
