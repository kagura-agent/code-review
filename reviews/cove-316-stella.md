# PR #316 Re-review — Stella (Round 5)

## Summary
Round 5 addresses the only R4 blocker: the missing negative regression tests for channel-route `VIEW_CHANNEL` enforcement. I pulled the current PR diff, re-checked the implementation and tests fresh, and verified the full suite now passes (`223 passed`). The four new tests cover the exact routes that regressed in earlier rounds. No remaining blocking issues found.

## Critical Issues
None.

## Verification
- ✅ **New channel-route negative tests exist** in `packages/server/src/__tests__/permissions.test.ts:534-568`:
  - `denied bot cannot GET /channels/:id` → expects `403`
  - `denied bot cannot PATCH /channels/:id` → expects `403`
  - `denied bot cannot DELETE /channels/:id` → expects `403`
  - `denied bot gets filtered guild channel list` → `GET /guilds/:guildId/channels` returns `200` and excludes the denied channel
- ✅ **Implementation still enforces the checks** in `packages/server/src/routes/channels.ts`:
  - Guild channel list filters bot-visible channels via `requireBotChannelPermission` (`lines 20-25`)
  - `GET /channels/:id` checks `VIEW_CHANNEL` before returning channel metadata (`lines 29-39`)
  - `PATCH /channels/:id` checks `VIEW_CHANNEL` before mutation (`lines 77-86`)
  - `DELETE /channels/:id` checks `VIEW_CHANNEL` before deletion (`lines 127-136`)
- ✅ **Test suite verified**: `pnpm test` → `223 passed (223)`, 12 server test files passed.
- ✅ **Build verified**: `pnpm build` completed successfully across workspace packages.

## Product Impact
The feature now consistently enforces the stated MVP for bots: by default, bots without explicit `VIEW_CHANNEL` overwrites cannot access channel metadata, message/reaction/typing routes, READY channel lists, or filtered channel lists. Humans remain outside this bot-visibility model, as intended.

`CHANNEL_CREATE` and `CHANNEL_DELETE` remain intentionally unfiltered via `broadcastToGuild`, matching the R4 resolution for lifecycle/topology events and avoiding the previously identified create/delete delivery pitfalls. `CHANNEL_UPDATE` and content-bearing channel events remain filtered.

## Suggestions
- Consider adding a short source comment near `GatewayDispatcher.channelCreate/channelDelete` explaining why these lifecycle events are intentionally unfiltered while `CHANNEL_UPDATE` is filtered. This would prevent future reviewers from re-flagging the same design choice.
- Consider centralizing the `VIEW_CHANNEL` bigint constant; it is still represented separately in `routes/helpers.ts`, `ws/dispatcher.ts`, `ws/session.ts`, and `@cove/shared` as a string flag.
- PR body still says “210 tests pass”; update it to `223 tests pass` before merge for accuracy.

## Positive Notes
- The new tests are targeted at the exact R4 gap and cover the previously repeated regression area.
- The route helper keeps the authorization behavior centralized and readable.
- The suite/build results are clean.
- The permission model now has meaningful negative coverage across REST routes, gateway filtering, and channel list filtering.

## Rating
✅ Ready
