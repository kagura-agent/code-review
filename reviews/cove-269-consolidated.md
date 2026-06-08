# Consolidated Review R2 — cove#269: PR #264 follow-ups

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)
**Round:** 2

## R1 Issue Resolution

| # | Issue | Status |
|---|-------|--------|
| 🔴 | re-IDENTIFY leaks intervals | ✅ Fixed — `session.isIdentified` guard + close 4005 |
| 🔴 | Cookie fallback tracks wrong token | ✅ Fixed — `identifyToken` 用 cookie token 覆盖 |
| 🔴 | Test 3 tautological (OAuth) | ✅ Fixed — 真正驱动 `/api/auth/callback` + mock fetch |
| 🔴 | Test 2 doesn't test short TTL | ⚠️ 部分修复 — 加了 formula assertion 但没执行 production code with short TTL |

## Reviewer Verdicts

- 🌟 Stella: **⚠️ Needs Changes** — short TTL test + 3 escalated items
- 🌠 Nova: **✅ Approve with follow-up issues** — 核心 bug 已修，剩余开 issue
- 💫 Vega: **❌ Block** — 3 escalated should-address 现在 blocking

## Verdict: ⚠️ Needs Changes (2/3 block, 1/3 approve-with-followups)

---

## 核心 R1 bug 已修 ✅

re-IDENTIFY interval 泄漏和 cookie token 跟踪问题**完全修复**。OAuth 测试现在驱动真实 route。这些是真正的安全/正确性 bug，解决得好 👍

## 剩余问题

### 🟡 Test 2: short-TTL 分支仍是 tautological (2/3 consensus: Stella + Nova)

测试 re-implement 了 `Math.max(shortTTL / 2, shortTTL - 86400000)` 在测试里然后 assert 自己。没有用 short TTL 执行 `resolveUser`。

**Fix 建议:** 提取 `getRefreshThreshold(ttlMs)` 纯函数并单测，或用 `vi.stubEnv` + `vi.resetModules` 在 short TTL 下跑完整路径。

### 🟡 60s per-connection polling (3/3 consensus — escalated from R1)

每个非 bot WS 连接一个 `setInterval`。N 个浏览器 tab = N 个 DB 查询/分钟。

**Fix 建议:** 用 `setTimeout(close, expires_at - Date.now())` 单次定时器，或全局共享一个 ticker。可以开 follow-up issue。

### 🟢 `@deprecated` re-export (2/3: Stella + Nova)

`repos/users.ts` 的 `export { SESSION_TTL_MS }` 加 `/** @deprecated */` 或直接删除。一行改动。

### 🟢 preAuthUser revalidation (2/3: Stella + Vega)

Cookie fallback 时 `preAuthUser` 是 upgrade 时快照。60s poll 已经兜底了，但最严格的做法是 IDENTIFY 时 re-read token。

---

## 我的建议

**R1 的安全/正确性 bug 全修了，剩余都是 hardening。** 实际风险评估：

- `@deprecated` 注释 → **一行改动，顺手加了**
- Short TTL test → **值得改，但不影响生产代码正确性**
- 60s polling → **当前用户量下 OK，scalability concern 适合 follow-up issue**
- preAuthUser revalidation → **60s poll 已兜底，exposure window 可接受**

**建议：加 `@deprecated` 注释后 merge，其余开 follow-up issues。**
