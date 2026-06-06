# PR #249 Review — Stella

## 1. Summary

PR #249 is a small, mostly mechanical cleanup that:
- Removes the default-guild insert from the invite-code registration path.
- Adds `GatewayDispatcher.removeUser()` and calls it after account deletion.
- Centralizes several Discord-style error helpers.
- Removes duplicate per-route auth middleware where global `/api/*` auth already applies.
- Replaces client gateway opcode magic numbers with `GatewayOpcode`.

The cleanup direction is good, and the diff is easy to follow. However, I found one auth/access-control gap that means the “no implicit default guild membership” behavior is still not fully enforced.

Verification I ran locally:
- `pnpm -r build` ✅
- `pnpm -r exec tsc --noEmit` ✅
- `npm test` / targeted Vitest attempts were blocked by local native-module environment failure: `better-sqlite3` reported `Module did not self-register` under Vitest. Direct `node -e "require('better-sqlite3')"` works, so I’m not treating this as a PR failure, but I could not independently confirm the claimed 150/150 tests locally.

## 2. Critical Issues

### 2.1 Existing OAuth login still silently re-adds users to the default guild

**Severity:** High — auth/access-control / product correctness  
**Files:**
- `packages/server/src/routes/register.ts:50-52` removes auto-join for new invite registration ✅
- `packages/server/src/routes/auth.ts:78-84` still auto-joins existing OAuth users ❌

The PR fixes the new-registration transaction by removing the `guild_members` insert, but the OAuth callback still does this for any existing user:

```ts
// Ensure user is in default guild
db.prepare("INSERT OR IGNORE INTO guild_members ...")
  .run(guildsRepo.getDefaultId(), existing.id, null, "[]", now);
```

That means a user who has no guild memberships — for example because they left the default guild, were removed from it, or were created under the new “empty guild list” behavior and later hit the existing-user OAuth path — can be silently granted default-guild access just by logging in again.

This conflicts with #210’s principle: guild membership should be explicit and user-initiated, never automatic. It also makes membership removal non-durable, which is an access-control concern.

**Recommended fix:** Remove the existing-user default-guild insert in `auth.ts` as well. If there is a compatibility reason to keep it for legacy seeded/admin users, gate it behind an explicit migration/backfill path instead of login-time behavior.

**Regression tests to add:**
1. Register a new user with a valid invite code, authenticate with the new session, and assert `GET /users/@me/guilds` returns `[]`.
2. Seed an existing OAuth user with no `guild_members` rows, run the OAuth callback path, and assert no default membership is inserted.
3. Optional legacy test: an existing user who already has a guild membership keeps it after login.

## 3. Product Impact

- **New-user onboarding:** The main registration path now creates users without automatically adding them to the default guild, which matches the intended Discord-like mental model.
- **Guild access semantics:** The remaining OAuth auto-join path can still surprise users/admins by restoring default-guild access after it was removed. This is the main reason I would not merge as-is.
- **Account deletion:** Closing active gateway sessions on deletion is the right product behavior; deleted users should not keep receiving guild events until the socket naturally dies.
- **Developer experience:** Centralized error helpers and opcode enum usage improve readability without changing API shape.

## 4. Suggestions

1. **Add tests for the behavior changes.**  
   The PR body says tests pass, but I don’t see targeted coverage for the two riskiest behavioral changes: “registered users have no guilds” and “deleted users’ WS sessions close.” For a cleanup batch touching auth/session behavior, these regressions are worth locking down.

2. **Test `removeUser()` with multiple sessions.**  
   Add a dispatcher unit test that creates two sessions for the same user, calls `removeUser(userId)`, and asserts:
   - both sessions are closed with code `4004`,
   - the user is removed from online presence,
   - one offline presence update is emitted to shared guild members.

3. **Consider making dispatcher removal order explicit.**  
   Current `removeUser()` calls `removeSession(session)` before `session.close(4004, ...)`. That works with the current dispatcher implementation and avoids stale sessions immediately, but a short comment would help future maintainers understand why close-triggered cleanup may run a second time and why that is safe/idempotent.

4. **Remove or use `missingAccess()`.**  
   `missingAccess()` is added in `routes/helpers.ts` but not used in this diff. It’s harmless, but either using it where appropriate or leaving it for the next cleanup PR would keep the helper surface tighter.

5. **Optional: centralize `unknownUser()` / `unknownMember()` too.**  
   The new helpers cover guild/channel/message/access, while user/member errors remain inline. Not a blocker, just a consistency follow-up.

## 5. Positive Notes

- The removal of per-route `requireAuth` in `channels.ts` and `agents.ts` is appropriate because `app.ts` already applies global auth to `/api/*` except public paths.
- `GatewayOpcode` in the client makes the WebSocket handshake much clearer and less brittle.
- The error helper extraction reduces noisy repetition without introducing a large abstraction.
- `removeUser()` snapshots sessions before closing/removing, avoiding mutation while iterating the live `Set`.
- The diff is small and reviewable, which is exactly right for this kind of cleanup batch.

## 6. Verdict: ⚠️ Request changes

Good cleanup overall, but please fix the remaining login-time default-guild auto-join in `auth.ts` before merging. Because this touches auth/access control and can silently restore guild access, I would treat it as a merge blocker for #210.
