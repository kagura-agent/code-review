# PR #357 Round 2 Re-review — Stella

## 1. R1 Issues Status

1. **Thread-member routes missing `requireBotChannelPermission`** — ✅ **Fixed for the originally called out routes**
   - `join`, `leave`, `add`, and `list` now check the parent channel permission via `requireBotChannelPermission(repos, thread.parent_id!, ...)`.
   - `requireBotChannelPermission` also now understands thread channels and falls back to the parent channel.
   - Note: I found a new related permission leak on the guild active-threads route below.

2. **No tests** — ✅ **Fixed**
   - Added `packages/server/src/__tests__/threads.test.ts` with coverage for thread creation, member join/leave/list, active-thread listing, archive/unarchive, and message enrichment.
   - I ran the focused suite: `pnpm -F @cove/server exec vitest run src/__tests__/threads.test.ts --reporter=dot` → **29 tests passed**.

3. **`auto_archive_duration` unvalidated** — ✅ **Fixed**
   - Both create routes validate against `[60, 1440, 4320, 10080]` before persisting.

4. **Thread indicator state sync** — ✅ **Fixed**
   - Parent messages are enriched with `thread` on list/single-message fetch.
   - Client `THREAD_CREATE` handling updates `useMessageStore.setMessageThread(...)`, so existing parent messages can display the indicator without a full refetch.

## 2. New Issues

### 1. High — Guild active-threads endpoint leaks threads from channels the bot cannot view

`GET /guilds/:guildId/threads/active` only verifies guild membership, then returns every active thread in the guild:

- `packages/server/src/routes/threads.ts:115-127`
- `repos.threads.listActiveByGuild(guildId)` has no parent-channel permission filtering.

This bypasses the parent-channel VIEW_CHANNEL filtering added for the per-channel thread/member routes. A bot that lacks access to a private/hidden parent channel can still enumerate that channel's active thread IDs, names, parent IDs, owners, and metadata through the guild-wide route.

Recommendation: for bot users, filter returned threads by `requireBotChannelPermission(repos, thread.parent_id, user.id, true)` or push that permission-aware filtering into a route/service layer. Add a regression test with two channels where the bot can view only one parent channel.

### 2. Medium — Nested threads are still allowed

Both create routes accept any channel that passes guild membership + VIEW_CHANNEL checks, but neither rejects `channel.type === 11`:

- `POST /channels/:channelId/messages/:messageId/threads`: `packages/server/src/routes/threads.ts:17-55`
- `POST /channels/:channelId/threads`: `packages/server/src/routes/threads.ts:67-92`

That allows creating a thread whose `parent_id` is another thread. The client sidebar and dispatcher appear to assume `parent_id` is a normal parent channel, so nested threads can disappear from the expected channel grouping or produce inconsistent gateway/filter behavior.

Recommendation: reject thread creation when the target channel is itself a thread, e.g. return 400/unsupported channel type. Add tests for both create-from-message and standalone thread creation against a thread channel.

### 3. Medium — Archived/locked thread metadata is not enforced for message writes

The PR adds `archived` and `locked` metadata plus PATCH support, but `POST /channels/:id/messages` still accepts writes into a thread regardless of those flags:

- message creation path: `packages/server/src/routes/messages.ts:63-114`
- archive/lock mutation path: `packages/server/src/routes/channels.ts` thread metadata handling

As a result, a thread can be archived and disappear from active listings, while clients can continue posting to it if they know the thread ID. `locked` currently has no behavior at all.

Recommendation: define the intended product/API semantics and enforce them consistently. If this is Discord-compatible behavior, archived/locked threads should reject normal sends or require an explicit unarchive / elevated permission path. Add tests for posting to archived and locked threads.

### 4. Medium — Thread `message_count` becomes stale after bulk-delete / clear-all

Single-message delete decrements `message_count`, but bulk delete and clear-all do not adjust thread counters:

- single delete adjusts: `packages/server/src/routes/messages.ts:213-216`
- bulk delete does not: `packages/server/src/routes/messages.ts:249-260`
- clear-all does not: `packages/server/src/routes/messages.ts:277-280`

For thread channels, these routes can remove messages while leaving `message_count` and parent thread indicators inflated.

Recommendation: when `ch.type === 11`, recompute or decrement `message_count`/`total_message_sent` appropriately for bulk-delete and clear-all. Add tests for thread message counters after those operations.

### 5. Low — Thread member leave route is missing the guild-membership guard present on the other member routes

`PUT @me`, `PUT :userId`, and `GET members` verify `repos.members.exists(thread.guild_id, user.id)`, but `DELETE @me` does not:

- `packages/server/src/routes/threads.ts:150-164`

For non-bot users, `requireBotChannelPermission` returns `true`, so a non-member with a valid token can get a 204 against a known thread ID and potentially probe existence. This is less severe than the guild-wide leak because it only removes the caller's own membership row, but it should be made consistent.

Recommendation: add the same guild-membership check used by the join/list/add routes.

## 3. Summary + Verdict

The Round 1 blockers are mostly addressed: permission checks on the named member routes are in place, tests were added, `auto_archive_duration` is validated, and the thread indicator sync path now exists.

However, fresh review found a new high-impact security gap in the guild-wide active-thread listing, plus correctness issues around nested threads, archive/lock enforcement, and stale counters. These should be fixed before merge.

**Verdict: ⚠️ Needs Changes**
