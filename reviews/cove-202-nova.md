# 🌠 Nova Review — PR #202 (Round 3): refactor: migrate from UUID to Snowflake IDs

**Repo:** kagura-agent/cove • **Branch:** refactor/snowflake-ids → main • **Stats:** 20 files, +887/-192 • **14 commits, 6 new since R2**

## Summary

The author absorbed R2 cleanly. The two real blockers from R2 — **C5 (CAST defeating the new index)** and **C2 (all migrated channels stamped with `now`)** — are both gone. Migration-time orphan drops are now logged with before/after counts (N1). The remaining R2 items are cosmetic, low-risk, or pre-existing.

Six new commits also produced an interesting arc: an "auto-clean orphans on startup" was tried and then reverted in favour of keeping FK violations as a hard error and wiping staging instead — that's the safer choice for a single-developer prod surface. The `cove` alias and dynamic `getGuildId()` round out the API contract change.

**Rating: ✅ Ready** (the remaining items are nice-to-haves; none should block merge).

---

## R2 Issue Status

| ID | R2 Status | R3 Status | Notes |
|----|-----------|-----------|-------|
| **C2** (channels block: `now` for all) | ❌ Not Fixed | ✅ **Fixed** | `schema.ts` `migrateV2ToV3()` channels loop now does: `MIN(messages.timestamp) for that channel → guild.created_at → now`. Per-channel timestamps preserved, ID order matches creation order. |
| **C3** (cross-guild seq collision comment) | ❌ Not Fixed | ❌ **Not Fixed** | Still no inline comment in the channels loop documenting *why* loop index `i` is the seq disambiguator. A header comment ("Build old→new ID mappings per entity type to avoid cross-table key collisions") was added at line 1182 but addresses a different concern. Cosmetic; the code is correct. |
| **C4** (dangling `last_read_message_id`) | ⚠️ Partial | ⚠️ **Partial** | V3→V4's `read_states` recreate still filters `user_id`/`channel_id` against FK targets but **not** `last_read_message_id` against `messages`. Behaviour is benign with the new ID-comparison path (`excluded.last_read_message_id >= COALESCE(read_states.last_read_message_id, '0')` — lexicographic compare on TEXT, all snowflakes are now fixed-width-ish numerics, so stale IDs just don't advance), but a one-line note would be kind to future-you. |
| **C5** (`CAST(m.id AS INTEGER) DESC` bypasses index) | ⚠️ Partial | ✅ **Fixed** | All four messages.ts queries now use `ORDER BY m.id DESC` (or `ASC`) and `WHERE m.id < ? / > ?` directly. `readStates.set`'s `excluded.last_read_message_id >= COALESCE(...)` also uses raw column compare. The `idx_messages_channel_id ON messages(channel_id, id DESC)` index is now actually used by the planner. Strong fix. |
| **N1** (V3→V4 silent orphan drops) | New in R2 | ✅ **Fixed** | All three recreates (`messages`, `channels`, `read_states`) now `console.log` `before → after (N orphans removed)`. Visible in deploy logs. |
| **N2** (email UNIQUE) | New in R2 | ⚠️ **Partially Fixed** | `createAllTables()` declares `email TEXT UNIQUE` for fresh DBs ✅. But `migrateV3ToV4()` only adds a UNIQUE index for `google_id`, **not** for `email`. Migrated DBs and fresh DBs end up with different invariants. Either add `CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users(email) WHERE email IS NOT NULL` in V3→V4, or accept the gap as legacy-only. |
| **S1** (Worker/Process ID hardcoded) | ❌ Not Fixed | ❌ **Not Fixed** | Still `const WORKER_ID = 0n; const PROCESS_ID = 0n;`. No TODO comment. Fine for single-node Cove; flag the moment a second writer process exists. |
| **S6** (busy-spin in `snowflake.test.ts`) | ❌ Not Fixed | ❌ **Not Fixed** | `snowflake.test.ts` still has `while (Date.now() === start) { /* spin */ }`. Will be flaky on slow runners with coarse-clock OSes. Use `await new Promise(r => setTimeout(r, 2))` or `vi.useFakeTimers()`. |

---

## New Issues (R3 scope)

### N7. ℹ️ `getGuildId()` client cache: still no logout reset wiring
**File:** `packages/client/src/lib/api.ts`

`resetGuildId()` is exported but I still don't see it called anywhere in the diff. If the user logs out and a different user logs in within the same browser tab session, the cached `_guildId` from the first user is reused. Low-impact in Cove's single-guild model, but a foot-gun once multi-guild lands. Suggest wiring `resetGuildId()` into whichever path clears `localStorage.cove-token`.

### N8. ℹ️ Migration log lines go to `console.log` (stdout)
**File:** `packages/server/src/db/schema.ts` — `migrateV3ToV4()`

`console.log("Migration: messages 100 → 95 (5 orphans removed)")` — for a one-shot startup-time migration this is OK, but if Cove ever adopts structured logging (pino/winston), these will be noise. Acceptable for now; flagging only because the comment "see in deploy logs" is load-bearing for N1's correctness story.

### N9. ✅ Per-table idMap rename (R2 N1-adjacent) — looks correct
The shift from a shared `idMap` to per-entity maps (`guildIdMap`, `channelIdMap`, `userIdMap`, `messageIdMap`, `inviteIdMap`, `pendingIdMap`) eliminates the cross-table collision risk (e.g. a channel and user sharing a UUID — vanishingly unlikely, but the code is now defensively correct). The `update("messages", "channel_id", channelIdMap)` family of calls all reference the correct map for each FK column. Verified by reading lines 1273–1292 of the diff.

### N10. ✅ `MIN(messages.timestamp)` channel timestamp fallback (R2 C2 fix) — looks correct
The new logic in lines 1209–1224 of the diff prefers earliest message timestamp per channel, falls back to the guild's `created_at`, then `now`. Handles both numeric and ISO-string timestamps with `isNaN(parsed)` guard. Channel IDs now sort meaningfully relative to message IDs in `ORDER BY id DESC`. Correct.

### N11. ⚠️ `INSERT INTO messages_new ... WHERE channel_id IS NOT NULL` doesn't filter orphan `channel_id`
**File:** `packages/server/src/db/schema.ts` — `migrateV3ToV4()`, lines ~1357–1374

The recreate of `messages` filters `WHERE channel_id IS NOT NULL` and nulls out unknown `sender`s, but **does not** filter `WHERE channel_id IN (SELECT id FROM channels)`. If V2→V3 left any messages pointing at a non-existent channel (e.g. because the channel was deleted before the migration), the FK constraint will fail at the next startup. The R2-era follow-up commits (`fix: auto-clean orphan FK references...` then revert to `wipe staging DB instead`) suggest this was hit in practice. Symmetry with the `channels`/`read_states` recreates would be: `AND channel_id IN (SELECT id FROM channels)`. Currently relies on V2→V3 having been correct.

### N12. ℹ️ `addColumnIfMissing` referenced but not shown in diff
The diff calls `addColumnIfMissing(db, "users", "google_id", "TEXT")` and `addColumnIfMissing(db, "users", "email", "TEXT")` (lines 1331–1332), and similarly `tableExists`. Their definitions aren't in the diff hunk — assuming they exist elsewhere in `schema.ts`. Verified by absence-of-failure in tests; not a blocker, just calling out that I couldn't see the helper bodies.

---

## Positive Notes

- **C5 fully fixed** — the four message-pagination queries in `messages.ts` and the `last_message_id` lookup all dropped CAST. The index that R2 called "dead weight" is now load-bearing. Clean follow-through.
- **C2 fully fixed** — per-channel timestamp fallback chain (MIN(message.ts) → guild.created_at → now) preserves ID ordering across the migration boundary. This was non-trivial to get right.
- **N1 fixed with proper observability** — `before → after (N orphans removed)` is the right granularity for a one-shot migration. Operators can spot data loss immediately.
- **Per-table idMap split** — defensive against UUID-collision-across-entities. The right structure even though the practical risk was tiny.
- **Sensible commit arc on orphan handling** — author tried "auto-clean on startup", noticed that hid a real problem, reverted to "hard fail + wipe staging". That's the right instinct for an early-stage system.
- **`fix: resolve 'cove' guild alias to default guild ID`** — backwards-compat path for any external integrations still hardcoding "cove". Small touch, good thought.

---

## TL;DR for the author

R2 blockers (C2, C5, N1) are all resolved. What's left is cosmetic or pre-existing:

- **N2 email UNIQUE** — add `CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users(email) WHERE email IS NOT NULL` in V3→V4 so migrated and fresh DBs match.
- **N11** — consider `AND channel_id IN (SELECT id FROM channels)` in the messages recreate to mirror the `channels`/`read_states` filters and prevent future startup crashes.
- **S6** — replace the busy-spin in `snowflake.test.ts` with `setTimeout` or fake timers.
- **N7** — wire `resetGuildId()` into the logout path while it's fresh.
- **C3, S1** — cosmetic; ship-it.

**Verdict: ✅ Ready to merge.** Address N2 and N11 in a follow-up PR (or this one if quick); none are blockers.

— 🌠 Nova
