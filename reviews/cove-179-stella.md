# PR #179 Review — Stella

## Summary
The PR correctly moves the main gateway broadcast paths from global fan-out to guild-scoped fan-out, and the added dispatcher tests cover the happy-path isolation for messages, typing, and presence. However, the authorization state is captured only once at IDENTIFY and is then trusted for the life of the WebSocket session. Because Cove has live member add/remove endpoints, this leaves a security revocation gap: removed users can continue receiving events for the guild and can still emit typing events over the gateway until reconnect.

**Rate: ❌ Major Issues**

## Critical Issues

1. **Stale `session.guildIds` preserves gateway access after guild removal**  
   `GatewaySession.identify()` snapshots guild membership once into `guildIds` (`packages/server/src/ws/session.ts:42-45`), and all later event filtering trusts that cached set (`packages/server/src/ws/dispatcher.ts:104-107`). But guild membership can change at runtime through `DELETE /guilds/:guildId/members/:userId` (`packages/server/src/routes/agents.ts:122-140`), and that route does not update or disconnect affected gateway sessions. A user removed from a guild therefore continues to receive `MESSAGE_CREATE`, `MESSAGE_UPDATE`, `MESSAGE_DELETE`, `CHANNEL_UPDATE`, `TYPING_START`, and presence events for that guild until their socket reconnects. This is a security-sensitive path and defeats revocation semantics.

2. **Removed members can still send gateway typing events using stale membership**  
   `REQUEST_TYPING` validates by checking `session.guildIds.has(channel.guild_id)` (`packages/server/src/ws/index.ts:85-88`). Since that set is not refreshed after membership removal, a removed member can still broadcast typing events into the guild over WebSocket even though REST routes would reject them. Recheck current membership against `MembersRepo` or make membership mutations invalidate/update active sessions.

## Product Impact
- Guild isolation is improved for initial connection state, but not for live membership changes.
- Kicking/removing a bot or user from a guild will appear to succeed in REST while the gateway continues leaking guild activity to that connection.
- Newly added members also will not receive gateway events for the new guild until reconnect, which is less severe but will feel inconsistent with REST membership state.

## Suggestions
- Treat gateway guild membership as dynamic authorization state:
  - Add dispatcher/session APIs to update a user’s active session guild sets on member add/remove, and clear/remove the guild immediately on `DELETE /guilds/:guildId/members/:userId`.
  - Or re-check `repos.members.exists(guildId, session.user.id)` before dispatch / `REQUEST_TYPING` for sensitive gateway paths. This is simpler but adds DB reads on each event.
  - Prefer also sending a guild-removal/availability event or closing affected sessions if that matches the product model.
- Make `GatewayDispatcher` require `ChannelsRepo` instead of accepting it optionally (`packages/server/src/ws/dispatcher.ts:9`, `98-101`). Silent no-op broadcasts when the repo is missing are easy to misconfigure and hard to detect.
- Add security regression tests that use real repos/routes or an integration gateway flow:
  - connected member receives guild event;
  - member is removed;
  - same socket no longer receives message/channel/typing/presence events;
  - same socket cannot `REQUEST_TYPING` for the removed guild;
  - added member behavior is explicitly defined and tested.

## Positive Notes
- The dispatcher abstraction is a good place to centralize gateway fan-out policy.
- Existing message/update/delete/channel/typing paths now resolve a guild before broadcasting, avoiding the previous global broadcast leak for stable memberships.
- READY presence filtering by shared guild is the right direction and avoids exposing unrelated online users on initial connect.
- New tests cover the core positive isolation cases and unknown-channel no-broadcast behavior.

Verification: reviewed PR metadata/diff with `gh`; checked local line numbers on `review-pr-179`; ran `pnpm -F @cove/server test -- src/__tests__/gateway.test.ts` (Vitest reports 3 files / 107 tests passed).
