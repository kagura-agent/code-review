# PR #179 Round 2 Review — Stella

## 1. Summary

Rate: ⚠️ Needs Changes

Round 2 is substantially improved. The security-critical stale-membership problem from R1 is now addressed for the existing membership mutation endpoints: active sessions are updated on member add/remove, `REQUEST_TYPING` re-checks channel guild membership, and `channelsRepo` is now required instead of silently suppressing broadcasts.

I found no new blocker in the implemented guild-scoped event path. Server tests and TypeScript build pass locally:

- `pnpm -F @cove/server test` → 108 passed
- `pnpm -F @cove/server build` → `tsc` passed

However, the R1 DM/non-guild channel issue was not actually fixed; it was converted into a TODO. Under the escalation rule, that remains an unaddressed prior issue. If this PR is intentionally guild-only until #111 lands, the code should make that contract explicit in behavior/tests rather than silently dropping `guild_id == null` dispatches.

## 2. Previous Issues Status

1. 🔴 **Stale `guildIds` after membership changes** — ✅ Addressed for current API paths
   - `GatewayDispatcher.addGuildToUser()` / `removeGuildFromUser()` update every active session for the affected user.
   - `agentRoutes` wires these hooks into `PUT /guilds/:guildId/members/:userId` and `DELETE /guilds/:guildId/members/:userId`.
   - Added test covers join → receive guild events, kick → stop receiving guild events.
   - `REQUEST_TYPING` now resolves the channel and rejects when `session.guildIds` lacks the channel guild.
   - Caveat: this stays correct only if all runtime membership changes go through these routes/hooks.

2. 🟡 **Optional `channelsRepo` caused silent broadcast suppression** — ✅ Addressed
   - `GatewayDispatcher` now requires `ChannelsRepo` in the constructor.
   - Production construction passes `repos.channels` from both app and gateway setup.
   - This removes the `if (!channelsRepo) return null` fallback from R1.

3. 🟡 **DM/non-guild channels undeliverable** — ❌ Not fixed; escalated
   - Current `resolveGuildForChannel()` still returns `channel?.guild_id ?? null`; any future channel with `guild_id == null` will still be silently dropped for `MESSAGE_CREATE`, `MESSAGE_UPDATE`, and `MESSAGE_DELETE`.
   - The new TODO references #111, but there is no functional DM recipient path and no failing/guardrail test documenting the current limitation.
   - Because this was a prior R1 issue and Round 2 did not implement it, severity should not be downgraded. I would treat it as a required follow-up before claiming the gateway dispatch layer is generally channel-safe beyond guild channels.

## 3. Critical Issues

### Escalated: DM/non-guild dispatch still silently drops events

`GatewayDispatcher.resolveGuildForChannel()` still only supports guild channels:

```ts
const channel = this.channelsRepo.getById(channelId);
return channel?.guild_id ?? null;
```

All message dispatch methods return early when this is null:

```ts
const guildId = this.resolveGuildForChannel(message.channel_id);
if (!guildId) return;
```

Today the schema/shared types still model `guild_id` as non-null, so this is not breaking current guild-channel behavior. But the PR description frames gateway scoping as Discord parity, and #111 explicitly requires DM gateway delivery to both participants. With this implementation, adding DM channels later will produce successful REST message creation with no gateway delivery unless this dispatcher path is revisited.

Minimum acceptable handling for this PR:

- either explicitly scope PR #179 to guild channels and add a test/comment at the dispatch boundary that non-guild channels are intentionally unsupported until #111,
- or add a `broadcastToRecipients`/DM recipient abstraction now and cover it with tests.

## 4. Product Impact

- ✅ Guild isolation is now much safer: kicked users stop receiving new guild events without reconnecting.
- ✅ Typing events no longer bypass guild membership after a user is removed.
- ✅ Missing dispatcher channel resolution dependency should now fail at construction/typecheck time instead of silently dropping all events.
- ⚠️ DM/private-message work remains at risk: if #111 is implemented later without changing this dispatcher, users will be able to create/read DM messages via REST but connected clients will not receive live gateway events.
- ⚠️ Membership removal currently changes visibility but does not emit a member-removal/presence cleanup event to remaining guild clients. That may be acceptable because member gateway events are not implemented here, but clients could show stale presence/member UI until refresh.

## 5. Suggestions

1. Add an explicit test for the current non-guild behavior.
   - If DMs are out of scope, assert that dispatcher does not support `guild_id == null` yet and reference #111.
   - This prevents future PRs from assuming DM gateway delivery already works.

2. Prefer a channel dispatch strategy before #111 lands:
   - `guild_id != null` → `broadcastToGuild(guildId, ...)`
   - `guild_id == null` → `broadcastToChannelRecipients(channelId, ...)`

3. Add a route-level or repo-level note that all membership mutations must call dispatcher membership hooks. The fix is correct for current routes, but easy to bypass if future code calls `repos.members.add/remove` directly.

4. Consider emitting a future `GUILD_MEMBER_REMOVE` or presence cleanup event when `removeGuildFromUser()` removes the last shared guild between users. Not required for this PR, but it would avoid stale online/member UI.

5. Minor test hardening: in `gateway.test.ts`, add a direct `REQUEST_TYPING` integration-style test through `setupGateway` or a small handler seam. The dispatcher test covers broadcast scoping, but the R1 bypass was specifically the incoming request path.

## 6. Positive Notes

- The R1 critical stale-session bug was addressed in the right place: updating active sessions avoids waiting for reconnects.
- Making `channelsRepo` required is the correct fail-fast design.
- `removeSession()` broadcasting offline before deleting the session preserves guild context for scoped offline presence.
- New gateway tests cover message create/update/delete, typing, presence, cross-guild isolation, and live membership updates.
- The implementation is small and readable; the current guild-channel path is easy to reason about.
