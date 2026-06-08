# 🌟 Stella — R3 Re-Review: kagura-agent/cove#272 "feat: emoji reactions"

**Round:** 3  
**Verdict:** ⚠️ Needs Changes — all R2 blockers are addressed, but R3 found one new pagination correctness bug before merge.

---

## R2 Issue Status

### 🔴 Must Fix

1. **Client count drift for other users** — ✅ Fixed
   - Server gateway payloads now include authoritative absolute `count` for both add/remove events (`packages/server/src/ws/dispatcher.ts`).
   - Client store now replaces the reaction count with the event payload value instead of doing `count + 1` / `count - 1` locally (`packages/client/src/stores/useMessageStore.ts:90-127`).
   - Duplicate/replayed events for other users therefore converge to the same count instead of drifting upward/downward.

2. **`getUsersForReaction` unbounded + N+1** — ✅ Fixed
   - Route parses bounded `limit` with default 25 and max 100, plus `after` cursor (`packages/server/src/routes/reactions.ts:79-82`).
   - Repo uses one joined query against `reactions` + `users`, no per-user `getById` loop (`packages/server/src/repos/reactions.ts:83-98`).

### 🟡 Should Fix

3. **LRU eviction bug** — ✅ Fixed
   - Re-adding an existing id now deletes it first to refresh recency and only evicts when inserting a genuinely new id at capacity (`packages/plugin/src/channel.ts:30-38`).

4. **React key collision** — ✅ Fixed
   - Reaction pill key now uses `r.emoji.id ?? r.emoji.name` (`packages/client/src/components/MessageItem.tsx:87-90`).

5. **Auto-scroll over-fires on any reaction anywhere** — ✅ Fixed
   - Effect now derives a primitive key from only the last message id + total reaction count (`packages/client/src/components/MessageList.tsx:86-96`), so reaction updates on older messages no longer change the dependency.

---

## Fresh R3 Findings

### 🟡 S1. Reaction user pagination can skip users with the same millisecond timestamp

`getUsersForReaction` orders and pages only by `r.created_at`:

- `packages/server/src/repos/reactions.ts:90-95`

```ts
if (after) {
  query += ` AND r.created_at > (SELECT created_at FROM reactions WHERE message_id = ? AND user_id = ? AND emoji = ?)`;
}
query += ` ORDER BY r.created_at LIMIT ?`;
```

Because `created_at` comes from `Date.now()` (`packages/server/src/repos/reactions.ts:17-20`), multiple reactions can share the same millisecond. If page 1 ends at user A with `created_at = 1000`, page 2 uses `created_at > 1000`, so any other users reacted in the same millisecond after A are permanently skipped. The ordering is also nondeterministic for equal timestamps.

**Product impact:** reactor popovers/lists can silently omit users under bursty reactions, exactly where pagination matters most.

**Suggested fix:** make the cursor ordering stable with a tie-breaker, e.g. `ORDER BY r.created_at, r.user_id`, and page with tuple semantics:

```sql
AND (
  r.created_at > :afterCreatedAt
  OR (r.created_at = :afterCreatedAt AND r.user_id > :afterUserId)
)
```

Add a test where 3+ users share the same `created_at`, request `limit=1`, and verify all users are reachable across pages.

### 🟢 S2. Add a composite index for the reaction user-list query

The new user-list query filters by `(message_id, emoji)`, orders by `created_at`, and limits (`packages/server/src/repos/reactions.ts:83-98`), but the migration only adds `idx_reactions_message_id` (`packages/server/src/db/migrations/v7-reactions.ts:13`). For popular messages with multiple emoji, SQLite may scan/sort more rows than needed.

**Suggested index:**

```sql
CREATE INDEX IF NOT EXISTS idx_reactions_message_emoji_created
ON reactions(message_id, emoji, created_at, user_id);
```

This pairs naturally with the stable pagination fix above.

---

## Positive Notes

- The absolute-count gateway design is the right fix for client drift; much safer than local counter math.
- The R2 N+1 fix is clean: one joined query and route-level limit clamping.
- Reaction list integration into `MessagesRepo.list()` uses batch aggregation, avoiding a per-message reaction query.
- Tests cover the core route/repo behavior and cascade delete paths.

---

## Recommendation

⚠️ **Needs small changes before merge.** The R2 blockers are resolved, but please fix the `after` pagination tie-breaker before shipping the reactor-list endpoint. The index can be done alongside it and is cheap while the migration is still fresh.
