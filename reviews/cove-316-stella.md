# PR #316 Re-review — Stella (Round 4)

## Summary
This round fixes the previously re-escalated REST gating bug in code: `GET /channels/:id`, `PATCH /channels/:id`, and `DELETE /channels/:id` now all call `requireBotChannelPermission(..., VIEW_CHANNEL)` for bot users before returning/updating/deleting the channel. `CHANNEL_CREATE` and `CHANNEL_DELETE` are also now dispatched via unfiltered `broadcastToGuild`, which matches the stated intentional behavior for create/delete lifecycle events. However, the newly added channel-route access checks still do not have direct positive/negative tests for denied/allowed bot access on those exact routes, so this is not ready under the review standard for auth/security paths.

## Critical Issues

1. **Missing tests for the newly-gated `GET/PATCH/DELETE /channels/:id` routes**  
   Files: `packages/server/src/routes/channels.ts:29-39`, `packages/server/src/routes/channels.ts:77-86`, `packages/server/src/routes/channels.ts:127-136`; test gap in `packages/server/src/__tests__/permissions.test.ts:232-361`.

   The implementation now gates the three channel-object routes with `VIEW_CHANNEL`, but the permission tests only cover message/reaction/typing routes for denied bots. I could not find tests like:
   - denied bot without `VIEW_CHANNEL` cannot `GET /channels/:id`;
   - denied bot without `VIEW_CHANNEL` cannot `PATCH /channels/:id`;
   - denied bot without `VIEW_CHANNEL` cannot `DELETE /channels/:id`;
   - bot with `VIEW_CHANNEL` can access the newly gated route(s), at least for `GET`, and ideally for update/delete behavior as appropriate.

   This is a newly added access-control path. Per the review standard, auth/permission checks require both authorized and unauthorized coverage. Given this route family was the repeated R3 regression area, these route-specific tests should be added before merge.

## Product Impact
- The code behavior now matches the MVP intent: bots without explicit overwrites cannot see/read/write channel-scoped data, while humans bypass this bot visibility model.
- `CHANNEL_CREATE`/`CHANNEL_DELETE` being unfiltered means bots may receive lifecycle events for channels they cannot otherwise read. I verified the diff now does this intentionally via `broadcastToGuild`; this is acceptable if clients treat create/delete as guild topology notifications rather than proof of readable channel content.

## Suggestions
- Consider centralizing the `VIEW_CHANNEL` bit constant used in `routes/helpers.ts`, `ws/dispatcher.ts`, and `ws/session.ts` to avoid drift from `PermissionFlags.VIEW_CHANNEL` in `@cove/shared`.
- Consider target validation in `PUT /channels/:channelId/permissions/:targetId` if the API is intended to manage only guild bot members for now. The UI filters to bots, but the API currently accepts arbitrary target IDs/types if the actor is a human guild member.

## Positive Notes
- The R3 code regression is fixed: `GET`, `PATCH`, and `DELETE /channels/:id` all now check `VIEW_CHANNEL` for bots.
- `CHANNEL_CREATE` and `CHANNEL_DELETE` are unfiltered as requested, and the delete path no longer depends on resolving a deleted channel from the database.
- Existing permission tests cover the broader channel-scoped message/reaction/typing denial paths and dispatcher message filtering.
- Verification run: `pnpm --filter @cove/server exec vitest run src/__tests__/permissions.test.ts --reporter=dot` passed (`19 passed`).

## Rating
⚠️ Needs Changes
