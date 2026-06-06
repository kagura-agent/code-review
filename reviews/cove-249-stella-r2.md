# Stella R2 Review — kagura-agent/cove PR #249

## R1 Status

1. ✅ **OAuth auto-join existing users** — addressed. `auth.ts` no longer inserts existing OAuth users into the default guild, and invite-code registration no longer auto-joins new users.
2. ❌ **Regression tests for #210 / #187** — partially addressed only.
   - ✅ #210 has a new register regression test asserting zero `guild_members` rows.
   - ❌ #187 has a `removeUser` test, but its offline-presence assertion is inverted/weak: the comment says `sessionB` should receive offline presence, while the assertion checks it **does not**. Also `sessionB` is in a different guild, so this does not verify the required same-guild offline broadcast.
3. ❌ **`agents.ts` trailing whitespace** — still present at `packages/server/src/routes/agents.ts:10`.
4. ❌ **Unused `missingAccess()` helper** — still exported and unused at `packages/server/src/routes/helpers.ts:33`.
5. ❌ **No `unknownUser()` / `unknownMember()` helpers** — still not added; `agents.ts` still repeats literal Unknown User/Unknown Member JSON responses.

## New Issues

### 🟢 Weak/misleading #187 test assertion

`packages/server/src/__tests__/gateway.test.ts:226-227`:

```ts
// sessionB should receive offline presence for user-1
expect(sessionB.dispatch).not.toHaveBeenCalledWith("PRESENCE_UPDATE", expect.objectContaining({ status: "offline" }));
```

This contradicts the comment and does not test the intended behavior from #187. Because `sessionB` is only in `guild-b` while deleted user sessions are in `guild-a`, the assertion would pass even if `removeUser()` never broadcast offline presence to same-guild observers.

Suggested fix: add a third observer session in `guild-a`, then assert it receives:

```ts
expect(observer.dispatch).toHaveBeenCalledWith(
  "PRESENCE_UPDATE",
  { user: { id: "user-1" }, status: "offline" },
);
```

Keep a separate assertion that the deleted user's own closing sessions do not receive their own offline event if desired.

## Verification

Ran local CI-equivalent checks from PR branch:

```bash
pnpm -r build
pnpm -r exec tsc --noEmit
pnpm -r --filter @cove/server exec vitest run
```

Result: ✅ all passed (`152` server tests passed).

## Verdict

⚠️ **Functional blocker from R1 appears fixed, but R1 cleanup is not complete.**

I would not block on runtime behavior, but I would ask for one small follow-up before merge: fix the misleading #187 regression test so it actually proves same-guild offline broadcast, and clean up the remaining R1 nits if this PR is meant to close the full R1 list.
