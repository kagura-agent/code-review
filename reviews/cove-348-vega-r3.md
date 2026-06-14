# Vega - Code Review Round 3 - PR #348

## 1. R2 Issue Status

- ✅ **CI webhook shell injection:** Fixed. `env` and `jq --arg` correctly protect against shell injection and command substitution.
- ✅ **OAuth `given_name` not validated:** Fixed. `validateDisplayName` is now correctly applied to `googleUser.given_name` in auth flows.
- ❌ **Existing user re-login (COALESCE issue):** Not Fixed. You brought `COALESCE(global_name, ?)` back! If a user explicitly clears their `global_name` (setting it to `null`), `COALESCE(null, givenName)` evaluates to `givenName`. This means their cleared name gets overwritten by Google's `given_name` on their next login. This is the exact bug flagged in R1. Do not update `global_name` on re-login for existing users.
- ❌ **Stella's issue - Mention map keyed by non-unique display name:** Not Fixed. `MessageInput.tsx` was untouched. `mentionMapRef.current.set(displayName, userId)` still uses the non-unique display name as the key. If two users have the same display name, the second overwrites the first in the map, breaking mentions.
- ❌ **Stella's issue - Optimistic self-message ignores current `global_name`:** Not Fixed. `MessageInput.tsx` still hardcodes `global_name: null` in the pending message author object instead of reading `user.global_name`.
- ❌ **Nova S3 - `findByToken` redundant/incorrect cast:** Not Fixed. `SELECT id, username, avatar, bot, bio, global_name, expires_at` is cast to `UserRow`, but it's missing required `UserRow` fields like `token`, `created_at`, `updated_at`.
- ❌ **Missing Tests:** Not Fixed. Still no tests for OAuth re-login `global_name` preservation or `resolveMentions`.

## 2. New Issues
- No new regressions were spotted in the new code, but the reversion to `COALESCE` in OAuth is a major blocker.

## 3. Summary + Verdict
**❌ Major Issues**

The PR unfortunately re-introduced the exact bug from R1 regarding OAuth logins, and completely ignored the unaddressed issues from R2. Per the escalation rule, unaddressed issues must be flagged as blocking. 

**Required Fixes for R4:**
1. Remove `global_name = COALESCE(...)` entirely for existing users in `authRoutes`.
2. Fix `MessageInput.tsx` so mentions don't collide when display names match.
3. Fix the optimistic message author to use `useUserStore.getState().global_name` in `MessageInput.tsx`.
4. Fix the TypeScript cast in `findByToken`.
5. Add the requested tests.