# Code Review: PR #429 — feat(client): URL-based channel routing (#428)

**Reviewer:** 🌠 Nova  
**Round:** 2 (re-review after commit 521858c)  
**Date:** 2026-06-24

---

## 1. Previous Issues Status

### Critical Issue 1: `useScrollRestoration` hook defined but never integrated
**❌ Not fixed**

The hook is still defined in `packages/client/src/hooks/useScrollRestoration.ts` but is never imported or called from any component. `grep` confirms zero imports of `useScrollRestoration` across the entire diff. This is dead code that the spec explicitly lists as needed behavior (per-channel scroll position memory). Either integrate it into `MessageList` / `ChannelView`, or remove it from this PR and track as a separate issue.

**Severity escalation:** This was Critical in Round 1 and remains unaddressed → stays Critical. The spec's acceptance criteria implies scroll restoration as part of the routing feature (users switching channels lose scroll position without it).

### Critical Issue 2: Race condition in ChannelView thread validation
**✅ Fixed**

Two effective mitigations applied:
1. **Targeted selector** — `useThreadStore((s) => s.threads[channelId ?? ""] ?? [])` instead of subscribing to the full `threads` object. This prevents the effect from re-firing on unrelated channel thread updates.
2. **Ref guard** — `threadFetchRef` prevents duplicate/infinite fetch loops for the same threadId.

The combination eliminates the infinite fetch loop risk. Good fix.

### Critical Issue 3: CHANNEL_DELETE handler reads stale channel list
**✅ Fixed**

The handler now resolves the guild **before** removing the channel:
```typescript
const guildId = getGuildForChannel(data.id) ?? Object.keys(useGuildStore.getState().guilds)[0];
useChannelStore.getState().removeChannel(data.id);
```

The ordering is correct and the fallback to first guild is a sensible default. Clean fix.

---

## 2. New Critical Issues

### 2.1 None identified as blocking.

The remaining unresolved issue (useScrollRestoration) is escalated from Round 1 rather than a new finding.

---

## 3. Suggestions (Non-blocking)

### 3.1 ThreadPanel subscribes to entire `threads` record (performance)
```typescript
const threads = useThreadStore((s) => s.threads);
```
Unlike ChannelView which uses a targeted selector, ThreadPanel subscribes to ALL threads across all channels. Any thread update anywhere triggers a re-render + effect re-evaluation. Consider using a targeted selector like ChannelView does, or computing a stable derived value.

### 3.2 Lazy routes have no `errorElement` / error boundary
The router uses `lazy()` for all route components but provides no `errorElement` on any route. If chunk loading fails (network blip, stale deployment), the user gets an unhandled crash with no recovery path. Add at minimum:
```typescript
{
  path: "/",
  errorElement: <RouteErrorBoundary />,
  lazy: () => import("../AppShell")...
}
```

### 3.3 Double-fetch on deep-linked threads
Both `ChannelView` (validation effect) and `ThreadPanel` (lookup effect) independently call `fetchThread(threadId)` on deep link. This results in 2 API calls for the same resource. Consider having ChannelView's fetch also call `addThread()` to seed the store, so ThreadPanel finds it without a second fetch.

### 3.4 `fetchThread` doesn't update the store
`useThreadStore.fetchThread()` returns the channel but never calls `addThread()`. This means the fetched thread data is ephemeral — it lives only in local component state (ThreadPanel) and is lost if the component remounts. If the user navigates away and back, it fetches again.

### 3.5 `RedirectToDefault` relies on Object.keys() ordering
`Object.keys(guilds)[0]` for selecting the default guild. If guild IDs are numeric strings, V8's object key ordering rules may not match expected "first guild" semantics. Consider storing guild order explicitly or using an array.

### 3.6 `useBotStore` imports from `../lib/router` — coupling concern
`useBotStore` now imports `getActiveIdsFromRouter` directly from the router module. This couples a data store to the routing layer. Minor, but worth noting if you plan to unit-test stores independently.

### 3.7 Test mock for `router.navigate` doesn't verify calls
The test file mocks `router: { navigate: vi.fn() }` but no assertions check that navigation was called with correct arguments in CHANNEL_DELETE or READY scenarios. Consider adding assertions for the critical navigation paths.

---

## 4. Verdict

**⚠️ Needs Changes**

Two of three Round 1 critical issues are properly fixed. However, `useScrollRestoration` remains dead code — the hook exists but is never wired into the component tree. Per the escalation rule, this stays Critical since it was raised in Round 1 and not addressed.

**Required for approval:**
- Either integrate `useScrollRestoration` into the relevant component (likely `MessageList` or `ChannelView`), OR remove it from this PR and create a follow-up issue acknowledging it as incomplete scope.

**Nice-to-have before merge:**
- Add `errorElement` to the root route for lazy-load failure resilience
- Fix ThreadPanel's broad store subscription
