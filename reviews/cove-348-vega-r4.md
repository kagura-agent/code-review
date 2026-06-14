# Code Review: PR #348 (Round 4) - Vega

## 1. R3 Issue Status
- **COALESCE regression**: ✅ Fixed. `global_name` was successfully removed from the existing-user OAuth UPDATE entirely. User-cleared names will now persist safely.
- **given_name length unbounded**: ✅ Fixed. Bounded to 80 characters during OAuth login.
- **Mention map keyed by non-unique display name**: ✅ Fixed / Not an issue. The map is correctly keyed by the unique `u.id` (`mentionUsers.set(u.id, u.global_name || u.username);`).
- **Optimistic self-message `global_name: null`**: ✅ Fixed. Now correctly defaults to `user.global_name ?? null`.
- **findByToken redundant cast**: ✅ Fixed. Cast removed.
- **Missing OAuth re-login test**: ❌ Not Fixed. No tests covering OAuth re-login were added. Escalate.
- **Missing resolveMentions test**: ❌ Not Fixed. No test for `resolveMentions` using `global_name` was added. Escalate.

## 2. New Issues
- None. The newly added validation and normalization logic in `agents.ts` and `validation.ts` handles edge cases well, including whitespace stripping and invalid characters.

## 3. Summary + Verdict
**❌ Major Issues (Escalated)**

The good news: all functional blockers and bugs from R3 have been cleanly resolved. The codebase looks solid functionally.

However, per our escalation rules, unaddressed issues from previous rounds must be escalated. The missing test coverage requested in R3 was completely ignored in this round. 

**Required before merge:**
1. Add an OAuth re-login test demonstrating that an existing user's `global_name` (whether set or explicitly cleared to `null`) is not overwritten when they log in again via OAuth.
2. Add a `resolveMentions` test ensuring that mentions resolve and utilize the `global_name` correctly.
