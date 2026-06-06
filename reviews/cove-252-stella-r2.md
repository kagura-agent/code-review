# Stella R2 Review — cove#252

PR: kagura-agent/cove#252 — `feat: emit missing Gateway events and add client cascade cleanup`

## R1 Status

1. ✅ **BLOCKING: `GUILD_MEMBER_ADD/REMOVE` incorrectly mutates global presence**
   - Fixed. The member event handlers no longer call `usePresenceStore.setOnline()` / `setOffline()`.
   - `PRESENCE_UPDATE` remains the sole source of online/offline state.

2. ✅ **BLOCKING: `GUILD_CREATE` / `GUILD_DELETE` silently dropped by client**
   - Addressed enough for this PR. Both events were added to `GatewayEventMap`, `gatewayEvents`, and `setupGatewaySubscriptions()`.
   - Current handlers are intentional no-op placeholders pending GuildStore work (#228), but the events now traverse the client dispatcher path instead of being unknown/dropped.

3. ❌ **Non-blocking: No tests for new event paths**
   - Still mostly unresolved.
   - Existing `MESSAGE_DELETE` assertion was updated for `guild_id`, but there are still no direct tests for:
     - `guildMemberAdd()` / `guildMemberRemove()` dispatcher payloads and guild scoping
     - client `CHANNEL_DELETE` cascade cleanup
     - client member/guild event subscription paths

4. ❌ **Non-blocking: `MESSAGE_DELETE_BULK` client type drift**
   - Still present. Server emits `{ ids, channel_id, guild_id }`, but client `GatewayEventMap.MESSAGE_DELETE_BULK` remains `{ ids; channel_id }`.
   - Runtime impact is low because the client currently ignores `guild_id`, but the type drift remains.

## New Issues / Regressions

No new blocking regressions found in R2.

Notes:
- `GUILD_CREATE` type is narrower than the server payload, but structurally safe for current use because extra fields are allowed and the handler is a placeholder.
- The `GUILD_CREATE` / `GUILD_DELETE` client handling is still not functionally complete; that matches the explicit GuildStore deferral in comments.

## Verification

Ran locally on PR branch:

```bash
pnpm -F @cove/server test -- --runInBand
pnpm -F @cove/client build
```

Results:
- ✅ Server tests: 6 files / 152 tests passed
- ✅ Client production build passed

## Verdict

✅ **Approve / Ready to merge**, with non-blocking follow-ups.

The two R1 blocking concerns are fixed. Remaining items are test coverage and type polish, both suitable as follow-up work rather than merge blockers.
