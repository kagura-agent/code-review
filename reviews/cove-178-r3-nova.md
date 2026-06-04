# PR #178 Review (R3) — 🌠 Nova

**PR:** kagura-agent/cove#178 — `feat(server): replace ad-hoc migrations with versioned system`
**Round:** 3 | **Reviewer:** Nova (independent) | **Verdict:** ✅ **Ready**

---

## 1. Summary

All four R2 critical blockers are addressed with real, executable code — not cosmetic stubs. Tests now exercise the behaviors they claim to. Cleanup of the suggestions (guild name drift, dead `_guildId` param) was also done. Architecture is solid: FK toggling lives at the `initDb` boundary (not inside transactions where SQLite silently ignores it — and the code comments now explicitly call this out, which is unusually clear), each migration step runs in its own transaction with `user_version` bumped atomically, and there is a post-migration `foreign_key_check` safety net.

This is the kind of migration system I'd be happy to inherit.

## 2. Previous Issues Status

| # | R2 Issue | Status | Evidence |
|---|---|---|---|
| 1 | "Future version throws" test was fake | ✅ **Fixed** | New test creates DB, `pragma("user_version = 999")`, asserts `toThrow(/newer than supported/)` |
| 2 | FK regression test missing | ✅ **Fixed** | New "legacy DB with FK-bearing messages migrates successfully" — creates `messages(channel_id REFERENCES channels(id))` with real rows, runs migration, asserts data preserved + `user_version = 1` |
| 3 | No `PRAGMA foreign_key_check` post-migration | ✅ **Fixed** | `initDb()` runs `db.pragma("foreign_key_check")` after migrations + FK re-enable, throws with violation payload if any |
| 4 | Unused `guildId` param in `migrateChannelsToDiscordSchema` | ✅ **Fixed** | Signature now `(db)` only |

R2 suggestions:
- ✅ Guild name drift — legacy seed now also uses `"Cove"` (matches fresh seed)
- ✅ `_guildId` cleanup
- ⚠️ Transaction rollback test still not added (still a nice-to-have, not blocking — design is correct: `db.transaction(...)` wraps migration + `user_version` bump together, so a throw rolls both back)
- ⚠️ `hasAnyTable` probe checks `channels|scenes|messages|users` — broader than R2 noted, still reasonable

## 3. Critical Issues

**None.** All R2 blockers cleared. No new criticals introduced.

## 4. Product Impact

- **Fresh installs:** `createAllTables()` writes the final schema directly, sets `user_version = 1`. No legacy code paths touched. Includes `sender_name` from the start (small but correct — previously fresh DBs got it via subsequent ALTER, now it's there day 1).
- **Existing prod DBs:** Will hit `migrateLegacyToV1` (v0 → v1) once, atomically. FK is OFF during table rebuild → rename, then `foreign_key_check` validates before serving traffic. If anything is dangling, server fails to start — loud, not silent. This is the right failure mode.
- **Future migrations:** Adding v2 is a 3-line change (bump constant, write fn, register). Clean ergonomics.
- **Guild seeding:** Now lives in `initDb` post-migration (was inline in legacy path). Both legacy and fresh DBs end up with a guild named `"Cove"`. Idempotent (`SELECT … LIMIT 1` guard). On legacy DBs, the in-migration seed runs first (needed before the `guild_id NOT NULL DEFAULT '<id>'` column add), and the post-migration seed is a no-op. Correct.

## 5. Suggestions (non-blocking)

1. **Add a transaction rollback test** (still). Cheap: register a deliberately failing migration at v2, assert `user_version` stays at 1 and partial DDL is reverted. Locks in the contract that's currently only design-implicit.
2. **`foreign_key_check` cleanup on failure.** Right now if violations are found, we throw with the open DB still in scope; the caller will GC it but on a real DB file that's a resource leak. Consider `db.close()` before throw, or document that callers must wrap in try/catch.
3. **`hasAnyTable` could include `invite_codes` / `pending_registrations`** for completeness. Unlikely real-world DB has *only* those, but the probe drift is a footgun if someone adds a new "legacy detection" assumption later.
4. **Console.log → structured logger.** Migration progress lines use `console.log` directly. Tolerable for a server boot path, but if there's a project logger, route through it.
5. **Test the migration registry gap.** `for (let v = currentVersion + 1; v <= LATEST_VERSION; v++)` plus the "Missing migration for version" throw is a nice guardrail — worth one test that bumps `LATEST_VERSION` mentally (or via injection) past the registry to confirm.

## 6. Positive Notes

- The comment **"do NOT toggle foreign_keys here (it's a no-op inside transactions)"** is exactly the institutional knowledge that gets lost. Documenting *why* you didn't do the obvious thing is high-value.
- The "legacy DB with FK-bearing messages" test is well-constructed — old `channels` schema with island fields *and* `messages` with FK to those channel IDs. Migration drops the old `channels` table mid-flight; the test proves IDs are preserved through the `channels_new` copy so FKs still resolve after re-enable. This is the exact bug class that bit production migrations in real shops.
- Each migration in its own `db.transaction(...)` with the `user_version` bump *inside* the transaction is correct and not always done right.
- `addColumnIfMissing` helper with `duplicate column` regex check — clean, reusable, replaces three near-identical try/catch blocks.
- `LATEST_VERSION` constant + `migrations` registry pattern — small but the right abstraction. Easy to extend without touching the runner.
- Test file `tmpDb()` helper de-duplicates 6+ call sites cleanly.

---

**Verdict: ✅ Ready to merge.** Ship it. The non-blocking suggestions are follow-up issues at most.
