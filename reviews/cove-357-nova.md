# PR #357 Review — Discord-style Message Threads

**Reviewer:** 🌠 Nova
**Verdict:** ⚠️ Needs Changes

## Summary

A sizeable, well-structured feature drop (~1k LOC across 25 files) implementing Discord-compatible PUBLIC_THREAD (type 11) channels: v15 migration, `ThreadsRepo`, REST surface (`/channels/:id/messages/:mid/threads`, `/channels/:id/threads`, `/threads/active`, `thread-members/*`), gateway events, and a working React panel + Zustand store. The shape closely mirrors Discord's API which makes the client integration mostly mechanical. The core flow (create from message → indicator → panel → reopen) is sound. Main concerns are **bot permission gaps on thread member routes**, **zero new tests for a security-touching surface**, and a couple of dispatcher/state-sync edge cases.

## Critical Issues (blocking)

1. **Missing `requireBotChannelPermission` on thread-member routes** — `packages/server/src/routes/threads.ts`:
   - `PUT /channels/:threadId/thread-members/@me` (join)
   - `DELETE /channels/:threadId/thread-members/@me` (leave — also missing `members.exists` guard)
   - `PUT /channels/:threadId/thread-members/:userId` (add member)
   - `GET /channels/:threadId/thread-members` (list members)

   These only call `repos.members.exists(thread.guild_id, user.id)`. For bot/agent users, channel access in Cove is gated by `permission_overwrites` (`requireBotChannelPermission`). A bot that has no `VIEW_CHANNEL` on the parent text channel can still join, list members of, and add others to threads under that channel — bypassing the parent's overwrite. Permission inheritance was correctly added to `helpers.ts requireBotChannelPermission` (parent_id fallback for type=11), but it must actually be **called** on these routes. The two create-thread routes do call it correctly; the member routes are inconsistent.

2. **No tests added for a security/auth-sensitive surface.** Per review standard, auth/permission paths without tests = Critical. The PR adds:
   - 7 new server routes (none tested)
   - New repo with state mutations (`addMember`/`removeMember`/`incrementMessageCount`/`setArchived`/`setLocked`) — none tested
   - Migration v15 — only version-bump assertions in `migration.test.ts`, no column/table existence checks

   At minimum: a thread-routes integration test asserting (a) bot without VIEW_CHANNEL on parent gets 403 on create/join/list, (b) duplicate thread-from-message returns 400 (code 160004), (c) message_count increments on send and decrements on delete, (d) auto-add owner as member on create.

## Product Impact

- **READY-time N+1 fetch** — `gateway-subscriptions.ts` iterates every channel in every guild and issues `fetchActiveThreads(ch.id)` per channel. For users in guilds with many channels this fires N HTTP requests on every reconnect. A `/guilds/:guildId/threads/active` endpoint already exists in this PR — switch the client to that single call per guild.
- **Sidebar always shows all threads under a channel** — `Sidebar.tsx` lists every active thread under each parent channel unconditionally, with no collapse/limit. In a busy guild this will overrun the sidebar. Consider collapsing by default or capping at N with "show more".
- **PATCH archived/locked on non-thread or thread without metadata silently falls through** — `routes/channels.ts`: if `channel.type === 11` but `setArchived/setLocked` return `null` (no `thread_metadata` row), the code falls through to the regular channel update branch and returns 200 with the unchanged channel. Better: 400/409 when archive/lock target is invalid.
- **`THREAD_MEMBER_UPDATE` only goes to the joining user** — `dispatcher.ts threadMemberUpdate` calls `sendToUser(userId, ...)`. Other clients viewing the thread never see `member_count` change because no `THREAD_UPDATE` is emitted on join/leave. Member-count badges will be stale until next refresh.

## Suggestions (non-blocking)

- **`routes/threads.ts` (create-from-message)**: no validation on `auto_archive_duration`. Discord accepts only `{60, 1440, 4320, 10080}`. At minimum require a positive finite number; otherwise a client can write arbitrary values into `thread_metadata` JSON.
- **`repos/threads.ts createThread`**: `addMember(id, ownerId)` happens after the `INSERT` that sets `member_count=0`, then `addMember` increments to 1. Correct end-state, but two writes where one would do; consider seeding `member_count=1` in the INSERT and inserting the row directly to avoid the extra UPDATE.
- **`repos/threads.ts setArchived/setLocked`**: read-modify-write of `thread_metadata` is not wrapped in a transaction. Concurrent archive+lock could clobber. better-sqlite3 is synchronous per-process so this is theoretical, but if you ever multi-process the server, this becomes a real race. Wrap in `db.transaction(...)`.
- **`routes/channels.ts` PATCH**: when both `archived` and `locked` are sent, `setArchived` runs, then `setLocked` re-reads and overwrites. Final state is correct because `setLocked` re-parses fresh JSON, but the two separate UPDATE statements should be one. Same transactional point.
- **`useThreadStore.setThreads` callsite**: subscriptions only call `setThreads` when `threads.length > 0` — so after the last thread in a channel is deleted, the store keeps a stale empty list never replaced by the empty response. Always set (or initialize as `[]`).
- **`MessageContextMenu.handleCreateThread`** truncates name to 40 chars while server allows 100. Either bump client to 100 or document the 40-char convention. The same name is also used as the thread's `name` field with no length warning to the user.
- **`useThreadStore.ts updateThread/addThread`**: the `thread.parent_id!` non-null assertions appear after `if (!thread.parent_id) return`. That's safe but lint-noisy; restructure to narrow without `!`.
- **`ThreadIndicator.tsx`**: `channelId` prop accepted in `Props` but never used inside the component. Remove or use.
- **`dispatcher.ts threadMemberUpdate`**: `guildId` parameter accepted but unused. Either drop the param or use it (e.g., to also notify guild presence subscribers).
- **`Sidebar.tsx`**: `parentChannels = channels.filter((ch) => ch.type !== 11)` runs every render of every Sidebar instance. Memoize, or do it at the store layer.
- **`app/App.tsx`**: resize drag handler attaches `mousemove/mouseup` to `document` directly without using the React-managed cleanup; if the component unmounts mid-drag, listeners can leak. Wrap in a useEffect-managed pattern or check unmount.
- **`gateway-dispatcher.ts THREAD_DELETE` payload shape**: `type: 11` hard-coded — fine for now since only PUBLIC_THREAD exists, but when private threads (type 12) land this becomes a footgun. Source from the thread object.
- **`repos/threads.ts incrementMessageCount`**: Discord's semantics are that the initial / "first message" is not counted in `message_count`. Current impl counts every server message including the first one in a standalone thread, and excludes only the parent for thread-from-message. Minor compat nit if you care about Discord parity.

## Positive Notes

- **Permission inheritance in `helpers.ts`** — adding the parent-channel fallback in `requireBotChannelPermission` is the right design choice; just needs to be invoked everywhere.
- **`broadcastToGuildWithChannelFilter` parent-id lookup** is correctly placed *before* the loop, not inside it — clean perf-aware change.
- **Migration v15 is purely additive** — all new columns nullable or defaulted, FK with `ON DELETE CASCADE` correctly set. Re-runnable via `CREATE TABLE IF NOT EXISTS` for `thread_members`. Safe rollforward.
- **Type 11 / parent-id model** mirrors Discord exactly, which keeps the door open for clients that already speak Discord protocol.
- **Thread channels reuse `MessageList` / `MessageInput` / `ReplyBar`** — minimal new UI surface, low maintenance cost.
- **`addMember` uses `INSERT OR IGNORE` with `changes`-guarded counter update** — idempotent and correct.
- **Auto-enrichment of parent messages with thread indicator** in `messages.ts` list+get keeps the wire format Discord-compatible without client-side joining.
- **PR scope discipline** — explicit "out of scope: private threads, auto-archive cron, subagent binding" is exactly the right way to ship this.

---

**Bottom line:** Land after (1) wiring `requireBotChannelPermission` into the four thread-member routes and (2) adding at least a thin integration test for the permission boundary + duplicate-thread case. Everything else is polish.
