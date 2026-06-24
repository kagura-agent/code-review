# Code Review: PR #429 — feat(client): URL-based channel routing (#428)

**Reviewer:** 💫 Vega  
**Date:** 2026-06-24  
**PR:** https://github.com/kagura-agent/cove/pull/429  
**Branch:** feat/428-url-routing  
**Files Changed:** 27 (+531 / -252)

---

## Summary

Solid architectural migration from zustand-based navigation state to react-router-dom v6. The PR cleanly removes `activeChannelId`, `activeGuildId`, and `activeThread` from stores, replaces them with URL-derived state via `useActiveIds()` hook and `getActiveIdsFromRouter()` for non-React code. Lazy loading, OAuth path preservation, thread deep-link fetching, and CHANNEL_DELETE redirect logic are all handled. The spec is thorough and the implementation follows it closely. A few race conditions and edge cases need attention before merge.

---

## Critical Issues

### 1. Race condition in CHANNEL_DELETE: `getGuildForChannel` called after removal

**File:** `packages/client/src/lib/gateway-subscriptions.ts` (CHANNEL_DELETE handler, ~line 198-211)

```
useChannelStore.getState().removeChannel(data.id);
// ...
if (data.id === activeChannelId) {
  const guildId = getGuildForChannel(data.id) ?? Object.keys(...)[0];
```

`removeChannel` deletes the channel from `channelsByGuildId` first, then `getGuildForChannel(data.id)` iterates the store looking for it — it's already gone. The fallback to `Object.keys(guilds)[0]` saves most cases, but if there are multiple guilds, the user could be redirected to the wrong guild's first channel. **Fix:** call `getGuildForChannel(data.id)` *before* `removeChannel`.

### 2. ThreadPanel fetch loop risk with `threads` subscription

**File:** `packages/client/src/components/ThreadPanel.tsx` (lines ~27-39)

The `useEffect` that finds/fetches the thread has `threads` (the entire store object) as a dependency. Every time *any* thread in *any* channel updates, this effect re-runs. When it doesn't find the thread in-store (e.g. it's in a different parent), it calls `fetchThread` — potentially triggering repeated API calls on each thread store update. The `setThread` call inside the effect also doesn't prevent re-renders because `threads` changing causes re-evaluation regardless.

**Fix:** Either memoize the lookup outside the effect with a `useMemo`, or derive a more stable dependency (e.g. subscribe to only `threads[parentChannelId]` if known, or add a guard `if (thread?.id === threadId) return`).

### 3. ChannelView thread validation triggers fetch on every thread store change

**File:** `packages/client/src/components/ChannelView.tsx` (lines ~55-66)

Similar to above: the effect depends on `threads` (whole store map). When `channelsLoaded` is true and the thread isn't found *yet* (e.g. it's being fetched), the effect calls `fetchThread` every time any other thread updates. The `.then` callback also navigates away if fetch returns null, but doesn't account for the fetch being in-flight from a prior render.

**Fix:** Add a `fetchingRef` guard or track fetch state to prevent concurrent/repeated fetches.

---

## Product Impact

1. **Deep linking now works** — sharing `/channels/guildId/channelId/threads/threadId` links will load the correct view, even if the user arrives unauthenticated (OAuth flow preserves and restores path).

2. **Browser back/forward navigation** — thread open = push, thread close via X = go(-1) with deep-link fallback. This matches Discord behavior.

3. **Breaking change for existing bookmarks of `/`** — All prior bookmarks point to `/` which now redirects to default channel. Not actually breaking, but worth noting in release notes.

4. **Mobile sidebar behavior** — The `membersOpen`/`filesOpen` state moved from App to ChannelView. The mobile backdrop overlays for members/files panels are not present in the new AppShell. Only the sidebar backdrop remains. If mobile users relied on the overlay-to-dismiss pattern for members/files panels, that UX may be regressed.

---

## Suggestions

### 1. `useScrollRestoration` missing `scrollRef` in dependency array

**File:** `packages/client/src/hooks/useScrollRestoration.ts` (lines 11, 19)

Both effects depend on `scrollRef.current` but only list `[channelId]` as deps. If the ref changes (unlikely but possible with conditional rendering), the saved position would reference a stale element. Adding `scrollRef` to deps is defensive best practice (though React refs are stable, the linter will flag this).

### 2. RedirectToDefault re-renders on any guild/channel store change

**File:** `packages/client/src/components/RedirectToDefault.tsx`

Subscribing to `guilds` (object) and `channelsByGuildId` (object) means this component re-renders on every store update. Since it only runs once (on `/`) and navigates away immediately, the impact is minimal — but it could cause a flash if the store churns during READY. Consider using a ref-based "already redirected" guard.

### 3. OAuth return path should validate before navigating

**File:** `packages/client/src/App.tsx` (lines ~143-148)

The `cove_return_path` from sessionStorage is navigated to blindly. A malicious or stale path (e.g. `/channels/deleted-guild/deleted-channel`) could lead to an invalid route. The ChannelView already handles invalid channels by redirecting to `/`, so this isn't a security issue per se, but validating the path starts with `/channels/` before using it would be cleaner.

### 4. `useBotStore` now depends on router module at import time

**File:** `packages/client/src/stores/useBotStore.ts`

Importing `getActiveIdsFromRouter` from `../lib/router` creates a hard dependency from a store to the router module. If the router hasn't initialized when the store module is first imported (possible in test environments or SSR), `router.state.matches` would be undefined. The test mock handles this, but it's worth adding a null-safety check in `getActiveIdsFromRouter`.

### 5. Thread close `navigate(-1)` relies on `window.history.state?.idx`

**File:** `packages/client/src/components/ChannelView.tsx` (line ~73)

`history.state.idx` is a React Router internal implementation detail (tracking history index). It works today but isn't part of the public API. If React Router changes how it tracks state, this breaks silently. Consider documenting this dependency or using `window.history.length === 1` as a supplementary check.

### 6. Spec mentions Safari bfcache handler — not implemented

The spec (docs/specs/428-url-routing.md, "Safari bfcache" edge case) mentions adding a `pageshow` event listener after OAuth. This wasn't implemented. Low priority but worth tracking.

---

## Positive Notes

1. **Excellent spec** — The 376-line design doc covers edge cases, history semantics, yo-yo prevention, scroll restoration, and migration scope. This is exemplary spec-driven development.

2. **Clean store separation** — Navigation state fully removed from zustand. Stores now hold only entity data. This is the correct architecture.

3. **`routes` helper** — Centralizing URL construction in `lib/routes.ts` prevents string duplication and makes future URL changes trivial.

4. **Lazy loading** — Route-level code splitting via `lazy()` is a free performance win.

5. **Non-React access pattern** — `getActiveIdsFromRouter()` using `router.state.matches` is type-safe and avoids regex duplication. Much better than parsing `window.location.pathname`.

6. **Test mocks updated** — The gateway-subscriptions test file properly mocks the new router imports and removes stale store references.

7. **READY handler respects URL** — Only auto-navigates on `/`. Deep links preserved. This was the #1 UX requirement.

---

## Verdict

⚠️ **Needs Changes**

The CHANNEL_DELETE race condition (issue #1) will cause incorrect redirects in multi-guild setups. The ThreadPanel fetch loop (issues #2, #3) could cause API spam under certain conditions. Both are real bugs that would surface in production. The fixes are straightforward (reorder one line; add a fetch guard).
