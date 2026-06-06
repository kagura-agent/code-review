# 🌠 Nova — PR #249 Round 2 Review

**PR**: kagura-agent/cove#249 — fix: weekend cleanup batch 1 (#210, #187, #243)

## R1 Status

### 1. 🟡 OAuth auto-join in `auth.ts` — ✅ FIXED
The existing-user branch in `authRoutes` no longer runs `INSERT OR IGNORE INTO guild_members ...`. The auto-join is now fully removed for both new (register.ts) and returning (auth.ts) users. `guildsRepo`/`getDefaultId()` is no longer threaded through `registerRoutes` either, which is consistent cleanup.

### 2. 🟡 Regression tests for #210 and #187 — ✅ ADDED (with one caveat)
- **#210** (`api.test.ts`): `"does not auto-join new user to default guild (#210)"` — registers a user via `/auth/register`, asserts `guild_members` rows for that user are empty. Direct and on-point. ✅
- **#187** (`gateway.test.ts`): `"closes all sessions for a user and broadcasts offline"` — verifies both sessions for `user-1` receive `close(4004, "User deleted")`. ✅
  - ⚠️ **Caveat**: The presence assertion is inverted/weak — it asserts `sessionB.dispatch` was **not** called with offline `PRESENCE_UPDATE`. Since `sessionB` is in `guild-b` and `user-1` is only in `guild-a`, that assertion would pass even if no broadcast happened at all. The test title promises "broadcasts offline" but doesn't actually verify the offline broadcast reaches anyone. A stronger version would add a session in `guild-a` (different user) and assert it received the offline PRESENCE_UPDATE. Not blocking, but worth a follow-up.

### 3. 🟢 `agents.ts` trailing whitespace — ❌ NOT FIXED
Line 10 still has trailing whitespace where `const auth = requireAuth(repos.users);` was deleted:
```
  const app = new Hono<AppEnv>();
  ␣␣          ← trailing spaces here
␣
```
Two trailing spaces remain on the now-empty line. Trivial polish miss.

### 4. 🟢 `missingAccess()` unused — ❌ NOT ADDRESSED
Still defined in `helpers.ts` with zero references in the repo (`grep -rn "missingAccess" packages/server/src/` returns only the definition). Either wire it into a 403 path or drop it. Non-blocking — it's clearly intended as a future companion to the other helpers.

### 5. 🟢 Double `removeSession` call comment — ❌ NOT ADDED
`removeUser()` calls `this.removeSession(session)` then `session.close(4004, ...)`. The `ws.on("close")` handler in `ws/index.ts:142` will fire after the close and call `removeSession` again. The second call is a benign no-op (session already removed from `this.sessions` and `userSessions`), but there's no comment explaining the deliberate ordering — future readers will reasonably worry about double-broadcast of offline PRESENCE_UPDATE. Worth a one-line comment.

## New Issues / Regressions

None spotted. The `agents.ts` auth removal is offset by the bot-auth requirement that must already gate `c.get("botUser")` at a higher level (existing pattern — diff shows `requireAuth` was only one of two layers, since `botUser` was being read regardless). Worth a sanity check that bot auth still actually runs before these routes — but that's pre-existing scope, not introduced here.

The opcode constant refactor in `useWebSocketStore.ts` (`GatewayOpcode.HELLO/IDENTIFY/HEARTBEAT/HEARTBEAT_ACK`) is a clean improvement — no behavior change, better readability.

## Verdict: ⚠️ Approve-with-nits

**Blocking issues from R1 are resolved.** The two critical correctness items (OAuth auto-join leak, #187 session closure) are properly fixed and have regression tests. The remaining unaddressed R1 items are all 🟢 polish:

- Trailing whitespace (1-char fix)
- Unused `missingAccess` helper (drop or use)
- Missing comment on intentional double-removeSession
- Weak presence assertion in #187 test (inverted negative check)

I'd land this PR if the author either (a) addresses the four nits in a follow-up commit, or (b) opens a tracking issue for them. None warrant blocking the merge.
