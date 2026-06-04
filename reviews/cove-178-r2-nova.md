# 🌠 Nova — Round 2 Review: PR #178 (cove)

**Rating: ⚠️ Needs Changes**

## 1. Summary

The R1 critical issue (FK toggle as a no-op inside a transaction) is genuinely fixed: `initDb()` now disables `foreign_keys` *before* calling `runMigrations()`, and the in-migration `PRAGMA foreign_keys` toggles have been removed. The author added an explanatory comment, which is good engineering discipline.

However, several R1 suggestions were skipped, the "future version throws" test is structurally broken (the test does not exercise the throw it claims to), and a subtle inconsistency in seeded guild naming was introduced. Plus the unused `guildId` parameter remained, and per the escalation rule, missing-FK regression coverage now climbs to **High**.

## 2. Previous Issues Status

| R1 Issue | Status | Notes |
|---|---|---|
| 🔴 FK PRAGMA no-op in tx | ✅ Fixed | FK off in `initDb()` outside any tx; inner toggles removed; comment added. |
| Fail on `currentVersion > LATEST_VERSION` | ✅ Fixed | `schema.ts` throws with clear message. |
| "Future version" test doesn't test the throw | ❌ Not fixed → **escalated** | See Critical #1 below. Test is now actively misleading. |
| `createAllTables` idempotency comment | ⚠️ Partial | Uses `CREATE TABLE IF NOT EXISTS` for all tables, but no comment explaining the dual fresh/legacy reuse. |
| FK regression test (messages → channels) | ❌ Not fixed → **escalated to High** | The whole reason R1 was Critical. Migration is still untested with real FK-bearing data. |
| `PRAGMA foreign_key_check` post-migration | ❌ Not fixed | Cheap insurance; still missing. |
| Unused `guildId` param in `migrateChannelsToDiscordSchema` | ❌ Not fixed | Was `_guildId`; renamed to `guildId` but still unused. Worse than before — no leading underscore now makes the dead param look intentional. |
| `hasAnyTable` probe narrow | ⚠️ Unchanged | Probes channels/scenes/messages/users. Acceptable for current legacy fleet but undocumented. |
| Transaction rollback test | ❌ Not fixed | No assertion that a failing migration leaves `user_version` unchanged. |

## 3. Critical / High Issues

### C1 — "future version throws on missing migration" test is fake (High)
File: `packages/server/src/__tests__/migration.test.ts`, lines ~52–71.

The test name promises to exercise the new "missing migration / version gap" throw, but the body sets up *nothing*: it opens a fresh tmp file, immediately closes it, then calls `initDb(tmpFile)` and asserts version becomes `1`. The author even acknowledges this in a comment: *"This won't trigger runMigrations since current >= LATEST_VERSION"*.

Net effect:
- The throw on `Missing migration for version v` is **completely uncovered**.
- The throw on `currentVersion > LATEST_VERSION` is also **uncovered**.
- The misleading test name produces false confidence in any future R3.

**Fix:** Two tiny tests. Use raw `better-sqlite3` to:
```ts
const setup = new Database(tmpFile);
setup.pragma("user_version = 99");
setup.close();
expect(() => initDb(tmpFile)).toThrow(/newer than supported/);
```
And similarly for a synthetic gap (requires temporarily stubbing `LATEST_VERSION` — or refactor `runMigrations` to accept the registry, which is also good API design).

### C2 — Legacy FK-bearing data still untested (High, escalated from R1)
The R1 critical was rooted in: *messages referencing channels will fail when channels is dropped/recreated with FK on*. The fix at the `initDb` level looks correct, but there is still no test that:
1. Creates a legacy DB with `messages.channel_id` rows pointing into legacy `channels`.
2. Runs `initDb`.
3. Asserts row count and join integrity post-migration.

Without this, the original Critical is structurally unverified. The two existing island→discord tests only insert channels, no messages.

**Fix:** One regression test that inserts 2 channels + 3 messages with `scene_id`/`channel_id` FK, runs migration, and asserts messages still join correctly post-rename + post-rebuild. Add a `PRAGMA foreign_key_check` assertion at the end (returns empty result set on success — one-liner).

## 4. Product Impact

- **Operations**: Fresh DBs are now clearly versioned; future schema rollouts are straightforward (the README-style guidance in the PR body is excellent).
- **Backwards compat**: Legacy DBs route through `migrateLegacyToV1`. The path is plausibly correct but unverified for the exact failure mode that motivated this PR.
- **Drift risk**: Fresh DBs seed a guild named **"Cove"** (in `initDb`), legacy DBs seed one named **"default"** (in `migrateLegacyToV1`). This silently diverges branding by deployment age. Pick one — recommend `"Cove"`.
- **Downgrade safety**: Server now refuses to boot against a newer-versioned DB. Good — prevents silent corruption on rollback.

## 5. Suggestions

1. **(High)** Fix C1 & C2 — both small, both load-bearing.
2. **(Med)** Unify the seeded guild name (`"default"` vs `"Cove"`) — pick `"Cove"` and remove the inline seed inside `migrateLegacyToV1`; rely on the post-migration seed in `initDb`. The legacy migration only needs *an* existing guild id for the `DEFAULT '${guildId}'` column literal, which it can get from the post-seed by reordering, or by deferring the column default to be filled after seed.
   - Actually simpler: seed the guild **before** `runMigrations` if no guild exists, so legacy migration can read it. Then there's one seed path.
3. **(Med)** Run `PRAGMA foreign_key_check` after `runMigrations` and before re-enabling FK; throw if it returns any rows. Two extra lines, prevents shipping a structurally corrupt DB.
4. **(Low)** `runMigrations` should accept the migrations registry as a parameter to enable testing of gap/version errors without monkey-patching.
5. **(Low)** Remove the unused `guildId` param on `migrateChannelsToDiscordSchema` (or actually use it — currently `channels_new` accepts whatever `guild_id` legacy rows already have, which is fine, so just drop the param).
6. **(Low)** Add an assertion-style comment to `createAllTables`: *"Idempotent: used both for fresh init and as a safety net in `migrateLegacyToV1` to backfill tables missing from old DBs."*
7. **(Low)** Transaction rollback test: force `migrateV0ToV1` to throw mid-flight (e.g., simulate by injecting bad SQL via a temporary migration), assert `user_version` is still 0 and that no partial schema exists.
8. **(Nit)** `migrateLegacyToV1` calls `createAllTables(db)` *before* doing column adds and the channels rebuild. Since `createAllTables` uses `CREATE TABLE IF NOT EXISTS`, existing tables aren't touched — but it does create `messages` with the final schema *including* `sender_name`. So the subsequent `addColumnIfMissing(... "sender_name" ...)` is dead code for any legacy DB without a pre-existing messages table. Harmless, but worth a comment or a reordering for clarity.

## 6. Positive Notes

- ✅ The R1 critical fix is correct and well-commented. The "do NOT toggle foreign_keys here" comment is exactly the kind of fossil future-you will thank present-you for.
- ✅ Versioned migration framework is clean and extensible; the README/PR body example is the right level of guidance.
- ✅ `addColumnIfMissing` helper meaningfully reduces noise vs. three identical try/catch blocks.
- ✅ Refusal to run on `currentVersion > LATEST_VERSION` is a small but important safety bar.
- ✅ Test file got a nice `tmpDb()` helper and version assertions sprinkled into the existing legacy tests. Both are quality-of-life wins.

---

**Bottom line:** The headline fix is real. But the test for the new "future version" guard is theater, and the FK regression test that would actually prove the R1 critical is closed is still missing. Tighten C1 + C2 (both are <30 lines of test code) and this is ready.
