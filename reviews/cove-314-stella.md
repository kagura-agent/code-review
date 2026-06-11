# Review: kagura-agent/cove PR #314

## Summary

This PR fixes bot management from both ends: the client now sends `bot: true` when creating bots, and `DELETE /users/:id` now allows any authenticated actor to delete target users that are bots while still preventing deletion of other human users. The implementation matches the stated permission model, and the new tests cover the important positive and negative authorization paths. Rate: ✅ Ready.

## Critical Issues

None found.

## Product Impact

- `packages/client/src/lib/api.ts:54-57` fixes the UI-created-bot path so newly created bots should now be persisted as non-expiring bot users rather than expiring human sessions.
- `packages/server/src/routes/agents.ts:95-104` intentionally broadens deletion permissions for bot users: any authenticated user can delete a bot account, but cross-user deletion of human accounts remains blocked with 403. This aligns with the provided permission model.
- Nonexistent cross-user deletes now return 404 before permission checks for non-self deletes (`packages/server/src/routes/agents.ts:98-100`), which is consistent with existing Unknown User behavior in the route and covered by tests.

## Suggestions

- Minor test hygiene: `packages/server/src/__tests__/bot-deletion.test.ts:30-31` deletes `process.env.RATE_LIMIT_ENABLED` in `afterEach`, which can clobber a pre-existing caller/test-runner value. Consider saving the previous value in `beforeEach` and restoring it after each test. This is non-blocking because the current suite passes and the pattern is localized.

## Positive Notes

- Good authorization coverage in `packages/server/src/__tests__/bot-deletion.test.ts`: bot deleting bot, human deleting bot, human blocked from deleting human, self-deletion, and nonexistent target are all tested.
- The server-side permission logic is small and easy to reason about: it resolves `@me`, allows self-deletion, checks the target once for cross-user deletion, and only allows the delete when `target.bot` is true.
- Verified targeted tests pass: `pnpm --dir packages/server exec vitest run src/__tests__/bot-deletion.test.ts --reporter=dot` → 5/5 tests passed.
