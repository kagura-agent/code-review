# PR #356 Review — Stella

## Summary

This PR cleanly wires channel-file create/update/delete events through the server dispatcher, browser client, and plugin cache invalidation path, and the `cove.md` cache is a good product/performance direction. The server-side permission filtering follows the existing bot `VIEW_CHANNEL` model, and route dispatch happens only after successful mutations. However, the browser subscription logic currently treats all channel-file events as if they belong to the currently open file sidebar, which can corrupt the sidebar state when events arrive for a different visible channel. I would fix that before merge; the cache implementation also needs a couple of resilience/performance hardening follow-ups.

## Critical Issues

1. **File sidebar refreshes with the wrong channel's files** — `packages/client/src/lib/gateway-subscriptions.ts:221-245`

   The new handlers check only `store.filesOpen`, then call `fetchFiles(data.channel_id)` / `fetchFile(data.channel_id, data.filename)`. Because the gateway broadcasts channel-scoped events for any visible channel in the guild, a user who has the file sidebar open on channel A can receive a file event for channel B. The handler will then load channel B's file list into the global `useChannelFilesStore`, so the sidebar for channel A displays channel B's files. On update/delete, if `selectedFile` has the same filename, it may also fetch channel B's content or clear the selection for channel A.

   **Fix:** gate these handlers on the current active channel before mutating the file store, e.g. compare `data.channel_id` with `useChannelStore.getState().activeChannelId`, or store the sidebar's current channel id in `useChannelFilesStore` and ignore events for other channels. Also consider clearing/refetching file state on active-channel changes so stale per-channel state cannot leak.

## Product Impact

- Users and bots should now receive realtime file-list updates after channel file create/update/delete, and the plugin can invalidate cached `cove.md` promptly instead of waiting for the TTL.
- With the current client bug, realtime updates can make the files sidebar show the wrong channel's files/content when multiple channels are active/visible in the same guild. This is confusing and potentially exposes the wrong in-app context to the user, though the REST fetch still uses authenticated APIs and server permissions.
- The 60s `cove.md` cache should reduce per-message REST reads and improve dispatch latency, while retaining stale content during transient fetch failures.

## Suggestions

- **Add tests for the new event paths.** There do not appear to be dedicated tests in this diff for `CHANNEL_FILE_*` dispatch, bot permission filtering for those specific event types, client subscription behavior, or plugin cache invalidation on `cove.md` events. At minimum, add:
  - server route/dispatcher test: PUT create vs update and DELETE emit the expected event only after success;
  - permission test: bot without `VIEW_CHANNEL` does not receive file events;
  - client subscription test: ignores events for non-active channels;
  - plugin test: `getCoveMd()` caches, invalidates, and falls back stale-on-error.
- **Bound or prune the `cove.md` cache** — `packages/plugin/src/cove-md-cache.ts:8-9`. The `Map` grows by channel id and entries are not removed on TTL expiry unless that channel is fetched again or invalidated. This is probably small per entry, but long-running plugins across many channels should have either max entries/LRU behavior, periodic pruning, or deletion of expired entries on access.
- **Consider extending stale-on-error behavior.** When a cached entry is stale and fetch fails, `getCoveMd()` returns stale content but leaves `fetchedAt` unchanged (`cove-md-cache.ts:28-31`). During an outage, every dispatch after TTL will retry the same 2s fetch and log a warning. Updating a separate `lastAttemptAt`/short error backoff, or temporarily refreshing `fetchedAt` for stale fallback, would avoid repeated latency and log noise.
- **Consider in-flight request deduplication** for `getCoveMd()`. Multiple simultaneous messages in the same uncached/expired channel can all fetch `cove.md` independently.
- **Runtime payload validation remains unchecked** in `packages/plugin/src/gateway-client.ts:265-276`. This matches existing gateway-client style, but for cache invalidation it would be safer to verify `channel_id` and `filename` are strings before emitting/acting on the event.

## Positive Notes

- Server mutation routes dispatch only after successful upsert/delete, and create vs update detection is straightforward and readable.
- `broadcastToGuildWithChannelFilter()` reuse is the right shape for matching existing channel event visibility semantics.
- Cache invalidation is narrowly scoped to `cove.md`, so unrelated channel-file churn does not flush useful context.
- The cache preserves the previous behavior of ignoring missing/oversized `cove.md` while reducing repeated REST calls on normal dispatches.

**Rate: ⚠️ Needs Changes**
