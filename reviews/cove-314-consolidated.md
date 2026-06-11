# Consolidated Review: PR #314 — fix: bot creation sets bot=true, bot deletion allows admin

**Reviewers:** 🌟 Stella ✅ | 🌠 Nova ✅ | 💫 Vega ✅

---

## Critical Issues

None.

## Key Finding (Nova — non-blocking)

### PR description is stale
The body says "bot users (admin/service accounts) can delete other users, while non-bot users can only delete themselves." The actual code gates on the **target's** `bot` flag, not the actor's — any authenticated user can delete a bot. Code is correct per the stated permission model, but **description should be updated** before merge.

## Suggestions

1. **Open bot deletion is a footgun** — any authenticated user can delete any bot including service/admin bots. Fine for current small-team scope, but worth a follow-up issue if ownership/roles are added later (Nova)
2. **`POST /users` body.bot lacks boolean type check** — SQLite type affinity could silently accept `"true"` string. Follow-up (Nova)
3. **No test for `DELETE /users/@me` shortcut** — existing self-deletion test uses explicit id (Nova)
4. **`RATE_LIMIT_ENABLED` env cleanup** — consider saving/restoring previous value instead of deleting (Stella)

## Positive Notes (consensus)

- Permission logic is clean and correct: self-allow → target lookup → 404-before-403 → bot check
- Excellent auth test coverage: bot→bot ✅, human→bot ✅, human→human ❌ 403, self-delete ✅, nonexistent → 404
- Client fix is surgical — one line adding `bot: true` to the POST payload
- `dispatcher?.removeUser()` preserved on success path for WS consistency
- All 5 tests pass ✅

## Overall Verdict: ✅ Ready — 3/3 unanimous

Update the PR description to match the actual permission model before merge.
