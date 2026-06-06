# Consolidated Review R3 — cove#248: OAuth token leak → BFF cookies

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)
**Round:** 3

## Round 2 Issue Resolution

| # | Issue | Status | Notes |
|---|-------|--------|-------|
| R2-1 | WS auth tests | ✅ Fixed | New `ws-auth.test.ts` (249 lines) — browser cookie, bot token, 4001/4004, malformed cookie. All 3 reviewers praise coverage quality |
| R2-2 | Legacy localStorage XSS | ✅ Fixed | `App.tsx` now removes `cove-token` + `cove-user` on mount |
| R2-3 | `NODE_ENV` / Secure flag | ✅ Fixed | `secure: NODE_ENV !== "development"` — safe by default |
| R2-4 | Register body fallback | ✅ Fixed | Cookie-only, `body.pendingToken` fully removed |
| R2-5 | WS token-fallthrough comment | ✅ Fixed | Clear inline comments explaining behavior |
| R2-6 | `/api/auth/me` duplicates `resolveUser` | ❌ Escalated 🟡 | **All 3 reviewers flagged** — see below |
| R2-7 | Stray blank line in `api.ts` | ❌ 🟢 | Cosmetic |
| R2-8 | CORS for cross-origin | ❌ 🟢 | Same-origin fine; document assumption |

**All 5 blocking items from R2 are resolved.** 🎉

## Remaining Issue

### 🟡 `/api/auth/me` should use `resolveUser` (3/3 reviewers, escalated from R2)

`routes/auth.ts:98-124` hand-rolls Authorization parsing (Bearer/Bot) + cookie fallback, duplicating what `auth.ts:resolveUser` already does. This is now the **third** place auth resolution lives (resolveUser, `/me`, WS verifyClient) — the WS one is justified (no hono context), `/me` is not.

**Fix (4 lines):** replace the manual parsing with:
```ts
const user = resolveUser(usersRepo, c.req.header("Authorization"), getCookie(c, SESSION_COOKIE));
if (!user) return c.json({ message: "Authentication required", code: 40001 }, 401);
return c.json({ id: user.id, username: user.username, avatar: user.avatar, bot: user.bot });
```

Nova: "Once R2-6 is addressed I'm a clean ✅."

## New Findings (all 🟢, non-blocking)

1. **Logout doesn't close WebSocket** (Stella) — After sign-out, the already-authenticated WS remains connected. Consider calling `disconnect()` in the logout flow. Not a token leak (cookies are cleared), but authenticated realtime traffic continues until page reload.

2. **Cookie attribute assertions missing** (Nova) — Tests check cookie *name* presence but never verify `HttpOnly`, `Secure`, `SameSite=Lax` attributes. One assertion per success path would lock the security contract against regressions.

3. **Local dev without `NODE_ENV=development`** (Stella) — `package.json` dev script doesn't set `NODE_ENV=development`, so local HTTP OAuth will reject Secure cookies. Add it to the dev script.

4. **Response inconsistency** (Nova) — Logout returns `{ message: "ok" }`, register returns `{ message: "registered" }`. Consider `204 No Content` or standardizing.

5. **WS valid cookie + invalid token = silent fallthrough** (Vega) — Behaviorally correct for browser clients (they send `null`), but an explicitly wrong token gets silently downgraded to cookie identity rather than 4004.

## Verdict

**⚠️ Needs Minor Changes** — 3/3 reviewers agree

The BFF security refactor is **complete and solid**:
- ✅ Token never in URL, localStorage, or JS-accessible surface
- ✅ `HttpOnly; Secure; SameSite=Lax` cookies
- ✅ WS pre-auth at upgrade
- ✅ Cookie-only register, no body fallback
- ✅ Bot backward compat preserved
- ✅ Comprehensive test coverage (HTTP + WS integration)

**One fix to merge:** refactor `/api/auth/me` to use `resolveUser` (4-line change, eliminates drift risk). After that → ✅ Ready.
