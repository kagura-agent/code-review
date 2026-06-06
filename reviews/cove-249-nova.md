# 🌠 Nova Review — cove#249 "weekend cleanup batch 1"

## 1. Summary

Three small, mostly orthogonal fixes batched into one PR (86+/60-, 8 files):

- **#210** — `register.ts` no longer inserts new users into the default guild on invite-code registration.
- **#187** — `GatewayDispatcher.removeUser(userId)` closes all live gateway sessions for a deleted user, then `DELETE /users/:id` calls it after DB delete.
- **#243** — Centralized 404/403 helpers (`unknownGuild`/`unknownChannel`/`unknownMessage`/`missingAccess`) in `routes/helpers.ts`, removed redundant per-route `requireAuth` (global middleware in `app.ts` already covers `/api/*` minus `PUBLIC_PATHS`), and replaced magic gateway opcode numbers in `useWebSocketStore.ts` with the shared `GatewayOpcode` enum.

Diff is mechanical and easy to read. Build + 150 tests pass per PR description.

## 2. Critical Issues

None blocking. Two things worth flagging before merge:

### C1. Newly registered users may end up stranded with no guild and no way in
After #210, a user who completes `/auth/register` with a valid invite code is created with **zero guild memberships**. The `invite_codes` schema (`packages/server/src/db/schema.ts:395`) has no `guild_id` column, so the invite itself does not place them in any guild. And `PUT /guilds/:guildId/members/:userId` (`agents.ts:130-150`) gates self-join behind `repos.members.exists(guildId, actingUserId)` — i.e. you must already be in the guild to add yourself. Net result: a fresh user has *no* API path to join any guild without an existing member adding them out-of-band.

This may be intentional for a personal/small-team server, but the PR body says "must join via invite", and there is no invite→guild linkage in this batch. Worth confirming before merging that this matches product intent, or noting a follow-up issue to either (a) attach `guild_id` to `invite_codes` and auto-join on register, or (b) ship a "guild invite" surface separate from account invite codes.

(For contrast: `routes/auth.ts:83-84` still ensures *existing* OAuth users get joined to the default guild on login. So the asymmetry is real and only affects brand-new accounts.)

### C2. `removeUser` correctness is fine, but the double-removal path is subtle
In `dispatcher.ts:179-189`:
```ts
removeUser(userId: string): void {
  const toRemove: GatewaySession[] = [];
  for (const session of this.sessions) {
    if (session.user?.id === userId) toRemove.push(session);
  }
  for (const session of toRemove) {
    this.removeSession(session);
    session.close(4004, "User deleted");
  }
}
```

`session.close()` ultimately triggers `ws.on("close")` in `ws/index.ts:140`, which calls `dispatcher.removeSession(session)` a second time. That second call is a no-op (already removed from `this.sessions` and `this.userSessions`), so it's safe — but worth a one-line comment because the next person to read it will wonder. Also, `session.user` is never cleared between calls, so if any future presence/broadcast logic reads `session.user` after `removeSession`, behavior is undefined. Today: harmless. Tomorrow: easy footgun.

Minor: order is `removeSession` then `close`. That means `PRESENCE_UPDATE offline` fires while the socket is still technically open, so the *dying* user's own session won't receive it (correctly excluded), and other members get it. ✅

## 3. Product Impact

- **#210 fix is user-visible and unambiguous**: a fresh sign-up no longer appears in the default guild's member list. Combined with C1, the practical UX is "user exists but can see nothing" until someone invites them. For a personal/small server this is fine; for any growth scenario this is a dead-end funnel.
- **#187 fix closes a real privacy/security gap**: previously, a deleted user could keep an open gateway session and continue to receive events. After this PR, deletion forcibly disconnects with code 4004 and broadcasts offline presence. Good.
- **#243 is pure cleanup** — no behavior change end-users will notice; small win for maintainability.

## 4. Suggestions

1. **(C1)** File a follow-up issue: "invite_codes should bind to a guild and register.ts should auto-join on consumption" — otherwise the regression in onboarding UX is real even if intentional for now.
2. **Add at least one regression test for #187**: spin up a fake `GatewaySession`, register two sessions for the same userId, call `removeUser`, assert (a) both sessions removed from `this.sessions`, (b) `PRESENCE_UPDATE offline` broadcast exactly once, (c) `session.close` called with `(4004, "User deleted")`. The dispatcher logic is exactly the kind of stateful code that silently regresses.
3. **Add a regression test for #210**: assert that after `/auth/register` the user has *zero* rows in `guild_members`. Cheap, locks the behavior.
4. **`agents.ts` leftover whitespace**: the removed `const auth = requireAuth(repos.users);` line was replaced with a blank line containing trailing whitespace. Strip it.
5. **`removeUser` micro-clarity**: rename the local to `victims` or add `// removeSession is idempotent vs. ws.on("close")` comment so the double-call is documented.
6. **`unknownX` helpers**: consider co-locating the Discord error code constants (`10003`, `10004`, `10008`, `50001`) into a small `ErrorCodes` enum in `@cove/shared` — same hygiene win as `GatewayOpcode`. Magic numbers in error helpers are still magic numbers, just in fewer places now.
7. **`PUBLIC_PATHS` in `app.ts`** (pre-existing, not this PR): mixes `/api/...` and `${API_PREFIX}/auth/register` (which is `/api/v10/...`). The inconsistency means the non-versioned `/api/auth/*` paths only work if those routes are mounted at `/api`, not at `API_PREFIX`. Worth a sanity check while you're in there, but out of scope.

## 5. Positive Notes

- Three issues, one focused PR, ~150 LOC net. Exactly the right scope for "weekend cleanup batch". 🎯
- `GatewayOpcode` substitution is the textbook example of how to retire magic numbers safely — enum already existed in `@cove/shared/types.ts`, just had to be imported and applied.
- Removing per-route `requireAuth` after centralizing it in `app.ts` is the right cleanup — eliminates a class of "did I remember to add auth here?" bugs.
- `removeSession` is called *before* `session.close` so `PRESENCE_UPDATE` broadcast happens while `session.guildIds` is still populated. The comment in `removeSession` even calls this ordering requirement out — good adherence to invariants.
- Invite-code consumption in `register.ts` is already race-safe via the conditional `UPDATE` inside the transaction (#209). Removing the default-guild insert didn't disturb that. ✅

## 6. Verdict

⚠️ **Approve with follow-ups** — code is correct and well-scoped; merge is safe. Two things to handle before/after:

- **Before merge**: confirm C1 matches product intent and file an onboarding-path follow-up issue if it doesn't. This is a behavior change that quietly breaks new-user funnel unless an existing member is around to add them.
- **After merge**: add regression tests for #210 (zero guild_members after register) and #187 (removeUser closes sessions + broadcasts offline). The dispatcher code in particular has no test coverage for this path and is exactly where silent regressions live.

Nice batch overall — small, mechanical, high signal-to-noise. 🌠
