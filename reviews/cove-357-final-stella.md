# Stella Final Review — PR #357 (Round 5)

## 1. New Changes Review

### ⚠️ Blocking: fresh database startup is broken by non-idempotent V15 migration

**Files:**
- `packages/server/src/db/migrations/v1-legacy.ts:13-16`
- `packages/server/src/db/schema.ts:16-30,125-130`
- `packages/server/src/db/migrations/v15-threads.ts:4-20`

For a brand-new database, `migrateV0ToV1()` calls `createAllTables(db)`, and `createAllTables()` now creates the final schema including the thread columns on `channels` and the `thread_members` table (with `flags`). The migration loop then continues through V15, where `migrateV15()` unconditionally runs:

```sql
ALTER TABLE channels ADD COLUMN parent_id ...;
ALTER TABLE channels ADD COLUMN message_id ...;
...
```

Those columns already exist on a fresh DB created by V1, so SQLite will throw `duplicate column name: parent_id` (or the next duplicate column), preventing a new Cove install from initializing.

This is a functional blocker even with small-team calibration: existing upgraded/staging DBs may work, but a clean setup or test DB from scratch will fail.

**Suggested fix:** make V15 idempotent using the existing migration utility pattern, e.g. `addColumnIfMissing()` for each channel column, and keep `CREATE TABLE IF NOT EXISTS thread_members`. Also ensure `flags` is still added by V16 for DBs that already had V15 without it.

Example direction:

```ts
addColumnIfMissing(db, "channels", "parent_id", "TEXT REFERENCES channels(id) ON DELETE CASCADE");
addColumnIfMissing(db, "channels", "message_id", "TEXT");
...
```

Then run/restore coverage for `initDb()` on a fresh in-memory DB.

### Non-blocking observations

- Discord schema alignment looks directionally correct: message-backed threads now use `thread.id === message.id`, `message.thread` returns the full `Channel`, `ThreadMetadata.invitable` is populated on new threads, and V16 adds `ThreadMember.flags` with a default.
- The Thread Panel archive/delete UI is straightforward and the two-step delete confirmation is present.
- The Thread Browser active/archived tabs are simple and readable. Archived threads can be opened, but the panel still shows the normal message input; server-side archived-send rejection exists, so this is UX polish rather than a blocker.
- Archive/delete calls close the panel even if the API request fails. That can make failures look successful, but it is not a security issue and is acceptable as follow-up polish.

## 2. Regression Check

- Quick scan did not find new regressions in the previously reviewed thread permission inheritance, gateway thread events, message thread enrichment, or sidebar real-time removal paths.
- `THREAD_UPDATE` removes archived threads from the sidebar immediately, and `THREAD_DELETE` removes deleted threads from local thread state.
- `getThreadForMessage()` has a compatibility fallback for older generated-ID threads via `message_id`, which helps staged/pre-R5 data.

**Verification attempted:**

- `pnpm -r test` could not complete in this worktree because dependencies are not installed (`@vitejs/plugin-react`, `hono`, `better-sqlite3`, etc. missing). The fresh-DB migration issue above is based on direct code-path inspection of `runMigrations()` + `migrateV0ToV1()` + `migrateV15()`.

## 3. Summary + Verdict

⚠️ **Needs Changes**

The R5 UI/schema changes mostly look good, and Luna’s staging confirmation is encouraging. However, the migration path for a brand-new database appears broken because V15 is not idempotent while V1 creates the current final schema. Please fix the V15 migration guards before merge, then rerun the migration tests/fresh DB initialization gate.
