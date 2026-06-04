# PR #178 Review — Versioned Migration System
**Reviewer:** 🌠 Nova
**Repo:** kagura-agent/cove
**Verdict:** ⚠️ Needs Changes

## 1. Summary
Replaces scattered try/catch `ALTER TABLE` blocks with a `PRAGMA user_version`–driven migration runner. Fresh DBs short-circuit to a single `createAllTables` path; legacy DBs run a consolidated `migrateLegacyToV1`. Adds 5 tests covering the new flow and re-uses prior legacy migration tests with version assertions.

The architecture is the right direction (versioned, transactional, fails loudly). However, there are correctness regressions hiding in the refactor that should be fixed before merge.

## 2. Critical Issues

### C1. `PRAGMA foreign_keys = OFF` is a no-op inside a transaction *(packages/server/src/db/schema.ts:159, 172)*
`runMigrations` now wraps each step in `db.transaction(() => { migration(db); ... })()`. SQLite documents that `PRAGMA foreign_keys` **cannot be changed within a transaction** — the call is silently ignored. Previously `migrateChannelsToDiscordSchema` and the `guild_id` ALTER both toggled FKs **outside** any outer transaction, so they worked. After this PR, both `db.pragma('foreign_keys = OFF')` calls inside `migrateLegacyToV1` / `migrateChannelsToDiscordSchema` are effectively dead code.

Today this happens to be safe — no other table currently has a FK pointing at `channels`, and the data being inserted satisfies the `guild_id → guilds(id)` constraint. But:
- The intent of the toggle is no longer enforced; the next FK added (e.g. `messages.channel_id REFERENCES channels(id)`) will fail mid-migration.
- The pattern survives in code unchanged, which will mislead future contributors.

**Fix options:**
- Run `migrateChannelsToDiscordSchema` outside the outer transaction, or
- Use `PRAGMA defer_foreign_keys = ON` (allowed inside a transaction), or
- Drop the FK toggles entirely and add a code comment explaining why they’re unnecessary.

### C2. `migrateLegacyToV1` runs `createAllTables` against a legacy schema before column/table fixups
At schema.ts:201 the legacy path now calls `createAllTables(db)` *before* `migrateChannelsToDiscordSchema` runs. `createAllTables` issues `CREATE TABLE IF NOT EXISTS channels (... guild_id NOT NULL REFERENCES guilds(id), type INTEGER, topic TEXT, position INTEGER ...)`. On a legacy DB whose `channels` table still has `icon/position_x/position_y/description` and no `guild_id`, this is a no-op (good) — but it also creates `messages` with the new column set (`sender_name`, `edited_timestamp`) only if absent. On a legacy DB with an existing `messages` table, the subsequent `addColumnIfMissing` calls are correct.

The risk: in a legacy DB without `guilds` table, `createAllTables` creates a fresh `guilds`, then the code below tries to read “oldest guild” — finds none and inserts one. Then `ALTER TABLE channels ADD COLUMN guild_id NOT NULL DEFAULT '<id>'` fires. So far so good. But the test `migrates old island-style channels to discord schema` sets up a DB *with* `guilds` already populated by a fixed `'g1'` id (test line ~190), while `migrateLegacyToV1` will pick that existing `'g1'` row — good. Worth noting in a code comment that the legacy path **depends on `createAllTables` being idempotent** for every table it touches; the current implementation is, but it’s fragile (any non-`IF NOT EXISTS` statement added there will break legacy DBs).

Not a blocker, but please at minimum add an inline comment to `createAllTables` warning future authors that it’s reused by the legacy path and must stay `IF NOT EXISTS`.

## 3. Product Impact
- Existing prod DBs (which sit at `user_version = 0` by default) will hit the legacy branch on first boot, get migrated, and be stamped `user_version = 1`. Net effect should be invisible to users.
- **Recommend a one-shot dry-run on a copy of the production DB** before deploying — given C1, any pre-existing data that violates the new FK on `channels.guild_id` would now actually surface (previously FK was disabled during the rebuild and re-enabled after, masking issues). That is arguably a *good* thing but should be expected.

## 4. Suggestions

- **S1 (docs):** PR description registry example shows `0: migrateLegacyToV1, 1: migrateV1toV2`, but actual code uses `1: migrateV0ToV1`. The map is keyed by *target* version. Please align the PR description so future contributors don’t add a step keyed by the wrong number.
- **S2 (correctness):** `hasAnyTable` in `migrateV0ToV1` only probes `channels/scenes/messages/users`. A DB containing only `guilds` or `invite_codes` (theoretical, but possible after partial recovery) would be treated as fresh and re-`createAllTables` would re-fly. Consider `SELECT count(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'` instead.
- **S3 (test gap):** The new test `"future version throws on missing migration"` does **not actually exercise the throw** — the comment even admits it (test file lines ~71–85). Either drop it or construct the failure: e.g. temporarily monkey-patch `LATEST_VERSION` / push a `migrations` entry whose number is missing, and assert `runMigrations` throws `Missing migration for version N`.
- **S4 (test gap):** No test asserts that the migration runs **inside a transaction** (e.g. inject a failing step and verify `user_version` stayed at 0 and no partial schema leaked).
- **S5 (logging):** `console.log("Running migration V… → V…")` is fine for now, but server already has logger infrastructure elsewhere — switch when convenient so migration logs survive log-level filtering.
- **S6 (style):** `db.pragma(\`user_version = ${v}\`)` uses string interpolation; `v` is loop-controlled, so safe. A small helper `setUserVersion(db, v)` would document intent.
- **S7 (cleanup):** The `_guildId` parameter on `migrateChannelsToDiscordSchema` was previously underscored; in this PR it’s renamed to `guildId` but still unused inside the function. Drop the parameter to avoid future confusion.

## 5. Positive Notes
- Centralizing the version check and transaction wrap in `runMigrations` is clean and idiomatic.
- `addColumnIfMissing` helper eliminates duplicated try/catch noise — nice.
- Fail-loudly on missing migration (`throw new Error(\`Missing migration for version ${v}\`)`) is the right call.
- New tests give meaningful coverage of the fresh-DB happy path and preserve the legacy migration suite.
- Stamping `user_version = 1` on legacy DBs immediately unlocks the V1→V2 path; the registry pattern documented in the PR will scale.

---
**Recommendation:** Address C1 (FK pragma in transaction) and S3 (real test for the throw branch) before merge. C2/S2/S7 can land as follow-ups but a code comment in `createAllTables` is worth including in this PR.
