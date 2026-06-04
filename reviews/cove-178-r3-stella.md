# PR #178 Round 3 Review — Stella

## 1. Summary

✅ **Ready**

The four Round 2 escalated items have all been addressed in the updated code. The future-version test now really creates a newer DB and asserts the throw; the FK-bearing legacy migration regression is covered; `PRAGMA foreign_key_check` now runs after migration; and the unused `guildId` parameter has been removed.

I re-reviewed the migration flow with fresh eyes and ran the relevant server tests locally on commit `98c9f6427bad6be2bc7af27bbe3124582a06c584`:

- `pnpm --filter @cove/server test --run src/__tests__/migration.test.ts` — ✅ 12 tests passed
- `pnpm --filter @cove/server test` — ✅ 99 tests passed

No remaining issue rises to blocker level. I have a few follow-up suggestions around rollback semantics and legacy-table detection, but they should not block this PR.

## 2. Previous Issues Status

1. 🔴 **“Future version throws” test is fake** — ✅ **fixed**
   - The test now creates an on-disk DB, sets `PRAGMA user_version = 999`, closes it, and asserts `initDb(tmpFile)` throws `/newer than supported/` (`packages/server/src/__tests__/migration.test.ts:65-73`).
   - This directly exercises `currentVersion > LATEST_VERSION` (`packages/server/src/db/schema.ts:15-17`).

2. 🔴 **FK regression test missing** — ✅ **fixed**
   - New test creates legacy `channels` with island columns, a `users` table, and a `messages` table with `channel_id TEXT NOT NULL REFERENCES channels(id)` before running `initDb()` (`migration.test.ts:79-119`).
   - This covers the important failure mode from earlier rounds: rebuilding/dropping `channels` while `messages` references it.

3. 🔴 **No `PRAGMA foreign_key_check` post-migration** — ✅ **fixed**
   - `initDb()` now re-enables FK enforcement and runs `db.pragma("foreign_key_check")`; any returned rows throw with details (`schema.ts:252-258`).
   - This closes the previous silent-orphan acceptance risk.

4. 🔴 **Unused `guildId` parameter in `migrateChannelsToDiscordSchema`** — ✅ **fixed**
   - The helper signature is now `migrateChannelsToDiscordSchema(db)` and the call site passes only `db` (`schema.ts:154`, `schema.ts:229`).

R2 suggestions status:

- **Guild name drift (`Cove` vs default)** — ✅ effectively resolved/consistent; the default guild seed and test both use `Cove`.
- **`createAllTables()` idempotency comment** — ⚠️ still could be clearer, but not blocking.
- **Transaction rollback test** — ⚠️ still missing; suggested below.
- **`hasAnyTable` probe narrow** — ⚠️ still narrow (`channels`, `scenes`, `messages`, `users` only), but acceptable as a follow-up unless partial legacy DBs are expected in production.

## 3. Critical Issues

None.

The earlier critical path — FK toggling inside a SQLite transaction being a no-op — is now handled at the `initDb()` level before `runMigrations()` enters the per-version transaction (`schema.ts:248-252`). The new regression test also verifies the channel rebuild works with FK-bearing messages.

## 4. Product Impact

- **Upgrade safety is much stronger now.** Existing DBs with `messages → channels` references should migrate through the channel table rebuild without crashing.
- **Data integrity is no longer silently bypassed.** If migration leaves orphaned FK references, startup now throws instead of accepting a corrupted DB.
- **Operational caveat:** the FK validation currently runs after the migration transaction has committed and after `user_version` is set. If `foreign_key_check` fails, the app correctly refuses to boot, but the DB may already be marked V1. That is recoverable/manual-repair territory, not a blocker, but worth tightening in a follow-up.

## 5. Suggestions

1. **Add a rollback/version test for failed migration.**
   - Example: create conflicting non-empty `scenes` and `channels`, assert `initDb()` throws, reopen the DB, and assert `PRAGMA user_version` is still `0`.
   - This would lock in the intended transactional behavior of `runMigrations()`.

2. **Consider validating FKs before setting `user_version` where practical.**
   - Current code sets `user_version = v` inside the migration transaction, then runs `foreign_key_check` after `runMigrations()` returns.
   - For V1 this is acceptable, but in future multi-version migrations it may be cleaner to run integrity validation before finalizing the version, or to document why validation is intentionally post-transaction.

3. **Broaden or document `hasAnyTable`.**
   - `migrateV0ToV1()` only probes `channels`, `scenes`, `messages`, and `users` (`schema.ts:41-44`).
   - A DB containing only `guilds`, `invite_codes`, or `pending_registrations` is classified as “fresh”. If that state is impossible/unsupported, add a comment. If it is possible, prefer checking for any non-SQLite user table.

4. **Add a stronger idempotency comment to `createAllTables()`.**
   - The function is used both for fresh creation and partial legacy DB normalization. A short warning that `CREATE TABLE IF NOT EXISTS` does not upgrade existing table shapes would help future migration authors avoid over-trusting it.

## 6. Positive Notes

- The Round 3 update directly addressed all four escalated R2 findings.
- The new tests are targeted and meaningful rather than just increasing coverage numbers.
- The migration runner is now clean and extensible: version check, registry lookup, per-version transaction, and version bump are easy to follow.
- `foreign_key_check` failure includes serialized violation details, which should help manual repair if it ever trips.
- Removing the unused parameter reduced confusion in exactly the right spot.

**Rating: ✅ Ready**
