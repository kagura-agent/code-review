# 🌠 Nova — Review of cove#279

**PR:** fix: use tuple comparison for reaction pagination cursor
**Closes:** #273
**Files changed:** 1 (`packages/server/src/repos/reactions.ts`)
**Verdict:** ✅ **Approve (with one nice-to-have)**

---

## Summary

The PR fixes a real bug in `ReactionsRepo.getUsersForReaction`. The previous query
used `r.created_at > (SELECT created_at …)` for cursor pagination. When two
reactions share the same `created_at` (same-millisecond inserts, or batched
clock-tied inserts), the strict `>` comparison drops the page tail’s siblings,
producing an unstable / lossy cursor.

The fix moves to SQLite row-value (tuple) comparison:

```sql
(r.created_at, r.user_id) > ((SELECT created_at …), ?)
ORDER BY r.created_at, r.user_id
```

with `user_id` as the deterministic tie-breaker. This matches the well-known
keyset pagination idiom and is the right fix.

---

## Correctness ✅

- **Tuple comparison support.** SQLite supports row-value comparison since
  3.15.0 (2016). better-sqlite3 ships a modern SQLite, so this is safe.
- **ORDER BY now matches cursor key.** `(created_at, user_id)` is deterministic
  given the table’s PRIMARY KEY `(message_id, user_id, emoji)` (so `user_id` is
  unique within a `(message_id, emoji)` slice). No more skipped or duplicated
  rows at page boundaries.
- **Param order is correct.** `params.push(messageId, after, emoji, after)` —
  the first three feed the subquery (`message_id`, `user_id`, `emoji`), the
  trailing `after` becomes the right-hand `user_id` of the tuple. Verified
  against the SQL.
- **Subquery NULL behavior is unchanged from baseline.** If the `after` user has
  no reaction on this message, the subquery returns NULL; the tuple compare
  evaluates to NULL (falsy) and zero rows are returned. The pre-fix code had
  the same property (`r.created_at > NULL` → no rows), so this is not a
  regression. Worth noting, but out of scope for this PR.

## Performance ✅

- The only relevant index is `idx_reactions_message_id`. Since the query is
  always filtered by a single `message_id` and (typically tiny) emoji set,
  cardinality is small; the added `ORDER BY user_id` tie-break is essentially
  free.
- For very hot messages a covering index `(message_id, emoji, created_at,
  user_id)` would help, but that is a separate optimization and not blocking.

## API / Interface Design ✅

- The wire-level `after` cursor is still just `user_id`. The server resolves
  the timestamp from the DB. That keeps the API stable and avoids leaking an
  internal compound cursor — good call.

## Security ✅

- Parameterized; no injection risk introduced.
- No authorization change.

## Testing ⚠️ (non-blocking nit)

- No regression test was added. The bug class is easy to lock in:

  ```ts
  // insert two reactions on the same message+emoji with the SAME created_at
  // page with limit=1, after=<first user>, assert second user returned
  ```

  Given `getUsersForReaction` is reachable from `reactions.test.ts`, adding a
  ~15-line same-millisecond pagination test would prevent future regressions
  (e.g. someone reverting the `ORDER BY` clause). Not a merge blocker for a
  small team / personal project, but strongly recommended as a follow-up
  commit before merge if cheap.

## Readability ✅

- One-line SQL change, intent obvious. The PR description explicitly calls out
  the deterministic-ordering / tuple-comparison reasoning. Good.

---

## Suggested follow-ups (optional)

1. Add a same-millisecond pagination regression test (cheap, high signal).
2. Consider a covering index `(message_id, emoji, created_at, user_id)` if
   reaction lists ever get hot enough to matter. Not for this PR.

## Final call

The fix is correct, minimal, and on-pattern for keyset pagination. Ship it; the
test is the only thing I’d push back on, and it is non-blocking.
