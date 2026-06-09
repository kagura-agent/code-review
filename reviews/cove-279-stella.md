# PR #279 Review — Stella

**Verdict:** Approved

## Summary

This is a small, focused fix for reaction-user pagination. The change correctly makes the cursor ordering deterministic by using `(created_at, user_id)` both in the `WHERE` cursor comparison and in `ORDER BY`, which prevents same-millisecond reactions from being skipped after the first page.

## Findings

No blocking issues found.

## Review Notes

- **Correctness:** The tuple comparison matches the new ordering, so pagination advances lexicographically from the cursor user's `(created_at, user_id)` pair. I also spot-checked the SQLite behavior with same-timestamp rows: after cursor `a`, the query returns `b,c` as expected instead of skipping `b`.
- **Security / input validation:** No new SQL injection risk; all cursor values remain parameterized. Existing route-level validation for emoji and limit remains unchanged.
- **Performance:** The query still filters by `message_id` and adds deterministic ordering. For very large reaction sets, a future composite index like `(message_id, emoji, created_at, user_id)` could help, but this PR does not introduce a practical blocker for the current scope.
- **Readability / API design:** The implementation is concise and keeps the public `after=<user_id>` API unchanged.
- **Testing:** Existing reaction/server tests pass locally. This PR would benefit from a targeted regression test with two users reacting in the same millisecond and `limit=1`, but the absence of that test is not a blocker for this small fix.

## Verification

- Reviewed PR title/body and diff via `gh pr view` / `gh pr diff`.
- Ran `pnpm -F @cove/server test -- src/__tests__/reactions.test.ts` successfully.
- Ran a direct SQLite tuple-comparison smoke test for same-millisecond rows.
