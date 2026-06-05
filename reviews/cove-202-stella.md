# Review: kagura-agent/cove PR #202 — Round 3 re-review

## R2 Issue Status

1. **C3 ❌ `CAST(id AS INTEGER)` bypasses the index — ✅ Fixed**
   - `packages/server/src/repos/messages.ts:45-60` now uses plain `m.id < ?`, `m.id > ?`, and `ORDER BY m.id ...` for all pagination paths.
   - `packages/server/src/repos/readStates.ts:31` now uses `ORDER BY m.id DESC` for the latest-message subquery.
   - I verified with `EXPLAIN QUERY PLAN` against the current query shapes: SQLite can use `idx_messages_channel_id (channel_id, id DESC)` for the channel filter, range predicate, and order. The previous temp B-tree caused by `CAST(...)` is gone.

2. **N1 🟡 Global `idMap` collision across tables — ✅ Fixed**
   - `packages/server/src/db/schema.ts:74-81` now creates per-entity maps (`guildIdMap`, `channelIdMap`, `userIdMap`, `messageIdMap`, `inviteIdMap`, `pendingIdMap`).
   - Foreign-key rewrites now choose the referenced entity map explicitly at `packages/server/src/db/schema.ts:174-185`, so a channel and user with the same legacy text ID no longer share/overwrite one mapping.
   - I would still like a regression test for the same legacy string present in two entity tables, but the implementation direction addresses the R2 corruption risk.

3. **N2 🟡 Message pagination expanded `CAST` problem — ✅ Fixed, with a new semantic caveat below**
   - The expanded pagination queries at `packages/server/src/repos/messages.ts:45-60` no longer use `CAST(...)`, so the index-bypass part of N2 is fixed.
   - However, replacing numeric comparison with raw TEXT comparison introduces a new ordering correctness issue for non-fixed-width Snowflakes; see New Issue S3-N1.

4. **N3 🟡 Bot/user creation can still mint non-Snowflake IDs — ❌ Not Fixed / escalated**
   - `packages/server/src/repos/users.ts:36` still defaults new user IDs to a username slug.
   - `packages/server/src/routes/agents.ts:12-31` still accepts arbitrary `body.id` and passes it through to `repos.users.create()`.
   - This remains inconsistent with the migration goal that entity IDs become Snowflakes. It also interacts badly with the new raw TEXT ID comparisons if any API-created user/message/read-state path ever stores non-Snowflake IDs.

5. **Nova: V3→V4 silent orphan row drops need logging — ✅ Fixed**
   - `packages/server/src/db/schema.ts:267-268`, `:292-293`, and `:316-317` now log before/after counts and the number of orphan rows removed for messages, channels, and read_states.

6. **Nova: Channel migration timestamps all use `now` — ✅ Fixed**
   - Channel Snowflake generation now derives a timestamp from the earliest message in the channel, then falls back to the guild `created_at`, and only then to `now` (`packages/server/src/db/schema.ts:98-119`).
   - This preserves substantially better ordering than the previous all-`now` fallback.

7. **Nova: `email` column lacks UNIQUE — ⚠️ Partially Fixed**
   - Fresh databases are fixed: `users.email` is declared `TEXT UNIQUE` in `packages/server/src/db/schema.ts:356`.
   - Existing databases are still not fixed: V3→V4 adds `email` as plain `TEXT` at `packages/server/src/db/schema.ts:224`, but only creates `idx_users_google_id` at `:225`; there is no `CREATE UNIQUE INDEX ... ON users(email)` for migrated DBs. So upgraded installations still permit duplicate email values even though fresh installations do not.

## New Issues

### S3-N1 — High: raw TEXT ordering is not numerically correct for Snowflakes with different digit lengths

The CAST removal fixed the index plan, but the new comparisons assume Snowflake strings are fixed-width decimal strings. They are not. Snowflakes generated before roughly 2022-07-22 are 18 digits, while current 2026 Snowflakes are 19 digits. SQLite TEXT ordering therefore sorts some older IDs after newer IDs, because e.g. `'794354201395200000' > '1456074443980800000'` lexicographically even though it is numerically smaller.

Affected code:
- `packages/server/src/repos/messages.ts:45-60` — `before`, `after`, `around`, and default pagination all use raw TEXT range/order comparisons.
- `packages/server/src/repos/readStates.ts:16-20` — the monotonic ACK guard uses `>=` on TEXT IDs and the comment explicitly says the IDs are fixed-width.
- `packages/server/src/repos/readStates.ts:31` — latest message uses `ORDER BY m.id DESC` on TEXT.

Why this matters here: `migrateV2ToV3()` preserves legacy row timestamps in the Snowflake timestamp bits (`packages/server/src/db/schema.ts:90-135`). Any migrated message/user data dated before the 18→19 digit boundary can be misordered against newer generated data. The current pagination tests only use same-length toy IDs (`1000000 + i`), so they do not catch this.

Possible fixes: store IDs in an INTEGER-sortable column, create/use an expression index on `CAST(id AS INTEGER)` if staying with TEXT, left-pad Snowflake strings to fixed width before storage, or constrain migration/new IDs so all stored Snowflakes share the same width and document/enforce that invariant. As-is, this is a correctness regression from the previous numeric `CAST` behavior.

### S3-N2 — Medium: `resetGuildId()` is added but never called on logout

`packages/client/src/lib/api.ts:29-38` caches the first guild ID globally and exposes `resetGuildId()`, but `packages/client/src/stores/useUserStore.ts:24-28` logs out by clearing localStorage and Zustand state only. A same-tab logout/login as another user can keep using the previous user's cached guild ID for `fetchChannels()`, `createChannel()`, and `fetchMembers()` (`packages/client/src/lib/api.ts:42-68`).

Server-side membership checks may turn some of this into 404s, but it is still stale identity-scoped state in the client and will be confusing after account switches.

## Summary & Verdict

Round 3 fixes several important items: the `CAST(...)` index bypass is removed, the migration now uses per-table ID maps, orphan drops are logged, and channel migration timestamps are much better than all-`now`.

I still would not merge yet. One R2 item remains unaddressed (new bot/user IDs can still be arbitrary text), migrated DBs still lack the email uniqueness constraint, and the CAST removal introduced a fresh correctness bug: raw TEXT ordering is not numerically correct for Snowflakes across digit-length boundaries.

**Rating: ⚠️ Needs Changes**
