# 🌟 Stella — PR #429 Review (Round 3)

**PR:** kagura-agent/cove#429 — `feat(client): URL-based channel routing (#428)`
**Branch:** `feat/428-url-routing`
**Reviewed commits:** 521858c (CHANNEL_DELETE race, thread fetch loop, unhandled rejection) + 001433b (React #185 infinite update loop fix)

## Summary

The core URL routing migration is solid and the Round 2 consensus fixes are confirmed (CHANNEL_DELETE race, ChannelView fetch loop guard, unhandled rejection). Commit 001433b correctly addresses the React 19 infinite update loop by stabilizing `navigate` references via refs. However, both Round 2 unresolved issues remain unaddressed: `useScrollRestoration` is still dead code, and ThreadPanel still subscribes to the entire `threads` store without a fetch guard — creating a fetch loop risk on deep-linked threads. Per escalation rules, these cannot be downgraded.

## Previous Issues Status

### Confirmed Fixed (from Round 2 consensus)

1. **CHANNEL_DELETE race — ✅ Fixed.** `getGuildForChannel()` called before `removeChannel()` in `gateway-subscriptions.ts:198-199`. Fallback to first guild via `Object.keys()` also present. Correct.

2. **ChannelView thread fetch loop — ✅ Fixed.** `threadFetchRef` guard in `ChannelView.tsx:56-72` prevents re-fetching the same threadId. Targeted `useThreadStore.getState().threads[channelId]` read (not a subscription) avoids reactive re-triggering.

3. **Unhandled fetchThread rejection — ✅ Fixed.** `.catch()` added in `ChannelView.tsx:69-72`, navigates back to parent channel on network failure.

### Round 2 Unresolved — Still Unaddressed

4. **useScrollRestoration dead code — ❌ STILL UNRESOLVED (escalated).** `useScrollRestoration.ts` defines a hook that is **never imported by any component** in the codebase. `MessageList.tsx` implements its own scroll memory via a module-level `scrollMemory` Map (lines 27-49, 90, 289-346), so the behavior IS working — but the hook is orphaned dead code. Either integrate it (replacing MessageList's ad-hoc implementation) or remove it. This was flagged in Round 2 by Nova; unaddressed → escalated.

5. **ThreadPanel subscribes to entire `threads` store, no fetch guard — ❌ STILL UNRESOLVED (escalated to Critical).** `ThreadPanel.tsx:18` uses `useThreadStore((s) => s.threads)` — subscribes to ALL threads across ALL channels. The `useEffect` at line 29 depends on `[threadId, threads]`. On deep-linked threads:
   - Thread is not in the store → `fetchThread()` is called
   - `fetchThread()` returns the thread but does NOT call `addThread()` to persist it
   - Any subsequent thread store mutation (THREAD_CREATE/UPDATE in another channel) changes the `threads` reference → effect re-runs → thread still not in store → `fetchThread()` called again
   - **No fetch guard ref** (unlike ChannelView which has `threadFetchRef`)
   - Result: repeated API calls on every thread store mutation while a deep-linked thread is open

   **Compare with ChannelView** (correctly guarded):
   - Uses `useThreadStore.getState().threads[channelId]` (point read, not subscription)
   - Has `threadFetchRef` to prevent duplicate fetches

   This was flagged by Vega in Round 2 as ⚠️ Minor; unaddressed → escalated to Critical.

## Critical Issues

### C1. ThreadPanel fetch loop on deep-linked threads (escalated)

**File:** `ThreadPanel.tsx:18, 29-41`

ThreadPanel subscribes to `s.threads` (entire store) and re-runs its find-or-fetch effect on every thread mutation anywhere. Combined with `fetchThread` not persisting results via `addThread()`, this creates a fetch loop for deep-linked threads. Fix requires either:
- (a) Add a `threadFetchRef` guard (matching ChannelView's pattern), OR
- (b) Have `fetchThread` call `addThread()` to persist the result, AND use a targeted selector like `s.threads[channelId]` instead of `s.threads`

### C2. Double-fetch of thread data on deep link

**Files:** `ChannelView.tsx:63` + `ThreadPanel.tsx:38`

Both components independently call `useThreadStore.getState().fetchThread(threadId)` on deep-link, and neither persists the result to the store. Two concurrent API calls for the same resource. ChannelView should be the single owner of fetch + validation, passing fetched data down or storing it.

## Product Impact

- **Scroll restoration**: Working correctly via `MessageList`'s own `scrollMemory` implementation. No user-facing impact from the dead `useScrollRestoration` hook — but the orphaned code is misleading (suggests scroll restoration was intended but not connected).
- **Deep-linked threads**: If a user shares a thread URL and the recipient opens it during active thread usage in the server, they may see increased network traffic from repeated fetches. Not a UX-breaking issue but degrades performance.

## Suggestions (non-blocking)

1. **Remove or integrate `useScrollRestoration`** (`useScrollRestoration.ts`): Dead code. MessageList handles scroll restoration natively. Remove the hook and add a brief comment in MessageList noting the spec requirement is covered there.

2. **Add `errorElement` to lazy routes** (`router.tsx`): If a lazy chunk fails to load (network blip, deploy), React Router shows a blank page. An `errorElement` on the root route provides graceful recovery (e.g., "Failed to load, click to retry").

3. **`window.history.state?.idx`** (`ChannelView.tsx:80`): This is a React Router internal. Consider `window.history.length === 1` or a `useRef` tracking whether the component was the initial entry point.

4. **OAuth return path validation** (`App.tsx:160-163`): `returnPath` from `sessionStorage` is navigated to without validation. A malicious or malformed path could cause unexpected routing. Validate it starts with `/channels/` or is exactly `/`.

5. **Missing 404/catch-all route** (`router.tsx`): Any URL not matching `/` or `/channels/:g/:c` renders nothing. Add a catch-all `*` route that redirects to `/`.

6. **`RedirectToDefault` relies on `Object.keys()` ordering** (`RedirectToDefault.tsx:18`): Picks `guildIds[0]`. In practice V8 preserves insertion order for string keys, but explicit ordering (e.g., sorted or first-received from READY) would be more intentional.

## Positive Notes

- **Clean separation**: AppShell → ChannelView → ThreadPanel hierarchy is well-decomposed. Outlet context pattern is clean.
- **Lazy loading**: Routes use `lazy()` for code splitting — good for initial load performance.
- **navigateRef pattern** (commit 001433b): Correct fix for React 19's unstable `useNavigate` references. Applied consistently in ChannelView and RedirectToDefault.
- **CHANNEL_DELETE handler**: Race condition fix is thorough — resolves guild before removal, falls back gracefully, navigates to next channel or root.
- **Store cleanup**: Navigation state properly removed from zustand stores. URL is now the single source of truth for active selection. Spec compliance is strong.
- **Gateway subscription tests**: Mock updates for router dependencies are thorough and correctly structured.
- **Route helpers** (`routes.ts`): Clean, typed path builders eliminate scattered template strings.

## Verdict

**⚠️ Needs Changes**

Two Round 2 unresolved issues remain unaddressed — the ThreadPanel fetch loop (C1) is a real bug on deep-linked threads during concurrent activity, and the double-fetch (C2) wastes network resources. Both have straightforward fixes (add fetch guard ref + persist to store, or consolidate fetch ownership in ChannelView). The dead `useScrollRestoration` hook is not blocking but should be cleaned up.
