# PR #252 Review — Stella

## 1. Summary

This PR adds the missing server-side `GUILD_MEMBER_ADD`/`GUILD_MEMBER_REMOVE` broadcasts, includes `guild_id` on `MESSAGE_DELETE`, and improves client cleanup when a channel is deleted. The direction is good and the cascade cleanup is a meaningful product improvement. I verified `pnpm -r build && pnpm -r exec tsc --noEmit && npm test` locally: all passed (152 tests). However, I would not merge as-is because the client still drops existing server-emitted guild membership events, and the new member handlers conflate guild membership with online presence.

## 2. Critical Issues

1. **`GUILD_CREATE` / `GUILD_DELETE` are still silently ignored in production**  
   - Files: `packages/server/src/ws/dispatcher.ts:116-136`, `packages/client/src/lib/gateway-dispatcher.ts:3-17`, `packages/client/src/stores/useWebSocketStore.ts:91-105`  
   - The server already emits `GUILD_CREATE` when a live user is added to a guild and `GUILD_DELETE` when removed, but the client event map and allowlist still do not include either event. In production, unknown dispatches are still dropped without warning; in dev they only warn. This leaves the affected user's connected client with stale guild state after membership changes, which is directly in the lifecycle surface this PR/linked issue is meant to fix.  
   - Recommended fix: add typed `GUILD_CREATE` / `GUILD_DELETE` entries to `GatewayEventMap` and `gatewayEvents`, then handle them at least minimally (refresh guild/channel/member state, clear cached guild id on delete, or trigger a reconnect/refetch flow). Add tests for both dispatch and client handling.

2. **`GUILD_MEMBER_ADD` / `GUILD_MEMBER_REMOVE` handlers incorrectly mutate presence**  
   - File: `packages/client/src/lib/gateway-subscriptions.ts:115-120`  
   - Being added to a guild is not the same as being online, and being removed from a guild is not a global offline transition. `routes/agents.ts:148-151` can add a user/member that has no active WebSocket session, but every client will mark that user online. Conversely, removal marks a user offline even if presence is independent of guild membership. `PRESENCE_UPDATE` / `READY.presences` are the existing source of truth for online status.  
   - Product impact: `MemberList` groups by `usePresenceStore.onlineUsers` (`packages/client/src/components/MemberList.tsx:64-65`), so adding an offline bot/member can immediately show it under Online until a later presence reset/reload.  
   - Recommended fix: do not update `usePresenceStore` from member lifecycle events. Either introduce/update a member store and let these events mutate membership, or ignore them on the client until member-list state is modeled. If the added member is currently online, the server should send/derive a proper `PRESENCE_UPDATE` or include presence separately.

## 3. Suggestions

- **Add regression coverage for the newly added event paths.** Current server tests only update `MESSAGE_DELETE`; I do not see tests asserting `guildMemberAdd()` / `guildMemberRemove()` dispatch payloads or route-level PUT/DELETE membership dispatch behavior. Client subscription tests also do not cover `CHANNEL_DELETE` cascade cleanup or the new member events. These are small and would catch the presence/membership conflation above.
- **Keep payload typings aligned with server payloads.** `GatewayDispatcher.messageDeleteBulk()` sends `{ ids, channel_id, guild_id }` (`packages/server/src/ws/dispatcher.ts:80-82`), but the client type is still `{ ids; channel_id }` (`packages/client/src/lib/gateway-dispatcher.ts:7`). It is harmless at runtime today, but it preserves API drift in the exact area this PR is cleaning up.
- **Consider deriving the allowlist from a single runtime constant.** TypeScript interfaces disappear at runtime, so `gatewayEvents` cannot literally derive from `GatewayEventMap`; still, a typed `const gatewayEvents = [...] as const satisfies Array<keyof GatewayEventMap>` would prevent future drift between the type map and allowlist.
- **Channel delete cleanup is good but should be tested with timers.** `useTypingStore.removeChannel()` correctly clears timeouts and removes IDs from `typingTimeoutIds`; a fake-timer/store test would protect against future leaks.

## 4. Positive Notes

- The server-side `MESSAGE_DELETE` `guild_id` addition is scoped through `resolveGuildForChannel()` and preserves guild isolation.
- `CHANNEL_DELETE` now clears messages, read states, unread flags, and typing indicators, which fixes the main stale-cache/memory-leak concern for deleted channels.
- `useTypingStore.removeChannel()` does the important timeout cleanup instead of only deleting the visible store entry.
- The dev-mode unknown event warning is useful for catching future Gateway drift during development.
- Local verification passed: `pnpm -r build`, `pnpm -r exec tsc --noEmit`, and `npm test` (152 tests).

## 5. Verdict

⚠️ **Needs Changes** — good foundation, but membership lifecycle events are still incomplete on the client and currently corrupt presence state in common cases.
