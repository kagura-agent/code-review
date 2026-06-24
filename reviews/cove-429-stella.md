# PR #429 Review — feat(client): URL-based channel routing (#428)

**Reviewer**: 🌟 Stella  
**Date**: 2026-06-24  
**Verdict**: ⚠️ Needs Changes

---

## Summary

Clean architectural migration from zustand-based navigation state to react-router-dom v6. The PR introduces URL-based routing with `createBrowserRouter`, removes `activeChannelId`/`activeGuildId`/`activeThread` from stores, and replaces them with a `useActiveIds()` hook and `getActiveIdsFromRouter()` helper for non-React code. Route definitions use lazy loading, the spec is thorough, and edge cases (READY handler, OAuth, channel deletion, thread deep links) are handled. However, there are a race condition in channel validation, a potential infinite redirect loop, and missing error handling on thread fetch that warrant fixes before merge.

---

## Critical Issues

### 1. Race condition: Thread validation fires fetchThread then navigates away prematurely

**File**: `ChannelView.tsx`, lines 55–65

```
if (channelsLoaded && !threadExists) {
  useThreadStore.getState().fetchThread(threadId).then((thread) => {
    if (!thread && guildId && channelId) {
      navigate(routes.channel(guildId, channelId), { replace: true });
    }
  });
}
```

The effect depends on `threads` in the dependency array. If `fetchThread` resolves and adds the thread to the store, the effect re-fires *before* the `.then()` navigates — but the check `!threadExists` will now pass (since the store updated). On subsequent re-renders the effect is a no-op. However, if `fetchThread` *rejects* (network error), the `.catch()` is unhandled — the promise silently swallows the error and the user is left on a broken thread URL. Add `.catch(() => navigate(routes.channel(guildId, channelId), { replace: true }))` or handle errors.

### 2. Potential redirect loop in `RedirectToDefault` when guilds exist but have zero channels

**File**: `RedirectToDefault.tsx`, lines 16–22

If `channelsLoaded === true` and `channels.length === 0` (e.g., all channels deleted), the component renders `null` indefinitely. But combined with the READY handler which also tries to navigate on `/`, there's no visible feedback. This isn't a loop per se, but the user sees a blank screen with no indication of what's happening. Should render a "no channels available" state or at minimum a loading skeleton.

### 3. `CHANNEL_DELETE` handler calls `getGuildForChannel` *after* removing the channel

**File**: `gateway-subscriptions.ts`, lines ~197–213

```
useChannelStore.getState().removeChannel(data.id);
// ...
if (data.id === activeChannelId) {
  const guildId = getGuildForChannel(data.id) ?? Object.keys(...)[0];
```

`getGuildForChannel` scans `channelsByGuildId` — but the channel was just removed from the store on the line above. The lookup will always return `null`, falling through to the first guild ID from the guilds object. This works by accident in a single-guild setup but will navigate to the wrong guild's channel in multi-guild scenarios. Fix: capture guildId *before* calling `removeChannel`.

---

## Product Impact

1. **Deep linking now works** — users can share `/channels/x/y/threads/z` URLs and recipients land directly on that view. This is a significant UX improvement.

2. **Back/forward navigation** — browser history works for channel and thread transitions. Thread close via X uses `navigate(-1)` with deep-link fallback — correct behavior.

3. **Potential disruption**: Existing bookmarks to `/` will auto-redirect to the first channel. Old browser tabs with stale JS on a `/channels/...` path will hit the new router — old JS won't recognize these routes and will fall through to `/`. The spec mentions this (version check on mount), but the implementation doesn't include it yet. Low risk since Caddy serves fresh HTML.

4. **OAuth flow**: `sessionStorage.setItem("cove_return_path", ...)` correctly preserves the URL before redirect. The restore effect in `App.tsx` fires after auth loads. Works correctly.

5. **`useScrollRestoration` hook is defined but not wired up** — scroll position won't actually be preserved on channel switch yet. This matches the spec as future work but users will notice scroll-to-top on channel switch (existing behavior, not a regression).

---

## Suggestions

1. **`useScrollRestoration` missing `scrollRef` in deps** — `useScrollRestoration.ts` lines 11 and 18: Both effects depend on `channelId` but read `scrollRef.current`. If the ref changes without `channelId` changing, the save/restore won't fire. Consider adding a ref-stable pattern or documenting that the ref must be stable across the effect's lifetime.

2. **Consolidate router imports** — `MessageContextMenu.tsx` imports both `router` and `getActiveIdsFromRouter` from `"../lib/router"` in two separate import statements. Merge into one.

3. **`ThreadPanel` double-fetch** — Both `ChannelView` (line 57) and `ThreadPanel` (line 33) call `fetchThread(threadId)` independently for the deep-link case. If both effects fire simultaneously, two API calls go out. Consider having only `ChannelView` handle the fetch-or-redirect logic, and pass thread data down.

4. **`useBotStore.ts`** now imports `getActiveIdsFromRouter` from the router — this couples the store module to the router module at import time. Fine for now but worth noting if you later need SSR or testing in isolation.

5. **`window.history.state?.idx === 0` check in `closeThread`** — this relies on React Router's internal history state shape (`idx`). It's not part of the public API and could break on router upgrades. Consider using `window.history.length === 1` as a more standard check, or accept the minor risk with a comment.

6. **Missing 404/catch-all route** — The router only defines `/`, `/channels/:guildId/:channelId`, and the thread sub-route. Any other path (e.g., `/settings`, typos) will show a blank page. Add a catch-all that redirects to `/`.

---

## Positive Notes

- **Excellent spec** (`docs/specs/428-url-routing.md`) — thorough, opinionated, covers edge cases, includes the "yo-yo problem" analysis. Ship-quality documentation.
- **Clean store cleanup** — complete removal of navigation state from three stores with no lingering dead code.
- **Lazy route loading** — `router.tsx` uses dynamic `import()` for code splitting, which is good for bundle size.
- **`routes.ts` path helpers** — centralizing URL construction prevents scattered template literals. Simple and effective.
- **Test file updated** — mocks properly updated for the new router dependency, not left broken.
- **`getActiveIdsFromRouter()` using `router.state.matches`** — type-safe, avoids regex URL parsing duplication.
- **Thread history semantics** (push to open, go(-1) to close) match the spec exactly and are well-reasoned.
