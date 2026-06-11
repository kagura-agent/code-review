# PR #316 Review — channel permission overwrites (bot visibility)
Reviewer: 🌠 Nova

## Summary
Adds a Discord-compatible `channel_permission_overwrites` table, a `PermissionsRepo`, a `PUT/DELETE /channels/:channelId/permissions/:targetId` route pair, channel response enrichment, a bot-toggle UI, and a dispatcher hook that drops realtime message events to bot sessions lacking `VIEW_CHANNEL`. The plumbing is clean and the tests for happy-path filtering exist, but as an enforcement mechanism the MVP has gaps that defeat the stated "default deny / explicit opt-in" guarantee: the route has no authorization check, and message REST/secondary realtime events are not gated. Verdict: ⚠️ Needs Changes.

## Critical Issues

### 1. Permission route has no admin authorization — any guild member (including bots) can grant themselves access
`packages/server/src/routes/permissions.ts:11-21,32-40`. Both `PUT` and `DELETE` only call `requireGuildMember(repos, channelId, userId)`. A bot that is a member of the guild can therefore call
```
PUT /api/v1/channels/<channelId>/permissions/<its-own-id>
{ "type": 1, "allow": PermissionFlags.VIEW_CHANNEL, "deny": "0" }
```
and bypass the entire opt-in gate. The PR's marketed invariant ("default deny — bots need explicit authorization") is not enforced server-side. This MVP needs at minimum a check that the caller is a human (not bot) or has a MANAGE_CHANNELS/admin equivalent. Without that, the rest of the work is cosmetic.

There is also no test for an unauthorized but-in-guild caller getting 403. The 404 test (`non-member gets 404`) only covers the non-member case.

### 2. Dispatcher only filters MESSAGE_CREATE/UPDATE/DELETE; other channel events leak
`packages/server/src/ws/dispatcher.ts:78-95`. The new `broadcastToGuildWithChannelFilter` is wired into `messageCreate/Update/Delete` only. Everything else continues to use `broadcastToGuild`, so a bot without `VIEW_CHANNEL` still receives:
- `MESSAGE_DELETE_BULK` for that channel (`messageDeleteBulk`, line ~95).
- `TYPING_START` for that channel (`typingStart`, line ~110).
- `MESSAGE_REACTION_ADD/REMOVE` (whatever the reactions dispatcher emits — not gated here).
- `CHANNEL_CREATE/UPDATE/DELETE` for hidden channels (lines 98-108).

So a denied bot still learns about the channel's existence, edits, typing, and bulk deletes. For the "bot visibility" product goal this is a real leak, not a nit. Route all per-channel events through a single helper.

### 3. REST endpoints are not gated by VIEW_CHANNEL
The filter is only on the WS dispatcher path. A bot without `VIEW_CHANNEL` can still `GET /channels/:id`, `GET /channels/:id/messages`, `POST /channels/:id/messages`, `PUT reactions`, `POST webhooks`, etc., because all those routes only check `requireGuildMember`. That means:
- A bot denied at the channel level can still **read full message history** via REST.
- A bot denied at the channel level can still **post messages** to the channel.

If the product intent is "bots without access will not receive messages from this channel" in any sense beyond pull-vs-push parity, REST reads on a `VIEW_CHANNEL`-denied bot must 404/403 as well. At minimum, document this MVP scope explicitly in the PR/issue, and add a TODO+test for REST filtering. As-is the security story is partial-and-misleading.

### 4. `hasPermission` parses untrusted bigints without validation
`packages/server/src/routes/permissions.ts:18-20` only checks that `allow`/`deny` are strings. `packages/server/src/repos/permissions.ts:56-63` then runs `BigInt(row.allow)` on the dispatcher hot path. A client that PUTs `{"type":1,"allow":"abc","deny":"0"}` stores garbage and the very next `messageCreate` for that channel throws `SyntaxError: Cannot convert abc to a BigInt` from inside `broadcastToGuildWithChannelFilter`. Depending on the WS write loop, that can blackhole event delivery for the whole guild on that broadcast.

Validate `allow`/`deny` as `/^\d+$/`, reasonable length cap (e.g. ≤ 40 chars), and reject otherwise with 400. Also consider try/catch in `hasPermission` to fail closed.

### 5. Dispatcher fails open when `permissionsRepo` is unset
`packages/server/src/ws/dispatcher.ts:81-88`: if `this.permissionsRepo` is null, the bot check is skipped and the bot receives everything. The wiring is done in `src/index.ts:42` but `createApp` does not wire it (the test file's `TestDispatcher` re-wires it manually, line ~17-22 of `permissions.test.ts`). Any future consumer who instantiates `GatewayDispatcher` via `createApp` and forgets the extra call silently disables the gate. Either:
- Inject `PermissionsRepo` via the constructor (preferred); or
- Fail closed: `if (session.user?.bot && !this.permissionsRepo) continue;`.

## Product Impact
- The PR description claims "Default: no overwrites = bot cannot see the channel (explicit opt-in required)." Given issues #1–#3, this is only true for three specific event types on the WS path. Either tighten the implementation or rewrite the description so operators don't deploy under a false sense of isolation.
- UX side: toggling the switch issues an authoritative-looking action that any bot can self-grant. From the admin's POV the UI implies governance that the server doesn't actually enforce.
- Initial Gateway READY payload and `GET /guilds/:id/channels` still expose all channels to all bots; only the message stream is partially throttled. If "bot visibility" should hide the channel from sidebar/READY too, this is a separate, larger workstream worth filing.

## Suggestions

- `packages/server/src/repos/permissions.ts` — `target_type` is stored but `hasPermission` doesn't distinguish role vs member; PK `(channel_id, target_id)` will collide if a role and member share an id. With snowflakes unlikely in practice; tighten when roles ship by keying on `(channel_id, target_type, target_id)`.
- `packages/server/src/routes/permissions.ts:23` — `body.type !== 0 && body.type !== 1` accepts truthy-but-non-integer values like `0.5`? `JSON.stringify` won't, but tighter would be `!Number.isInteger(body.type)`.
- `packages/server/src/repos/channels.ts:17-22` — `enrichOverwrites` fires an extra query per channel in `list()`; with N channels that's N+1. A single `WHERE channel_id IN (...)` grouped query is trivial and worth doing before this becomes the hot path for the channel sidebar.
- `packages/client/src/components/ChannelSettings.tsx:97-107` — Permissions tab re-fetches the full member list and full channel list every time the tab opens or `channelId` changes; you only need the one channel. Either reuse `useChannelStore` cache or add a `GET /channels/:id/permissions` endpoint.
- `packages/client/src/components/ChannelSettings.tsx:139-155` — `handleToggleBotPermission` updates state from the response synthesized client-side. On a 403 (after issue #1 is fixed) the UI will not roll back; surface the error in the modal instead of just `console.error`.
- `packages/client/src/components/ChannelSettings.tsx:147` — uses `(BigInt(o.allow) & BigInt(PermissionFlags.VIEW_CHANNEL)) !== 0n`; perfectly fine, just note the entire `PermissionFlags` is shipped as strings to keep bigint cross-platform — leave a comment in `types.ts` so future contributors don't "fix" it to numbers.
- `packages/shared/src/types.ts` — `PermissionOverwrite.type` could be a discriminated `0 | 1` literal for type-safety in the client and route validators.
- Tests: the dispatcher tests bypass HTTP for session setup and tag `(session as any).identified = true`. Once issue #1 is addressed, add an HTTP-level test that asserts a bot caller without permission receives 403 from `PUT /channels/:id/permissions/:targetId` — that's the security-critical path and is currently untested.
- `packages/server/src/__tests__/migration.test.ts` lines 174,200,322 still carry stale comments referring to "user_version should be 8" and "Version should be 3" while asserting `9`. Refresh the comments to avoid future confusion.

## Positive Notes
- Migration is additive, uses `IF NOT EXISTS`, and adds `FOREIGN KEY ... ON DELETE CASCADE`. The CASCADE behaviour is explicitly covered by the "permissions are removed when channel is deleted" test — good.
- `PermissionsRepo.upsert` uses an `ON CONFLICT … DO UPDATE` clause keyed on the PK; clean and idempotent.
- Bitfield as string + `(1n << 10n).toString()` is the right call for JSON safety, matches Discord.
- Bot-vs-human branching in `broadcastToGuildWithChannelFilter` correctly bypasses humans — humans don't get accidentally hidden.
- New `permissions.test.ts` covers CRUD, channel inclusion (single + list), CASCADE delete, validation 400, non-member 404, and bot+human dispatch paths. Good coverage of the implemented surface; the gaps above are about what's *not* implemented.
- UI keeps the Permissions tab feature-flagged off until ready, then flips a single boolean — minimal blast radius.

## Verdict
⚠️ **Needs Changes** — the PR's headline guarantee ("default deny / explicit opt-in for bot visibility") is not enforced because the route lacks an admin check (#1), only a subset of channel events is filtered (#2), and REST reads/writes are unfiltered (#3). #4 is a small but real DoS/exception vector on the realtime path. Once #1 and #4 are fixed and #2/#3 are either implemented or explicitly scoped-out in the PR description, this is mergeable.
