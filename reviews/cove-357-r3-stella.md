# PR #357 R3 Re-review — Stella

## R2 Issues Status

1. **Nested thread creation not blocked** — ✅ Fixed
   - Both create endpoints now reject `channel.type === 11` before creating a child thread (`packages/server/src/routes/threads.ts:17-21`, `70-74`).

2. **N+1 active-threads fetch on READY** — ✅ Fixed
   - READY handling now calls the guild-level active threads endpoint once per guild and groups by parent locally (`packages/client/src/lib/gateway-subscriptions.ts:145-156`), instead of fetching per channel.

3. **`threadDelete` dead code** — ✅ Fixed
   - `DELETE /channels/:id` now calls `dispatcher.threadDelete(ch)` for type 11 channels (`packages/server/src/routes/channels.ts:165-168`).
   - Note: the route also emits `CHANNEL_DELETE` first, which is not permission-filtered and may be semantically noisy for thread deletes; I listed that below as a fresh issue rather than counting this blocker as unfixed.

## New Issues

### Blocking / Needs Changes

1. **Archived and locked threads still accept message writes**
   - R2 listed this as non-blocking; it remains unaddressed and should be escalated.
   - `POST /channels/:id/messages` checks guild membership and view permission, but never checks `channel.type === 11` metadata before creating the message (`packages/server/src/routes/messages.ts:63-113`).
   - This means `PATCH /channels/:threadId { archived: true }` or `{ locked: true }` changes metadata, but clients/API can still send messages into the thread.
   - Expected: reject writes to archived threads, and reject writes to locked threads unless the eventual moderator/management permission allows it.

2. **Guild active-threads endpoint still leaks threads from parent channels the bot cannot view**
   - R2 listed this as non-blocking; it remains unaddressed and should be escalated.
   - `GET /guilds/:guildId/threads/active` validates only guild existence and guild membership, then returns `repos.threads.listActiveByGuild(guildId)` without filtering by inherited parent-channel `VIEW_CHANNEL` (`packages/server/src/routes/threads.ts:120-133`).
   - This can disclose active thread IDs/names/counts from channels hidden from the bot/user. The channel-scoped endpoint has a permission check; the guild-scoped endpoint needs equivalent per-thread parent filtering.

3. **Thread `message_count` still goes stale on bulk delete and clear-all**
   - R2 listed this as non-blocking; it remains unaddressed and should be escalated.
   - Single-message delete decrements the thread counter (`packages/server/src/routes/messages.ts:213-216`), but bulk delete and clear-all only delete messages/recompute `last_message_id` (`packages/server/src/routes/messages.ts:249-280`).
   - Result: deleting multiple/all messages from a thread leaves the parent thread indicator showing inflated reply counts.

4. **Thread creation has a race that can create duplicate message threads**
   - The route checks for an existing thread in application code, then inserts (`packages/server/src/routes/threads.ts:45-58`), but the schema has no unique constraint/index on `channels.message_id` for type 11 channels.
   - Two concurrent requests for the same parent message can both pass `getThreadForMessage()` and insert duplicate threads. This breaks the one-thread-per-message invariant the API is trying to enforce.
   - Expected: add a DB-level uniqueness guard, e.g. a partial unique index on `channels(message_id)` where `type = 11 AND message_id IS NOT NULL`, and handle constraint errors as the existing 400 response.

### Escalated R2 leftovers / Non-blocking but still open

5. **Leave route still lacks a guild-membership guard**
   - Join/add/list check `repos.members.exists(thread.guild_id, user.id)`, but leave does not (`packages/server/src/routes/threads.ts:156-170`).
   - For non-bot users, `requireBotChannelPermission` returns true, so a non-member with a valid token and known thread ID can hit the route. It mostly deletes their own row if present, but it should be consistent with the other thread-member routes.

6. **No negative permission tests for thread permission inheritance / guild active-thread leak**
   - The new tests cover happy paths and non-thread 404s, but I did not find tests proving hidden parent channels block thread create/list/join/message/gateway visibility, especially for the guild-level active thread endpoint.

7. **Drag handler listener leak still exists**
   - The resize handler adds document-level `mousemove`/`mouseup` listeners and removes them only from `onMouseUp` (`packages/client/src/App.tsx:165-181`).
   - If the panel unmounts/closes mid-drag, the listeners survive. Add effect cleanup or use a stable drag effect tied to `resizeDragging`.

8. **Emoji / surrogate-pair corruption on thread auto-naming still exists**
   - `content.slice(0, 40)` can split surrogate pairs / grapheme clusters (`packages/client/src/components/MessageContextMenu.tsx:99-100`). Use code-point or grapheme-aware truncation.

9. **Missing moderator removal route remains open**
   - The PR added `PUT /channels/:threadId/thread-members/:userId` for adding a user (`packages/server/src/routes/threads.ts:173-198`), but there is still no corresponding route to remove another user from a thread.

10. **Unused `channelId` prop in `ThreadIndicator` remains open**
   - `ThreadIndicator` declares `channelId` in `Props`, callers pass it, but the component ignores it (`packages/client/src/components/ThreadIndicator.tsx:3-9`).

### Additional fresh concern

11. **Deleting a thread emits both unfiltered `CHANNEL_DELETE` and filtered `THREAD_DELETE`**
   - `DELETE /channels/:id` always emits `channelDelete`, then emits `threadDelete` for type 11 (`packages/server/src/routes/channels.ts:165-168`).
   - `channelDelete` uses `broadcastToGuild`, not the parent-channel permission filter (`packages/server/src/ws/dispatcher.ts:106-108`), so bot sessions that cannot view the parent can still learn that a channel/thread ID was deleted.
   - For thread deletion, consider emitting only `THREAD_DELETE`, or make the `CHANNEL_DELETE` path permission-filtered/thread-aware.

## Summary + Verdict

❌ **Major Issues**

The three R2 blocking issues are fixed. However, several R2 non-blocking issues were not addressed and now need escalation, especially archived/locked thread writes, guild active-thread permission leakage, and stale `message_count` after bulk/clear-all deletes. I also found a new duplicate-thread race due to lack of a DB uniqueness constraint. This should not merge until those are fixed.
