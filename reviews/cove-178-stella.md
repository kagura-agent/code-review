# Stella Review — kagura-agent/cove PR #178

## Summary
⚠️ **Needs Changes**

The direction is good: centralizing schema changes behind `PRAGMA user_version` is much safer than scattered best-effort `ALTER TABLE` blocks. However, the V0→V1 legacy migration has a blocking correctness bug for real databases that contain messages referencing channels: the migration is wrapped in a transaction, but it tries to toggle `PRAGMA foreign_keys` inside that transaction before dropping/rebuilding `channels`. In SQLite that toggle is ineffective while a transaction is active, so `DROP TABLE channels` can fail with `FOREIGN KEY constraint failed`.

## Critical Issues

1. **Legacy channel rebuild can fail on existing message data** — `packages/server/src/db/schema.ts:23`, `packages/server/src/db/schema.ts:156`, `packages/server/src/db/schema.ts:181`
   - `runMigrations()` wraps each migration in `db.transaction(...)`.
   - `migrateChannelsToDiscordSchema()` then calls `PRAGMA foreign_keys = OFF` before rebuilding `channels`, but SQLite does not apply `foreign_keys` changes while inside an active transaction.
   - For a legacy DB with `messages.channel_id REFERENCES channels(id)` and at least one message, dropping `channels` during the rebuild fails.
   - I reproduced this locally with a legacy island-style `channels` table plus one message referencing `home`; `initDb()` failed with `FOREIGN KEY constraint failed`.
   - Fix options: disable FK checks before entering the migration transaction and restore after, rebuild dependent tables safely, or use SQLite’s recommended table-rebuild sequence with FK handling outside the active transaction plus `PRAGMA foreign_key_check` before committing/marking the version.

## Product Impact

- This can prevent production/staging from starting after deploy if the existing DB has old island-style channels and messages. Because `initDb()` runs at server startup, the app would fail before serving traffic.
- Fresh databases and some sparse legacy fixtures pass, so CI green does not rule out this real migration path.

## Suggestions

1. **Fail on databases from a newer schema version** — `packages/server/src/db/schema.ts:15`
   - `currentVersion > LATEST_VERSION` currently returns as if everything is fine. That is risky during rollback/downgrade: old code may run against an incompatible future schema.
   - Prefer explicit failure with a message like `Database schema version X is newer than supported version Y`.

2. **Replace the misleading missing-migration test** — `packages/server/src/__tests__/migration.test.ts:65`
   - The test is named “future version throws on missing migration”, but it neither creates a future version nor asserts a throw. It only initializes an empty DB and expects version 1.
   - Add actual coverage for `currentVersion > LATEST_VERSION` once implemented, and/or expose/test the migration runner gap behavior directly.

3. **Add a regression test for legacy data with FK references**
   - Create old island-style `channels`, create `messages` with `channel_id REFERENCES channels(id)`, insert a message referencing a channel, then run `initDb()`.
   - Assert migration succeeds, message rows remain, `channels` has the final schema, and `PRAGMA foreign_key_check` returns no rows.

4. **Run `PRAGMA foreign_key_check` after legacy migration**
   - Especially after disabling FK enforcement and rebuilding tables, this gives a strong safety gate before setting `user_version = 1`.

## Positive Notes

- The new runner is much easier to reason about than repeated ad-hoc `try/catch` migrations.
- Setting `user_version` in the same migration flow is the right persistence mechanism for SQLite.
- Fresh DB creation through the final schema avoids unnecessary historical steps.
- The `scenes → channels` conflict guard is preserved, including the important “both tables have data” fail-loud path.
- Tests cover several useful migration and seeding paths; they just need the missing FK/data-retention cases added before merge.
