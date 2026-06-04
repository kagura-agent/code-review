# PR #179 Round 3 Review — Stella

## 1. Summary

The round-3 update materially improves the guild-scoping implementation: message/channel/typing broadcasts now resolve a guild and filter by `session.guildIds`, READY presences use a single-pass shared-guild calculation, disconnect self-broadcast is fixed, and live member add/remove now updates active sessions and emits `GUILD_CREATE`/`GUILD_DELETE`. I verified `pnpm -r exec tsc --noEmit` passes and, with Node 24, `pnpm --filter @cove/server test -- gateway.test.ts` reports 110 passing server tests. However, there is still a live authorization gap when membership is removed indirectly by deleting a user, plus one previous issue remains explicitly deferred and the new WS `REQUEST_TYPING` authorization gate is still not directly tested.

**Rating: ⚠️ Needs Changes**

## 2. Previous Issues Status

1. 🔴 **Self-broadcast on disconnect** — **Addressed.** `removeSession()` now calls `broadcastToGuildMembers(..., excludeSessionId)` before deleting the session from `sessions`, and the new gateway test asserts the dying session does not receive its own offline `PRESENCE_UPDATE` (`packages/server/src/ws/dispatcher.ts:26-43`, `packages/server/src/__tests__/gateway.test.ts:101-115`).

2. 🔴 **No `GUILD_CREATE` / `GUILD_DELETE` events to client** — **Mostly addressed.** `addGuildToUser()` emits `GUILD_CREATE` when a guild object is available, and `removeGuildFromUser()` emits `GUILD_DELETE` before removing the guild from session state (`packages/server/src/ws/dispatcher.ts:100-120`). This covers explicit member PUT/DELETE routes. See Critical Issue #1 for the remaining indirect removal path via user deletion.

3. 🟡 **DM channels silently dropped** — **Not fixed; explicitly deferred. Escalated per re-review rule.** The dispatcher still returns early when `resolveGuildForChannel()` sees `guild_id == null`, with only a TODO for #111 (`packages/server/src/ws/dispatcher.ts:123-128`) and a test that locks in non-broadcast behavior. If DM channels are impossible in the current schema, this is an acceptable scoped deferral, but as a re-review item it remains unaddressed.

4. 🟡 **O(N²) IDENTIFY presence calculation** — **Addressed for IDENTIFY.** `GatewaySession.identify()` now calls `dispatcher.getSharedGuildPresences(this.guildIds)`, which scans sessions once and de-duplicates users (`packages/server/src/ws/session.ts:42-48`, `packages/server/src/ws/dispatcher.ts:146-160`).

## 3. Critical Issues

### 1. Deleting a user leaves their active gateway sessions authorized with stale guild IDs

`DELETE /users/:id` still calls only `repos.users.delete(id)` (`packages/server/src/routes/agents.ts:66-72`), and `UsersRepo.delete()` removes that user's `guild_members` rows (`packages/server/src/repos/users.ts:64-69`). The dispatcher is never notified. Any already-connected WebSocket session for the deleted user keeps its old `session.user`, remains in `userSessions`, and retains its old `session.guildIds` set, so it can continue receiving guild-scoped events and can still send `REQUEST_TYPING` for those guild channels until the socket disconnects.

That breaks the security invariant this PR is adding: gateway visibility should follow current guild membership, not stale membership captured at IDENTIFY time. Explicit guild member removal is handled, but membership removal through user deletion/cascade is not.

**Suggested fix:** before or after deleting the user, list the user's current guild IDs and either:
- call `dispatcher.removeGuildFromUser(id, guildId)` for each guild and then close/remove that user's sessions, or
- add a dispatcher method such as `removeUser(userId)` / `closeUserSessions(userId)` that emits appropriate lifecycle events and clears session authorization state.

Add a regression test with an online user, delete that user via `DELETE /users/:id`, then assert they no longer receive `MESSAGE_CREATE` / `TYPING_START` for the former guild.

### 2. WS `REQUEST_TYPING` membership rejection is implemented but not directly tested

The new membership gate lives in `setupGateway()` (`packages/server/src/ws/index.ts:81-88`), but the new tests only exercise `GatewayDispatcher.typingStart()` and REST typing behavior. They do not open a gateway session, send opcode `REQUEST_TYPING` for a channel outside `session.guildIds`, and assert no `TYPING_START` is emitted.

Because this is a new permission/security check on a public gateway opcode, it needs a positive and negative test at the WS handler layer, not just dispatcher-level coverage.

## 4. Product Impact

- Guild-channel events are now substantially safer: non-members should no longer receive guild message/update/delete/channel/typing events through normal paths.
- Live member removal via the member DELETE route now updates active clients immediately, which avoids reconnect-only desync.
- User deletion currently remains dangerous: a deleted/kicked account can keep receiving real-time events over an existing socket until disconnect.
- DM behavior is intentionally still absent. If any future or plugin path creates `guild_id == null` channels before #111 lands, those events will be silently dropped by design in this PR.
- Separate existing gap: `GET /api/v10/guilds/:guildId/presences` still maps `dispatcher.getOnlineUserIds()` without filtering to the requested guild (`packages/server/src/app.ts:52-63`). That is REST, not gateway, but it undercuts the product story that presence visibility is guild-isolated everywhere.

## 5. Suggestions

- Send presence deltas on live guild joins/removals. After `addGuildToUser()`, existing members of the joined guild may need a `PRESENCE_UPDATE online` for the joining online user, and the joining user's sessions may need initial presences for the newly visible guild. `GUILD_CREATE` alone may not update member presence UI.
- Consider returning a boolean or count from `addGuildToUser()` / `removeGuildFromUser()` so route tests can assert that active sessions were actually updated.
- Consider exposing a guild-filtered presence helper, e.g. `getPresencesForGuild(guildId)`, and use it for `/guilds/:guildId/presences` to close the REST-side isolation gap.
- The old `getOnlineUserIds()` remains useful, but with guild isolation now in place, be careful using it directly in route code; most callers probably want a scoped view.

## 6. Positive Notes

- The round-3 fixes directly address the two red R2 gateway issues: disconnect self-broadcast and missing guild membership lifecycle events.
- Making `channelsRepo` required in the dispatcher removed the dangerous silent fallback where broadcasts could disappear because the dispatcher could not resolve a channel.
- The new `getSharedGuildPresences()` is simpler and scales better than calling `getSessionGuildIds()` once per online user during IDENTIFY.
- The gateway unit tests now cover cross-guild message isolation, live member removal, DM deferral, `GUILD_DELETE`, and the disconnect self-broadcast case.
- Verified locally: `pnpm -r exec tsc --noEmit` passed; `pnpm --filter @cove/server test -- gateway.test.ts` passed under Node 24 with 110 server tests passing. Node 22 failed only because the installed `better-sqlite3` native module was built for Node 24 (`NODE_MODULE_VERSION 137`).
