# Code Review: PR #429 — feat(client): URL-based channel routing

**Reviewer:** 🌠 Nova  
**Date:** 2026-06-24  
**PR:** https://github.com/kagura-agent/cove/pull/429  
**Branch:** feat/428-url-routing  
**Files changed:** 27 (+532 / -283)

---

## Summary

This PR introduces URL-based routing to the Cove client using react-router-dom v6, making the URL the single source of truth for navigation state. It cleanly removes `activeChannelId`, `activeGuildId`, and `activeThread` from zustand stores, introduces a `useActiveIds()` hook and `getActiveIdsFromRouter()` for non-React code, handles deep linking, thread panel via URL params, OAuth path restoration, lazy route loading, and proper READY handler behavior. The implementation closely follows the spec and is well-structured overall. The store cleanup is thorough and the migration to URL-driven state is consistent across all consumers.

---

## Critical Issues

### 1. `useScrollRestoration` hook is defined but never integrated
**File:** `packages/client/src/hooks/useScrollRestoration.ts`  
**Impact:** The hook is brand new but no component uses it. The spec calls for per-channel scroll position memory (Discord-like behavior). Without integration into `MessageList` or `ChannelView`, switching channels will lose scroll position — a user-facing regression vs. the expected behavior described in the spec.

**Verdict:** Not blocking merge (behavior is same as before this PR since no scroll restoration existed), but the dead code should be removed or wired in. Listed here because the spec implies it's part of this feature.

### 2. Race condition in `ChannelView` thread validation
**File:** `packages/client/src/components/ChannelView.tsx` (lines 55-65)  
```
useEffect(() => {
  if (!threadId || !channelId) return;
  const channelThreads = threads[channelId] ?? [];
  const threadExists = channelThreads.some((t) => t.id === threadId);
  if (channelsLoaded && !threadExists) {
    useThreadStore.getState().fetchThread(threadId).then((thread) => {
      if (!thread && guildId && channelId) {
        navigate(routes.channel(guildId, channelId), { replace: true });
      }
    });
  }
}, [threadId, channelId, guildId, channelsLoaded, threads, navigate]);
```
The `threads` dependency means this effect re-runs on every thread store update. If `fetchThread` resolves and adds the thread to a different parent key than `channelId`, the effect will keep firing and keep calling `fetchThread` in a loop. Additionally, if the fetch succeeds but doesn't populate `threads[channelId]` (because the thread belongs to `channelId` but the store keying uses `parent_id`), the next render still sees `!threadExists` and re-fetches.

**Fix:** Add a `fetchedRef` or guard to prevent re-fetching after the first attempt. Or move the validation to only run once when `channelsLoaded` flips to true.

### 3. `CHANNEL_DELETE` handler reads stale channel list
**File:** `packages/client/src/lib/gateway-subscriptions.ts` (CHANNEL_DELETE handler)  
```
useChannelStore.getState().removeChannel(data.id);
// ...
if (data.id === activeChannelId) {
  const guildId = getGuildForChannel(data.id) ?? ...;
  const channels = useChannelStore.getState().getChannels(guildId);
```
`getGuildForChannel(data.id)` is called *after* `removeChannel(data.id)`. The channel was just removed from the store, so `getGuildForChannel` will return `null` since it iterates `channelsByGuildId`. The fallback to `Object.keys(guilds)[0]` saves it, but the intent is fragile — if the user is in a non-first guild, they'd get navigated to the wrong guild's channel.

**Fix:** Call `getGuildForChannel(data.id)` *before* `removeChannel(data.id)`, or pass the `guild_id` from the WS event payload if available.

---

## Product Impact

1. **Deep linking now works** — users can share channel/thread URLs, bookmark them, and open in new tabs. This is a significant UX improvement.
2. **Browser back/forward works** — channel switches are pushes, thread opens are pushes, thread close via X is go(-1). The yo-yo prevention with `history.state.idx === 0` fallback is correct.
3. **OAuth flow preserves path** — `sessionStorage` based, clean implementation.
4. **No visible regression for existing users** — the `/` auto-redirect means existing bookmarks still work.
5. **Mobile sidebar/members panels**: The `membersOpen` and `filesOpen` state is now local to `ChannelView` rather than `App`. This means they reset on channel switch (they're `useState` in a route component). This is probably fine (Discord does this too) but is a behavior change worth noting.
6. **`InviteCodePage` no longer does `window.history.replaceState({}, "", "/")`** before reload — this is correct since the router now owns URL state.

---

## Suggestions

### 1. `getGuildForChannel` linear scan
**File:** `packages/client/src/lib/router.tsx` (lines 43-50)  
Iterates all guilds × all channels. Fine for small servers but could add a reverse index (`channelId → guildId` map) if guild/channel counts grow. Low priority.

### 2. Missing `scrollRef` in `useScrollRestoration` dependencies
**File:** `packages/client/src/hooks/useScrollRestoration.ts`  
Both effects use `scrollRef.current` but only list `[channelId]` in deps. Since `scrollRef` is a stable ref this works in practice, but the lint rule `react-hooks/exhaustive-deps` may warn. Consider adding a comment suppression or including it.

### 3. Lazy imports could fail silently
**File:** `packages/client/src/lib/router.tsx`  
The `lazy` route loaders don't have error boundaries. If a chunk fails to load (network error), the user gets a blank screen. Consider adding an `errorElement` at the root route level.

### 4. `RedirectToDefault` always picks `guildIds[0]`
**File:** `packages/client/src/components/RedirectToDefault.tsx`  
Object key order for `guilds` depends on insertion order. If the user has a "last visited guild" preference in the future, this is the place to add it. Fine for now (single-guild setup).

### 5. Thread deep link: no loading state
**File:** `packages/client/src/components/ThreadPanel.tsx`  
When `thread` is `null` (deep link, fetch in progress), the component returns `null` — the thread panel area is empty. A loading skeleton or spinner would improve perceived performance.

### 6. Consider `useSyncExternalStore` for router state in non-React code
**File:** `packages/client/src/lib/router.tsx`  
`getActiveIdsFromRouter()` reads `router.state.matches` synchronously. This is fine for event handlers but if ever used in a render path outside React Router context, it won't trigger re-renders. Current usage (gateway subscriptions) is correct.

### 7. Test mock for `router.navigate` doesn't verify calls
**File:** `packages/client/src/lib/gateway-subscriptions.test.ts`  
The mock `router: { navigate: vi.fn() }` is set up but no test assertions verify that navigation happens correctly on CHANNEL_DELETE or READY. Consider adding assertions for the redirect logic.

---

## Positive Notes

1. **Excellent spec** — `docs/specs/428-url-routing.md` is thorough, covers edge cases, has explicit decisions on push vs. replace semantics, and includes a test plan. Model spec-driven development.
2. **Clean store cleanup** — All navigation state removed from zustand with zero half-measures. No "bridge" code keeping both systems alive.
3. **`routes.ts` path helpers** — Centralized URL construction prevents scattered template strings. Easy to refactor if URL structure changes.
4. **`getActiveIdsFromRouter()`** — Elegant solution for non-React code (gateway subscriptions) to read current navigation state without hooks.
5. **Lazy route loading** — Code splitting out of the box. Good for future growth.
6. **Thread history semantics** — The yo-yo prevention (close via X = go(-1), deep link fallback = replace) is well thought out and matches Discord behavior.
7. **Test file updated** — Mocks properly updated to reflect new module structure. Not just "make it compile" — the mocks match the new API surface.
8. **Net deletion** — +532 / -283 for a feature this significant shows good refactoring discipline. The old App.tsx monolith is properly decomposed.

---

## Verdict

⚠️ **Needs Changes**

The CHANNEL_DELETE stale-read (#3) can cause wrong-guild navigation in multi-guild setups. The thread fetch loop (#2) is a potential infinite-fetch bug on deep links with edge-case thread store keying. Both are straightforward fixes (reorder one line; add a fetch guard). The scroll hook (#1) is dead code that should be wired in or removed.

None of these are architectural — the overall design is solid and the implementation is high quality.
