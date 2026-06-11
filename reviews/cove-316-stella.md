# PR #316 Round 2 Review — Stella

## Summary
This PR adds channel permission overwrites and the Round 2 fixes do address part of the Round 1 feedback: bots can no longer call the permission overwrite routes, list/send message routes are gated, dispatcher filtering was expanded for message/typing/reaction events, and malformed non-BigInt `allow`/`deny` values are rejected on the permission route. However, the core default-deny guarantee is still incomplete. Several channel-bound REST routes and channel gateway events still bypass `VIEW_CHANNEL`, so denied bots can still learn about hidden channels and interact with messages if they know IDs. Because these are repeated Round 1 access-control findings, I’m escalating them as blocking.

**Rating: ❌ Major Issues**

## Critical Issues

### 1. [Escalated R1 C2] `VIEW_CHANNEL` is still missing from many channel-bound REST endpoints
The fixes added `requireBotChannelPermission` to channel list, message list/send, and webhook create/list, but most other channel-scoped routes still only check guild membership. A bot with no overwrite can still access or mutate resources in a channel it should not be able to see.

Examples:
- `packages/server/src/routes/channels.ts:29-36` — `GET /channels/:id` returns the channel object, including metadata/overwrites, without checking `VIEW_CHANNEL`.
- `packages/server/src/routes/channels.ts:74-118` and `121-134` — denied bots can patch/delete channels as guild members.
- `packages/server/src/routes/messages.ts:32-45` — `GET /channels/:id/messages/:msgId` returns a specific message if the bot knows/guesses the ID.
- `packages/server/src/routes/messages.ts:97-160`, `164-194`, `198-211`, `214-230`, `233-243` — edit/delete/bulk-delete/clear/ack/typing all bypass the new permission check.
- `packages/server/src/routes/reactions.ts:11-91` — add/remove/list reactions all bypass the new permission check.

This directly violates the PR’s stated default of “no overwrites = bot cannot see the channel.” Please centralize the channel access check so every route that takes a channel id either rejects denied bots with `403 Missing Permissions` or intentionally documents a human/admin-only bypass.

### 2. [Escalated R1 C4] Dispatcher filtering is still incomplete for channel events
`MESSAGE_*`, `TYPING_START`, and reaction events now use `broadcastToGuildWithChannelFilter`, but channel lifecycle events still go through the unfiltered guild broadcast:

- `packages/server/src/ws/dispatcher.ts:98-107` — `CHANNEL_CREATE`, `CHANNEL_UPDATE`, and `CHANNEL_DELETE` are sent to every bot session in the guild.

For denied bots this leaks hidden channel IDs, names/topics on create/update, and deletion activity. `CHANNEL_UPDATE` is especially sensitive now that channel responses include permission overwrites. These events need the same `VIEW_CHANNEL` filtering semantics as message events, with a deliberate policy for newly-created channels that have no overwrite yet.

### 3. [Escalated R1 C3] Negative auth tests only cover the newly-fixed happy subset, not the remaining protected surface
The added tests are a good start, but they only assert denied bots cannot list/send messages and cannot manage overwrites. They would not catch the leaks above. Given this PR is implementing access control, each channel-bound API/event path needs negative tests for a bot without `VIEW_CHANNEL`, especially:

- `GET /channels/:id`
- message get/edit/delete/bulk-delete/clear/ack/typing
- reaction add/remove/list
- webhook create/list if intended to stay gated
- `CHANNEL_CREATE`, `CHANNEL_UPDATE`, `CHANNEL_DELETE` dispatcher delivery

This is blocking under the review standard because the missing auth coverage allowed repeated Round 1 issues to remain in Round 2.

## Product Impact
Denied bots will still be able to discover and interact with channels that the UI/admin has not granted them. That undermines the feature’s main user-facing promise: using the Permissions tab to control which bots can see a channel. In practice, bot authors could still read specific messages by ID, mutate channel/message state via REST, and observe hidden-channel metadata through gateway events.

## Suggestions

- `packages/server/src/routes/permissions.ts:31-38` now catches non-BigInt strings, which fixes the crash class, but bitfields should probably be validated as non-negative decimal strings, with tests for values like `"abc"`, `""`, and `"-1"`. Discord permission bitfields are not signed integers, and accepting negative values can make future `hasPermission` checks behave unexpectedly.
- Consider validating overwrite targets before upsert: `type: 1` should reference an existing guild member/user, and `type: 0` should reference an existing role once roles exist. Otherwise the API can store inert or confusing overwrites.
- To avoid future missed gates, consider a helper that resolves `(channel, user)` and enforces bot visibility in one call, rather than repeating `requireGuildMember` plus optional permission checks route-by-route.

## Positive Notes

- The previous self-grant path for bots is closed: permission routes now reject `user.bot` with `50013`.
- Channel list and message list/send now enforce `VIEW_CHANNEL`, matching the default-deny model for the most common read/write paths.
- Dispatcher filtering was meaningfully expanded for message, typing, and reaction events.
- Route-level parsing now prevents invalid non-integer `allow`/`deny` values from crashing `BigInt()`.
- I ran the test suite entrypoint used by the workspace (`pnpm test -- --run packages/server/src/__tests__/permissions.test.ts`); it completed successfully with the server suite reporting 214 passing tests, though the workspace script ran broader tests than just the single file.
