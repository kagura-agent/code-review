# PR #178 Round 2 Review — Stella

## Summary

⚠️ **Needs Changes**

The R1 critical transaction/FK-toggle bug is materially fixed: `foreign_keys` is now disabled before `runMigrations()` enters the per-version transaction, so the `DROP TABLE channels` rebuild path no longer depends on a no-op PRAGMA inside a transaction.

However, the fix stops at disabling constraints and does not validate the migrated database before marking it V1. Several R1 follow-ups are still unaddressed, including the misleading future-version test, no regression test for messages referencing rebuilt channels, no `foreign_key_check`, the narrow legacy detection probe, and no rollback test.

Validated locally:
- `pnpm -F @cove/server test -- --run packages/server/src/__tests__/migration.test.ts` — passes, but also runs `api.test.ts` due Vitest arg handling.
- `pnpm -F @cove/server build` — passes.
- Manual FK regression with `messages.channel_id -> channels.id` across island-schema channel rebuild — passes.

## Previous Issues Status

1. **R1 critical: `PRAGMA foreign_keys = OFF` was a no-op inside the migration transaction** — ✅ **addressed in implementation**
   - `initDb()` now disables FK enforcement before `runMigrations()` starts the transaction (`packages/server/src/db/schema.ts:248-252`).
   - `migrateChannelsToDiscordSchema()` correctly no longer toggles FK inside the transaction (`schema.ts:154-185`).
   - Manual reproduction with `messages` referencing rebuilt `channels` succeeds.

2. **Fail on databases with newer schema version** — ✅ **addressed in code**, ❌ **not actually tested**
   - Code throws for `currentVersion > LATEST_VERSION` (`schema.ts:15-17`).
   - The test named “future version throws” never sets `user_version` above latest and never asserts a throw (`migration.test.ts:65-80`).

3. **Future-version test does not test the throw** — ❌ **unaddressed**
   - Still true; the comments even describe the old broken behavior while asserting `version === 1` (`migration.test.ts:70-79`).

4. **Add `createAllTables()` idempotency comment** — ⚠️ **partially addressed**
   - The code path is clearer, but there is still no explicit warning that this function is intentionally idempotent and must remain compatible with partial legacy schemas (`schema.ts:56-125`).

5. **Regression test with FK data (`messages` referencing `channels`)** — ❌ **unaddressed in automated tests**
   - Existing island migration test rebuilds channels but does not create a `messages` table with FK references (`migration.test.ts:168-227`).
   - I manually verified this case works after the implementation change.

6. **`PRAGMA foreign_key_check` post-migration** — ❌ **unaddressed**
   - FKs are re-enabled after migration, but no validation is performed before accepting/marking the DB as migrated (`schema.ts:250-252`).

7. **Unused `guildId` parameter** — ❌ **unaddressed**
   - `migrateChannelsToDiscordSchema(db, guildId)` still accepts `guildId` but does not use it (`schema.ts:154`, called at `schema.ts:229`).

8. **`hasAnyTable` probe is narrow** — ❌ **unaddressed**
   - Legacy detection still only checks `channels`, `scenes`, `messages`, and `users` (`schema.ts:39-44`). Existing `guilds`, `invite_codes`, or `pending_registrations`-only DBs can be treated as fresh and marked V1 without legacy normalization.

9. **Transaction rollback test** — ❌ **unaddressed**
   - No test currently asserts failed migrations roll back schema/data/user_version.

## Critical Issues

None remaining at the same level as R1’s “migration fails for normal legacy data” blocker. The core R1 failure mode is fixed in code.

## Product Impact

- **Remaining data-integrity risk:** Because migrations run with FK checks disabled and do not run `PRAGMA foreign_key_check`, invalid legacy references can be silently accepted and the DB can still be marked `user_version = 1` (`schema.ts:26-29`, `schema.ts:250-252`). Re-enabling `foreign_keys` does not retroactively validate existing rows.
- **Upgrade confidence is still weaker than it looks:** The test suite says “future version throws” but does not test that behavior (`migration.test.ts:65-80`), and the specific R1 regression scenario is still not covered by automated tests.
- **Partial/odd legacy DBs may be incorrectly finalized:** The narrow `hasAnyTable` check can classify existing DBs as fresh and set V1 even when non-probed tables already exist (`schema.ts:39-49`).

## Suggestions

1. Add post-migration FK validation before returning from `initDb()`:
   - Run `PRAGMA foreign_key_check` after `db.pragma("foreign_keys = ON")`.
   - If rows are returned, throw with enough table/row details for manual repair.
   - This should happen before the app proceeds to seed/use the DB.

2. Fix the future-version test:
   - Create a DB, run `PRAGMA user_version = 2`, close it, then assert `initDb(tmpFile)` throws `/newer than supported/`.

3. Add the missing automated regression test for R1:
   - Legacy island-style `channels` table with `position_x`.
   - `messages.channel_id REFERENCES channels(id)` with rows pointing at those channels.
   - `initDb(tmpFile)` should succeed and preserve messages.

4. Add a rollback test:
   - Create conflicting `scenes` + `channels` data so migration throws.
   - Reopen the DB and assert `user_version` is still `0` and partial changes were not committed.

5. Broaden legacy detection:
   - Prefer checking `sqlite_master` for any user table, excluding SQLite internals, instead of hardcoding four table names.

6. Remove or use the unused `guildId` parameter in `migrateChannelsToDiscordSchema()`.

## Positive Notes

- The R1 critical FK-toggle bug was addressed in the right architectural place: outside the migration transaction.
- `currentVersion > LATEST_VERSION` now fails loudly in code.
- The migration runner is much easier to reason about than scattered ad-hoc `ALTER TABLE` blocks.
- Fresh DB creation and latest-version no-op behavior are covered.
- Local server tests and TypeScript build pass on this branch.
