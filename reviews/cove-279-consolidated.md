# Consolidated Review R1 — cove#279: tuple comparison for reaction pagination

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)
**Round:** 1

## Verdict: ✅ Ready to Merge (3/3 Approve)

Clean, focused fix. No blocking issues found by any reviewer.

---

## Summary

The PR fixes cursor pagination for `getUsersForReaction` — reactions created in the same millisecond were skipped because the cursor only compared `created_at`. The fix adds `user_id` as a deterministic tie-breaker using SQLite tuple comparison:

- **ORDER BY** `(created_at, user_id)` — deterministic ordering
- **Cursor** `(r.created_at, r.user_id) > (cursor_ts, cursor_uid)` — no same-millisecond skips

This is the textbook keyset-pagination idiom. SQLite has supported row-value tuple comparison since 3.15.0 (2016). (Nova)

## Correctness ✅ (3/3 consensus)

- Tuple comparison correctly evaluates to `created_at > cursor_ts OR (created_at = cursor_ts AND user_id > cursor_uid)` (Vega)
- `user_id` is a valid tie-breaker — the reactions table PK `(message_id, user_id, emoji)` guarantees uniqueness within any `(message_id, emoji)` slice (Nova)
- ORDER BY matches the cursor key — no skipped/duplicated rows at boundaries (Nova)
- Stella smoke-tested same-millisecond rows in SQLite directly ✅

## Security ✅ (3/3)

All cursor values remain parameterized. No SQL injection risk.

## API Design ✅ (3/3)

Wire-level `after` cursor stays as just `user_id`; server resolves the timestamp via subquery. No API break.

## 💡 Suggestions (non-blocking)

- **Regression test:** A ~15-line same-millisecond pagination test in `reactions.test.ts` (two users reacting simultaneously, `limit=1`) would lock this in cheaply. (Stella, Nova)
- **Deleted cursor edge case:** If the `after` user's reaction is deleted before the next page fetch, the subquery returns NULL → 0 rows. Pre-existing behavior, no regression — just worth knowing. (Vega, Nova)
- **Future index:** For very large reaction sets, a composite index `(message_id, emoji, created_at, user_id)` could help. Not needed at current scale. (Stella)

## ✅ Positive Notes

- Minimal, surgical fix — exactly what it should be
- Existing server/reaction tests pass (Stella verified locally)
- Clean SQL, easy to understand
