# Code Review: PR #429 — feat(client): URL-based channel routing (#428)

**Reviewer:** 💫 Vega (Round 2)  
**PR:** https://github.com/kagura-agent/cove/pull/429  
**Branch:** feat/428-url-routing  
**Commit under review:** 521858c (fix commit)  
**Date:** 2026-06-24

---

## Previous Issues Status

### 1. ✅ CHANNEL_DELETE race — Fixed

**Round 1 issue:** `getGuildForChannel(data.id)` was called after `removeChannel(data.id)`, causing wrong guild lookup in multi-guild scenarios.

**Fix verification:**
```typescript
subscribe("CHANNEL_DELETE", (data) => {
    const { channelId: activeChannelId } = getActiveIdsFromRouter();
    // Resolve guild BEFORE removing the channel from the store
    const guildId = getGuildForChannel(data.id) ?? Object.keys(useGuildStore.getState().guilds)[0];
    useChannelStore.getState().removeChannel(data.id);
    // ...
```

Guild is now resolved **before** `removeChannel()` is called. Fallback to first guild if not found. Correct redirect logic follows: navigates to next available channel in the same guild, or root if none available. ✅ Complete and correct fix.

---

### 2. ⚠️ ThreadPanel fetch loop — Partially Fixed

**Round 1 issue:** `threads` (entire store object) as dependency causes every unrelated thread update to re-fire effect + fetchThread.

**Current state in ThreadPanel:**
```typescript
const threads = useThreadStore((s) => s.threads);  // ALL threads, all channels
// ...
useEffect(() => {
    let found: Channel | null = null;
    for (const channelThreads of Object.values(threads)) {
      const t = channelThreads.find((t) => t.id === threadId);
      if (t) { found = t; break; }
    }
    if (found) {
      setThread(found);
    } else {
      useThreadStore.getState().fetchThread(threadId).then((t) => {
        if (t) setThread(t);
      });
    }
}, [threadId, threads]);  // ← entire threads object as dep
```

**Problems remaining:**
1. **Still subscribes to entire `threads` store** — any thread update in any channel triggers a re-run.
2. **No fetch guard ref** — unlike ChannelView which uses `threadFetchRef`, ThreadPanel has no guard. If thread is not in the store (deep-link to archived/removed thread) and any unrelated thread update fires, it will re-fetch repeatedly.
3. **`fetchThread` doesn't persist to store** — it returns the channel but doesn't call `addThread()`. So in the deep-link case where the thread isn't included in READY data, `threads` will never contain it, and every store update re-triggers a fetch.

**Severity escalation:** The ChannelView pattern was correctly fixed (targeted selector + ref guard). But ThreadPanel still has the same fundamental issue. The practical impact is reduced (once READY loads threads, the thread is usually found), but for edge cases (archived threads, deep-links to threads from other channels), this remains a fetch loop.

---

### 3. ✅ ChannelView thread validation fetch loop — Fixed

**Round 1 issue:** Same pattern as #2 — `threads` dependency causes repeated fetchThread calls.

**Fix verification:**
```typescript
// Targeted selector — only this channel's threads
const channelThreads = useThreadStore((s) => s.threads[channelId ?? ""] ?? []);
const threadFetchRef = useRef<string | null>(null);

useEffect(() => {
    if (!threadId || !channelId) return;
    const threadExists = channelThreads.some((t) => t.id === threadId);
    if (channelsLoaded && !threadExists) {
      // Guard: don't re-fetch if already in progress or completed for this threadId
      if (threadFetchRef.current === threadId) return;
      threadFetchRef.current = threadId;
      useThreadStore.getState().fetchThread(threadId).then(/* ... */);
    }
}, [threadId, channelId, guildId, channelsLoaded, channelThreads, navigate]);
```

Two-pronged fix: (1) targeted selector `s.threads[channelId]` avoids re-fires from unrelated channels, (2) `threadFetchRef` guard prevents re-fetching even if the effect does re-fire. ✅ Complete fix.

---

## New Critical Issues

### None

No new blocking issues identified in the fix commit.

---

## Suggestions (Non-blocking)

### 1. ThreadPanel: Add fetch guard ref (consistency with ChannelView)

ThreadPanel should mirror ChannelView's pattern:
```typescript
const threadFetchRef = useRef<string | null>(null);
// In effect's else branch:
if (threadFetchRef.current === threadId) return;
threadFetchRef.current = threadId;
useThreadStore.getState().fetchThread(threadId).then(/* ... */);
```

This prevents the edge-case re-fetch loop and aligns both components.

### 2. ThreadPanel: Use targeted selector instead of entire `threads` object

Instead of:
```typescript
const threads = useThreadStore((s) => s.threads);
```

Consider passing `channelId` (parent) from props or URL and doing:
```typescript
const channelThreads = useThreadStore((s) => s.threads[parentChannelId ?? ""] ?? []);
```

ThreadPanel already receives `threadId` — deriving `parentChannelId` from the URL (`channelId` param) would enable a targeted selector and prevent unnecessary re-renders.

### 3. `useScrollRestoration` — missing `scrollRef` in deps array

```typescript
useEffect(() => {
    const el = scrollRef.current;
    return () => { if (el) scrollPositions.set(channelId, el.scrollTop); };
}, [channelId]);  // scrollRef not listed
```

While `RefObject` is stable (so functionally fine), the exhaustive-deps lint rule will flag this. Adding `scrollRef` silences the warning without behavior change.

### 4. RedirectToDefault — broad selectors cause unnecessary re-renders

```typescript
const guilds = useGuildStore((s) => s.guilds);
const channelsByGuildId = useChannelStore((s) => s.channelsByGuildId);
```

Any guild/channel change re-renders this component and re-runs the effect. Since it only needs the first guild's first channel, a targeted selector would be more efficient:
```typescript
const firstGuildId = useGuildStore((s) => Object.keys(s.guilds)[0] ?? null);
const firstChannel = useChannelStore((s) => firstGuildId ? (s.channelsByGuildId[firstGuildId]?.[0] ?? null) : null);
```

### 5. `navigate(-1)` relies on `window.history.state?.idx` (React Router internal)

```typescript
if (window.history.state?.idx === 0) {
    navigate(routes.channel(guildId, channelId), { replace: true });
} else {
    navigate(-1);
}
```

`idx` is an internal React Router implementation detail. Consider tracking whether the thread was opened via push in component state instead (e.g., a ref set to `true` on thread open navigation).

### 6. OAuth return path — no validation

```typescript
const returnPath = sessionStorage.getItem("cove_return_path");
if (returnPath && returnPath !== "/") {
    router.navigate(returnPath, { replace: true });
}
```

While React Router's `navigate()` only handles in-app paths (so external URLs won't cause a redirect), adding basic validation (e.g., `returnPath.startsWith("/channels/")`) provides defense-in-depth against session storage manipulation.

### 7. Spec mentions Safari bfcache handler — not implemented

The spec includes:
> Add `window.addEventListener("pageshow", (e) => { if (e.persisted) window.location.reload(); })` in auth flow.

This is not present in the implementation. Low priority but worth tracking as a follow-up.

---

## Verdict

### ⚠️ Needs Minor Changes

The three Round 1 critical issues have been substantively addressed:
- **CHANNEL_DELETE race**: ✅ Fully fixed
- **ChannelView fetch loop**: ✅ Fully fixed  
- **ThreadPanel fetch loop**: ⚠️ Partially fixed (ChannelView is correct, but ThreadPanel still lacks the guard ref and uses a broad selector)

The ThreadPanel issue is no longer **critical** in the strict sense — the realistic impact is limited to edge cases (deep-links to threads not in READY data + concurrent thread updates). However, per escalation rules, I cannot downgrade it. The fix pattern exists in ChannelView and should be consistently applied to ThreadPanel.

**Recommendation:** Add a `threadFetchRef` guard to ThreadPanel's fetch path (2-line change), matching the pattern already established in ChannelView. After that, this PR is ready to merge.
