# Nova Review — cove#250: split schema.ts into focused modules

## 1. Summary
Pure file split refactor of `packages/server/src/db/schema.ts` (627 → 175 lines) into 8 focused modules under `db/migrations/`. Verified behaviorally equivalent: build clean, all 152 server tests pass locally on `pr-250` checkout, every migration body is byte-identical to the original, migration ordering and `LATEST_VERSION = 5` preserved, public exports from `schema.ts` (`initDb`, `seedChannels`, `seedUsers`, `createAllTables`) unchanged for downstream importers (`src/index.ts`).

## 2. Critical Issues
None. The "pure split" claim holds.

## 3. Suggestions

### S1 — Circular import: `schema ↔ migrations/v1-legacy` (low risk, code smell)
The split introduces a cycle:

- `db/schema.ts` → `db/migrations/index.js` (for `runMigrations`)
- `db/migrations/index.js` → `db/migrations/v1-legacy.js`
- `db/migrations/v1-legacy.ts` → `../schema.js` (for `createAllTables`)

It works today because `createAllTables` is only invoked at runtime (after all modules have fully evaluated), and the schema module's top-level body contains no calls into the migration graph. ESM handles this fine in Node, but it's a fragile arrangement — adding any top-level code in `schema.ts` that touches migration state would deadlock evaluation.

Cleaner factoring options (post-merge, not a blocker):
- Move `createAllTables` into `migrations/util.ts` or a new `migrations/fresh-schema.ts`, then have `schema.ts` re-export it.
- Or invert the dependency: have `schema.ts` accept a `runMigrations` callback rather than importing it.

### S2 — `runMigrations` visibility broadened (intentional?)
Previously `runMigrations` was a file-local function in `schema.ts`; now it's an `export` from `migrations/index.ts`. Functionally fine and necessary for the split, but it does widen the public surface of the `db/` directory. Consumers should still be told to call `initDb`. Worth a one-line JSDoc `@internal` if you want to discourage direct use.

### S3 — `addColumnIfMissing` interpolation (pre-existing, not introduced here)
The util `addColumnIfMissing(db, table, column, definition)` builds SQL by string interpolation. This is unchanged from the original, so not a regression — flagging only because the split makes the helper a more visible, reusable target. Future migrations should keep `column`/`definition` as code-constants and never accept caller-controlled strings. No action needed for this PR.

## 4. Positive Notes
- Per-file split is sensibly partitioned by version (v1..v5) with shared helpers isolated in `util.ts`. Easy to read each migration in isolation.
- `isSnowflake`, `tableExists`, `hasColumn`, `addColumnIfMissing`, `migrateRenameTable` extracted cleanly with identical implementations — the inline closure `hasColumn` from `migrateV2ToV3` is now properly shared instead of duplicated.
- Migration registry (`migrations: Record<number, MigrationFn>`) preserved verbatim, including the V0→V1 numbering convention and the "newer than supported" guard.
- All console.log strings, error messages, transaction boundaries, and FK toggling semantics preserved exactly.
- `createAllTables` correctly promoted to `export` so `v1-legacy.ts` can call it for fresh-DB short-circuit.
- Verified end-to-end: `pnpm -r build` clean, server test suite 152/152 pass, migration logs (`V0→V1` through `V4→V5`) appear in expected order.

## 5. Verdict
✅ **Approve.** Safe to merge. The split is faithful and well-organized. The circular-import note (S1) is worth addressing in a follow-up but does not block this PR.
