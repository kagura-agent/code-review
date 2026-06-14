# 🌠 Nova — Round 2 Re-Review: PR #356 (cove)

**PR:** `feat: WS events for channel files + cove.md plugin cache (closes #354, closes #353)`
**Branch:** `feat/channel-files-ws-cache`
**R2 fix commit:** `56cb321` — *fix: cross-channel file event filtering, cache LRU eviction, add monaco dep*
**Diff size:** 10 files, +164 / −13.

---

## 1. R1 Issue Status

### 🔴 Cross-channel sidebar bug (Stella) — ✅ **Fixed**

R2 commit modifies all three subscribers in `packages/client/src/lib/gateway-subscriptions.ts` to gate on the active channel:

```ts
subscribe("CHANNEL_FILE_CREATE", (data) => {
  const store = useChannelFilesStore.getState();
  const activeChannelId = useChannelStore.getState().activeChannelId;
  if (store.filesOpen && data.channel_id === activeChannelId) {
    store.fetchFiles(data.channel_id);
  }
});
```

`UPDATE` and `DELETE` apply the same guard, and `UPDATE`/`DELETE` additionally key the file-content refresh / clear on `store.selectedFile === data.filename`. The previous bug (sidebar in channel A reloading because a file mutated in channel B) is closed.

**Caveat (not blocking):** because the handler always reads `useChannelStore.getState().activeChannelId` at event time, switching channels between an in-flight mutation and the WS echo can drop the refresh. Acceptable — when the user re-enters that channel the sidebar is re-fetched on open. Worth a comment, not a change.

---

### 🟡 Cache unbounded — ✅ **Fixed** (with minor reservations)

`packages/plugin/src/cove-md-cache.ts` now tracks `lastAccessedAt` on every hit and evicts when `cache.size > MAX_ENTRIES` (500):

```ts
function evictIfNeeded(): void {
  if (cache.size <= MAX_ENTRIES) return;
  const entries = [...cache.entries()].sort((a, b) => a[1].lastAccessedAt - b[1].lastAccessedAt);
  const toRemove = entries.slice(0, cache.size - MAX_ENTRIES);
  for (const [key] of toRemove) cache.delete(key);
}
```

Functionally correct LRU eviction, the cap is bounded, and `invalidateCoveMd`/`invalidateAllCoveMd` are exported. Issue is closed.

**Nits (not blocking):**
- `evictIfNeeded` runs a full `Map.entries() → sort` on every insertion past 500. O(n log n) on each write. Fine at 500, would be uncomfortable above ~5k. Since you only ever evict one entry past the cap, a single-pass min-scan (O(n)) or a true LRU (`Map` insertion-order trick: `delete`+`set` on hit, then `cache.keys().next().value` to evict) would be cheaper.
- `MAX_ENTRIES = 500` is a module-level constant with no comment justifying it. Consider documenting (e.g. "500 channels × ~8KB = ~4MB worst case").

---

### 🟡 R1 suggestions — status

| Suggestion | Status | Notes |
|---|---|---|
| **Missing tests** | ❌ **Not added** | No new test file. `channel-files.test.ts` was not extended (no asserts on dispatcher calls). No test for `cove-md-cache` (TTL, LRU, stale-on-error, invalidation). No client subscription test for the channel-filter fix. This is the biggest gap. |
| **Create-vs-update race** | ⚠️ **Partial / unaddressed** | Route now does `existing = repos.channelFiles.get(...)` before `upsert(...)` to decide CREATE vs UPDATE. Two concurrent PUTs of a new file can still both observe `existing == null` and each fire `CHANNEL_FILE_CREATE`. Cosmetic, not corrupting (upsert is the source of truth), but the fix from R1 (return create/update info from `upsert`) would be cleaner. |
| **In-flight dedup** | ❌ **Not addressed** | `getCoveMd` still launches a new fetch per cache miss; N concurrent dispatches for one channel = N round-trips. Low-priority, fixable with a `Map<channelId, Promise>` of in-flight requests. |
| **`cove.md` filename constant** | ❌ **Not addressed** | Still string-literal `"cove.md"` in `cove-md-cache.ts` (line 35), `channel.ts` (×3, lines 360/363/366), and in the server sorter (`packages/server/src/repos/channel-files.ts:27`). One shared constant in `@cove/shared` would prevent typo drift. |
| **No-op PUT broadcast** | ❌ **Not addressed** | PUT always broadcasts `CHANNEL_FILE_UPDATE` even when `body.content` equals the stored content. Causes redundant cache invalidations + client re-fetches. Comparing the old vs new file before dispatching would be cheap. |
| **Cache shutdown / multi-account isolation** | ❌ **Not addressed** | `cache` is a module-level `Map` — one global cache shared across all `CoveAccount` instances. `ctx.abortSignal` shutdown of the plugin does not call `invalidateAllCoveMd()`. If two accounts coexist with overlapping `channelId`s (unlikely today but not impossible), the cache will leak across them. Acceptable for the current single-account model; document the assumption. |

---

## 2. New Issues (Round 2)

### 🟡 N1 — `cove-md-cache` is a module singleton

Same root concern as R1 cache-shutdown but worth restating: storing the cache as a top-level `const cache = new Map(...)` means:
- Cannot be swapped/cleared per `CoveAccount`.
- Survives plugin restart within the same Node process (no abort-signal hook).
- Cannot be reset between tests, which probably explains why no tests were written. Wrapping in `createCoveMdCache()` returning an object would make it testable + per-instance.

### 🟡 N2 — `getCoveMd` `log` typing leaks `any`

```ts
log?: { warn?: (...a: any[]) => void }
```

`any` here disables type-checking on log call sites. The rest of the codebase has a real logger type — reuse it (`Logger | undefined`).

### 🟢 N3 — `evictIfNeeded` called *after* `cache.set`

Minor: on the path where the entry being inserted is the LRU oldest (e.g. just-resumed cold cache + a flood of new misses), it would be inserted then evicted on the next call. Not a correctness issue, just inefficiency. The single-pass LRU rewrite fixes this too.

### 🟢 N4 — Dispatcher type widening

In `gateway-client.ts`:
```ts
this.emit("channelFileCreate", payload.d as { channel_id: string; ... });
```
Casting raw payloads with `as` skips runtime validation. The other branches in the same dispatcher do the same, so this is consistent — but a zod schema on incoming WS frames is a longstanding tech debt this PR could have cited.

### 🟢 N5 — `dispatcher?` is optional in `channelFilesRoutes`

API supports calling without a dispatcher (used by the test harness). That's fine, but the production call site in `app.ts` always provides one, so the optionality is effectively just for tests. Consider a typed `NoopDispatcher` to remove the `if (dispatcher)` branches in the route — cleaner and one less code path to test.

### 🟢 N6 — `fetchFiles` re-fetch on every event

When several files in the active channel mutate in quick succession (e.g. a bot bulk-writing), every event triggers a full `fetchFiles` list call. A small debounce (50–100ms trailing) in the store would coalesce. Not in PR scope, file as follow-up.

---

## 3. Verdict

### Summary
The two **blocking** R1 findings — cross-channel sidebar leakage and unbounded cache — are properly fixed and the fixes are correct. The dispatcher → client wiring is sound, permission filtering (`broadcastToGuildWithChannelFilter` + `VIEW_CHANNEL_BIT`) is reused consistently with reactions, and the cache is now bounded with a reasonable cap.

The **major remaining gap is testing**: zero new tests were added even though both bugs are easy to assert (one dispatcher spy on the route, a few `Date.now()`-mocked tests on the cache). The other R1 nits (filename constant, no-op PUT, in-flight dedup, per-account cache scope) are all left open.

### Verdict: ⚠️ **Needs Changes** *(soft — almost Ready)*

Acceptable to merge as-is *if* the team agrees to open a follow-up tracker for tests + the deferred nits. If R2 was supposed to address Round-1 testing explicitly, that bar is not met yet.

**Strict ask before merge:**
1. Add at least: (a) a route test asserting `dispatcher.channelFileCreate` vs `…Update` on first/second PUT, and (b) a cache test asserting TTL expiry + LRU eviction at 500 entries.

**Nice-to-have (follow-up issue is fine):**
2. Hoist `"cove.md"` to a shared constant.
3. No-op PUT short-circuit (don't broadcast UPDATE if content+type unchanged).
4. Wrap `cove-md-cache` in a factory + register `invalidateAllCoveMd()` on `ctx.abortSignal`.
5. Type the `log` parameter properly.

Good response to R1 on the blockers. Testing is the only thing keeping this from a green.
