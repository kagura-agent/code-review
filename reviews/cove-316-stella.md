# Review: kagura-agent/cove PR #316 — feat: channel permission overwrites

## Summary

This PR adds channel permission overwrite storage, exposes PUT/DELETE APIs, surfaces per-bot visibility toggles in Channel Settings, and filters some gateway message events for bot sessions. The migration/build/test path is healthy (`pnpm -r test`: 210 passed; `pnpm -r build`: passed), but the access-control model is not ready yet: denied bots can still discover/read/write hidden channels through REST/READY, can self-grant visibility, and malformed overwrite bitfields can crash permission evaluation. **Rating: ❌ Major Issues**

## Critical Issues

1. **Default-deny visibility is only applied to a subset of gateway message events; REST and READY still expose hidden channels/messages.**  
   - `packages/server/src/ws/session.ts:48-51` sends every `channelsRepo.list(g.id)` channel in READY, including `permission_overwrites`, to every guild member/bot. A denied bot still learns the hidden channel exists immediately on connect.  
   - `packages/server/src/routes/channels.ts:11-26` and `packages/server/src/routes/messages.ts:11-42` only require guild membership, so a denied bot can still list channels, fetch a hidden channel, and read its message history over REST.  
   - `packages/server/src/routes/messages.ts:45-88`, `208-237`, and related reaction/delete routes similarly do not check `VIEW_CHANNEL`, so denied bots can post messages, ack messages, type, react, and perform message operations in channels they should not see.  
   - `packages/server/src/ws/dispatcher.ts:94-115` and `220-230` still broadcast `MESSAGE_DELETE_BULK`, `TYPING_START`, and reaction events to all guild bot sessions, leaking hidden channel IDs/message IDs/activity even though single-message create/update/delete events are filtered at `dispatcher.ts:76-91`.

   **Fix:** centralize a `canViewChannel(user, channelId)` check and apply it consistently to bot REST reads/writes and all channel-scoped gateway events. For READY/channel list, either omit channels lacking `VIEW_CHANNEL` for bots or include only channels the bot can view. Add positive and negative tests for each API/event class.

2. **Any guild member, including a denied bot, can create/delete overwrites and grant itself `VIEW_CHANNEL`.**  
   - `packages/server/src/routes/permissions.ts:13-27` authorizes overwrite mutation with only `requireGuildMember(...)`. A bot token that is a guild member can call `PUT /channels/:channelId/permissions/:itsOwnId` with `allow=VIEW_CHANNEL` and bypass the default-deny model.  
   - `permissions.ts:31-39` has the same issue for deletion; any guild member can remove another bot's overwrite.

   **Fix:** restrict permission overwrite management to a real administrator/owner/MANAGE_CHANNELS-equivalent path. If role permissions are not available yet, at minimum block bot users from these routes and require the guild owner or an explicit server-side admin concept. Add negative tests proving denied bots and ordinary members cannot mutate overwrites.

3. **`allow`/`deny` bitfields are accepted as arbitrary strings and later parsed with `BigInt`, enabling runtime crashes.**  
   - `packages/server/src/routes/permissions.ts:23-27` only checks that `allow` and `deny` are strings before persisting them. Strings such as `"not-a-number"`, `""`, `"1.5"`, or enormous values are accepted.  
   - `packages/server/src/repos/permissions.ts:61-62` calls `BigInt(row.allow)` / `BigInt(row.deny)` during dispatch filtering; malformed stored values will throw inside `messageCreate`/`messageUpdate`/`messageDelete` and can break gateway delivery.  
   - The client also does `BigInt(o.allow)` while rendering (`packages/client/src/components/ChannelSettings.tsx:327-329`), so malformed data can crash the Permissions tab.

   **Fix:** validate route input as canonical non-negative integer bitfield strings, optionally bounded to the supported Discord permission width; reject invalid JSON/body values before DB writes. Consider hardening `hasPermission` defensively so one bad row cannot crash dispatch. Add tests for invalid `allow`/`deny` values.

## Product Impact

- The UI suggests “Bots without access will not receive messages from this channel,” but as implemented a denied bot can still get the channel in READY/channel list, fetch message history, and interact with the channel over REST. That is a substantial mismatch for bot visibility/privacy and could lead users to believe a bot is isolated when it is not.
- Self-granting means the main security control is bypassable by the exact actor it is meant to restrict.
- Partial event filtering can create inconsistent bot behavior: a bot may miss `MESSAGE_CREATE` but still receive typing/reaction/bulk-delete events for the same hidden channel.

## Suggestions

- **Add target validation/foreign keys.** `channel_permission_overwrites.target_id` currently has no FK to `users`/roles and the route does not verify that `targetId` exists or is a member of the channel's guild. The UI only sends current bot members, but the API can store stale or nonsensical overwrites. Validate member targets for `type: 1`; defer or explicitly reject `type: 0` until role support exists.
- **Return or dispatch overwrite changes.** After PUT/DELETE, connected clients do not receive a `CHANNEL_UPDATE`, so multiple settings tabs/sessions can show stale permission state until a refresh/reopen.
- **Avoid N+1 overwrite loading for guild channel lists.** `ChannelsRepo.list()` now calls `permissionsRepo.listByChannel()` once per channel. That is probably fine for small guilds, but a batched query by guild/channel IDs would scale better and avoid repeated prepared statement execution.
- **Test REST authorization, not only dispatcher filtering.** The new tests cover CRUD and selected dispatch behavior, but this is an access-control feature; add explicit positive/negative tests for channel list, channel get, message list/get/post, typing/reactions, READY payload filtering, and overwrite mutation authorization.

## Positive Notes

- The schema/migration shape is simple and compatible with Discord-style overwrite objects, and channel delete cascade is covered by tests.
- The UI is small and understandable: per-bot switches map directly to a member overwrite for `VIEW_CHANNEL`.
- The dispatcher filter for `MESSAGE_CREATE`, `MESSAGE_UPDATE`, and single `MESSAGE_DELETE` is clear and covered by positive/negative tests.
- The existing suite passes, and the full workspace build succeeds after the changes.
