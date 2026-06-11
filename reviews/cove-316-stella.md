# PR #316 Review — Round 3 — Stella

## Summary
This round fixes a large portion of the R2 security gap: message, reaction, typing, ack, bulk-delete, clear-message, channel webhook create/list, guild channel list, gateway READY filtering, and dispatcher channel-event filtering are now mostly wired through `VIEW_CHANNEL`. However, C2 is still not complete. Several channel-scoped REST routes still allow bots without `VIEW_CHANNEL` to read or mutate hidden channel resources, and the new tests cover only a subset of the previously missed routes. I also found a fresh lifecycle regression: `CHANNEL_DELETE` is filtered after deleting the channel, so bots that previously had access will not receive the delete event.

**Rating: ❌ Major Issues**

## Critical Issues

### 1. C2 still incomplete: bots without `VIEW_CHANNEL` can read/update/delete hidden channels
**Files:** `packages/server/src/routes/channels.ts:29-36`, `packages/server/src/routes/channels.ts:74-118`, `packages/server/src/routes/channels.ts:121-134`

The direct channel routes still only verify guild membership via `requireGuildMember`; they do not call `requireBotChannelPermission` for bot users:

- `GET /channels/:id` returns hidden channel metadata, including `permission_overwrites`.
- `PATCH /channels/:id` lets a denied bot rename/update a hidden channel.
- `DELETE /channels/:id` lets a denied bot delete a hidden channel.

This is an unaddressed R2 C2 class issue, so per the escalation rule this should remain blocking/escalated. The intended default is explicit opt-in visibility for bots; these routes currently bypass that default.

**Required fix:** apply the same bot `VIEW_CHANNEL` gate used in `messages.ts`/`reactions.ts` before returning or mutating the channel. Add negative tests for denied bots on all three routes.

### 2. C2 still incomplete: webhook resource routes bypass channel visibility
**File:** `packages/server/src/routes/webhooks.ts:54-124`

The channel-scoped webhook create/list routes are now gated, but the webhook resource routes still only check guild membership:

- `GET /guilds/:guildId/webhooks` returns webhooks for every channel in the guild, including hidden channels.
- `GET /webhooks/:webhookId` lets a denied bot fetch metadata for a webhook in a hidden channel if it knows/learns the id.
- `PATCH /webhooks/:webhookId` lets a denied bot mutate a webhook in a hidden channel.
- `DELETE /webhooks/:webhookId` lets a denied bot delete a webhook in a hidden channel.

Even though tokens are stripped from list/get responses, these endpoints still leak hidden channel resources and allow mutation without `VIEW_CHANNEL`.

**Required fix:** for bot users, resolve the webhook's `channel_id` and require `VIEW_CHANNEL` before returning/updating/deleting it. For `GET /guilds/:guildId/webhooks`, filter the returned list to channels the bot can view, or return only human-visible full guild lists. Add negative tests for denied bots.

### 3. `CHANNEL_DELETE` no longer reaches bots that had access before deletion
**Files:** `packages/server/src/routes/channels.ts:128-132`, `packages/server/src/ws/dispatcher.ts:106-107`, `packages/server/src/ws/dispatcher.ts:180-188`

`DELETE /channels/:id` deletes the channel before dispatching `CHANNEL_DELETE`. Because the permission table has `ON DELETE CASCADE`, the bot's overwrite row is gone by the time `broadcastToGuildWithChannelFilter` checks `hasPermission`. Result: bots that previously had `VIEW_CHANNEL` are filtered out and never learn that the channel disappeared.

This fixes the previous leak but introduces stale client/gateway state for authorized bots.

**Required fix:** compute the authorized bot session set before deleting, dispatch before deletion, or pass a precomputed access predicate/snapshot into the dispatcher for delete events. Add both positive and negative lifecycle tests: authorized bot receives `CHANNEL_DELETE`; denied bot does not.

## Product Impact

- Hidden channels are still exposed and mutable through direct channel and webhook resource endpoints, so the core product promise (“bots without explicit opt-in cannot see the channel”) is not yet enforced consistently.
- Authorized bot clients may retain deleted channels indefinitely until reconnect because `CHANNEL_DELETE` is suppressed after permission rows cascade away.
- Gateway READY filtering appears implemented for production (`setupGateway(..., repos.permissions)` and `GatewaySession.identify` filters bot guild channels), but there is no direct negative test proving denied channels are absent from bot READY payloads.

## Suggestions

### 1. Expand negative test coverage for every channel-scoped route
The new tests are a good start, but they currently cover denied bots for message read/send/edit/delete, reaction add/remove, and typing. They do not cover several previously missed or still-risky routes, including:

- `GET /channels/:id`
- `PATCH /channels/:id`
- `DELETE /channels/:id`
- `POST /channels/:id/messages/bulk-delete`
- `DELETE /channels/:id/messages`
- `PUT /channels/:id/messages/:msgId/ack`
- `GET /channels/:channelId/messages/:messageId/reactions/:emoji`
- `GET /guilds/:guildId/channels` filtered output
- `POST /channels/:channelId/webhooks`
- `GET /channels/:channelId/webhooks`
- `GET /guilds/:guildId/webhooks`
- `GET/PATCH/DELETE /webhooks/:webhookId`
- bot READY payload excludes denied channels
- `CHANNEL_CREATE/UPDATE/DELETE` positive and negative delivery behavior

Given the review standard says security/auth paths require positive and negative tests, this should be completed before merge.

### 2. Avoid optional permission wiring on gateway paths if bot filtering is mandatory
`GatewaySession.identify` only filters READY when `permissionsRepo` is passed. Production currently passes it, but tests still have call sites that omit it. If visibility filtering is now a core invariant, consider making `permissionsRepo` required in `setupGateway`/`identify` or adding a safe default that denies bot channel visibility rather than leaking all channels.

## Positive Notes

- Message routes now consistently gate `GET`, single-message `GET`, `POST`, `PATCH`, single delete, bulk delete, clear all, ack, and typing with `VIEW_CHANNEL`.
- Reaction routes now gate add/remove/list by channel visibility.
- `GET /guilds/:guildId/channels` now filters hidden channels for bots.
- Bot READY filtering is implemented in the normal production gateway wiring.
- Dispatcher filtering now covers message, reaction, typing, and channel lifecycle event paths instead of only message events.
- The BigInt validation improvement from R2 remains in place, and the test suite passes locally: `219 passed`.
