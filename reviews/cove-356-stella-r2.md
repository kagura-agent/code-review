# PR #356 Round 2 Re-review — Stella

## 1. R1 Issue Status

### 🔴 Cross-channel files sidebar bug — ✅ Fixed

Verified the R2 gate is present and correctly scoped in `packages/client/src/lib/gateway-subscriptions.ts`:

- `CHANNEL_FILE_CREATE`: only calls `fetchFiles(data.channel_id)` when `store.filesOpen && data.channel_id === activeChannelId`.
- `CHANNEL_FILE_UPDATE`: same active-channel gate before refreshing the list/content.
- `CHANNEL_FILE_DELETE`: same active-channel gate before refreshing/clearing selection.

This prevents file events from another channel with the same filename from refreshing or clearing the currently open sidebar.

### 🟡 Unbounded cove.md cache — ✅ Fixed

Verified `packages/plugin/src/cove-md-cache.ts` now bounds the cache:

- `MAX_ENTRIES = 500`.
- Each entry tracks `lastAccessedAt`.
- TTL hits update `lastAccessedAt`.
- Successful fetches insert/update the entry, then `evictIfNeeded()` sorts by `lastAccessedAt` and removes the oldest entries until size is back to 500.

This addresses the unbounded-growth concern. The eviction path is O(n log n), but with a 500-entry cap that is acceptable.

### 🟡 Missing tests — ❌ Not Fixed

No test files were added or changed in this PR. The changed file list is still only implementation files:

- client dispatcher/subscriptions
- plugin gateway/cache/dispatch files
- server app/routes/dispatcher files

Existing client tests pass locally (`pnpm -F @cove/client test` → 2 files / 6 tests passed), but there is still no coverage for the new file-event subscriptions, cache eviction, cove.md invalidation, or server dispatch behavior.

### Other R1 suggestions — ⚠️ Mostly Not Addressed / Non-blocking

- Create-vs-update race: unchanged. Current `get()` then `upsert()` is synchronous in this implementation, so likely fine for the current in-process repo, but still not atomic if the repo/backend changes later.
- In-flight dedup for cove.md fetches: not added.
- Stale-on-error retry/log noise: unchanged; after TTL expiry, repeated fetch failures can still log once per dispatch attempt while serving stale/null.
- No-op PUT broadcasts: unchanged; PUT still emits `CHANNEL_FILE_UPDATE` even when content/metadata are unchanged.

## 2. New Issues

No new correctness, security, or API-design issues found in R2.

One testing gap remains important: the fixed cross-channel behavior is not covered by regression tests, so it could regress easily. A small test in `gateway-subscriptions.test.ts` that emits file events for active vs inactive channels would lock down the main R1 bug.

## 3. Summary + Verdict

The main functional blocker from R1 is fixed: file sidebar event handlers now correctly require `data.channel_id === activeChannelId`. The cache is also now bounded with LRU-style eviction at 500 entries.

However, the PR still has no tests for the new behavior, including the exact cross-channel regression that was found in R1. Because the remaining issue is testing rather than a current correctness bug, this is not a major blocker, but I would still request changes before merge.

**Verdict: ⚠️ Needs Changes**
