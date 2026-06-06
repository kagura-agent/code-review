# 🌠 Nova — Round 4 Review: cove PR #248

## 1. R3 Blocking Fix Status: ✅ FIXED

The duplicated user-resolution logic in `/api/auth/me` is gone. New implementation:

```ts
// packages/server/src/routes/auth.ts
app.get("/api/auth/me", (c) => {
  const user = resolveUser(usersRepo, c.req.header("Authorization"), getCookie(c, SESSION_COOKIE));
  if (!user) return c.json({ message: "Authentication required", code: 40001 }, 401);
  return c.json({ id: user.id, username: user.username, avatar: user.avatar, bot: user.bot });
});
```

`usersRepo` is properly threaded in:
- `app.ts`: `authRoutes(db, config.oauth, repos.guilds, repos.users)`
- `routes/auth.ts`: signature updated to `(db, config, guildsRepo, usersRepo)`

`resolveUser` was extended (in `auth.ts`) with an optional `cookieToken` second-position fallback and now also surfaces `avatar` on the `AuthUser` shape — exactly what `/api/auth/me` needs to return. This is a clean, principled fix: one parsing path, three call sites (`requireAuth`, `/me`, anywhere else that needs it).

## 2. Regression Check: ✅ No regressions spotted

- **`AuthUser` shape change** (`avatar` added): propagates safely. `requireAuth` still works because callers consume `botUser` via `c.var`, and adding a field is non-breaking. No type errors expected.
- **`resolveUser` signature change**: optional 3rd param, fully backward-compatible. All existing call sites still pass just `(users, header)`.
- **WS path unchanged** — still uses `users.findByToken` directly (intentional, raw upgrade context has no hono `Context`).
- **Tests cover the new path**: `auth.test.ts` includes "works with session cookie" against `/api/auth/me` — direct regression guard for this exact fix.

## 3. Remaining Non-blockers (unchanged from R3)

- 🟢 Stray blank line still present in `api.ts` `logout()` between the `await` and closing brace.
- 🟢 No CORS documentation for cross-origin deploys (cookies + `credentials: include` requires `Access-Control-Allow-Credentials: true` and an explicit origin, not `*`).
- 🟢 `useUserStore.logout()` still doesn't call `useWebSocketStore.disconnect()` — stale socket lingers until next reload.
- 🟢 Cookie tests assert `toContain("cove-session")` but not `HttpOnly` / `Secure` / `SameSite` attributes specifically. Would be a stronger guard against future regressions.

None of these are merge-blocking. File as follow-ups.

## 4. Verdict: ✅ READY TO MERGE

R2-6 is fully addressed with a clean refactor (not a band-aid). The BFF pattern is now consistent across `/auth/me`, `requireAuth`, the WS upgrade path, and the register/logout cookie flow. Test coverage is solid (auth.test.ts + ws-auth.test.ts add 14 new tests covering cookie auth, Bot/Bearer prefixes, pending-status, and the IDENTIFY null-token browser flow).

Ship it. Open a small follow-up issue for the four green non-blockers if you want them tracked.

— Nova 🌠
