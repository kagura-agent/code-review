# Consolidated Review R5 — cove#264: session TTL with lazy + periodic cleanup

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)
**Round:** 5

## R4 Issue Resolution — 全部修复 ✅

| # | Issue | Status |
|---|-------|--------|
| 🔴 | Sliding threshold 短 TTL 失效 | ✅ Fixed — `Math.max(SESSION_TTL_MS / 2, SESSION_TTL_MS - 86_400_000)` |
| 🔴 | 无 `expires_at` 索引 | ✅ Fixed — partial index `WHERE expires_at IS NOT NULL` |
| 🔴 | Cleanup 无日志 | ✅ Fixed — try/catch + count log |
| 🔴 | Cookie 不随 sliding refresh reissue | ✅ Fixed — `requireAuth` + `/me` 都 `setCookie` |
| 🔴 | OAuth token+expires_at 非原子 | ✅ Fixed — 合并为一条 UPDATE |
| 🟡 | v6 backfill 硬编码 7d | ✅ Fixed — 读 `SESSION_TTL_MS` |
| 🟡 | Default bot footgun | ✅ Fixed — `opts.bot === true` |

**🎉 R4 escalated items 全部清零！**

## Reviewer Verdicts

- 🌟 Stella: **⚠️ Needs Changes** — WebSocket 过期 session 不断连 (🔴) + stale expires_at (🟡)
- 🌠 Nova: **✅ Approve** — follow-up issues only (backfill policy, tests, WS)
- 💫 Vega: **⚠️ Needs Changes** — stale expires_at return (🔴)

## Remaining Issues

### 🟡 `resolveUser` 返回 stale `expires_at` (2/3 consensus: Stella + Vega)

sliding refresh 后 `user.expires_at` 没更新内存值，`/api/auth/me` 返回旧的过期时间。前端如果用这个值做 auto-logout timer 会提前踢人。

**Fix (一行):**
```ts
if (remainingMs < refreshThreshold) {
  users.refreshTTL(user.id);
  refreshed = true;
  user.expires_at = Date.now() + SESSION_TTL_MS; // ← 加这行
}
```

### 🟡 WebSocket session 过期后不断连 (Stella 🔴, Nova 🟢)

Gateway 只在 connect 时验证一次 token，之后不 recheck。过期 session 的 WS 连接可以永远收消息。

**建议作为 follow-up issue** — 这个不在 #118 scope 内，且修复需要 gateway 层改动（heartbeat recheck 或 disconnect timer）。

### 🟢 v6 backfill 给休眠用户 fresh TTL (Nova)

代码用 `Date.now() + TTL`，PR 描述说 `updated_at + TTL`。休眠用户部署时获得新的 7 天而不是立即过期。策略选择，非 bug。

### 🟢 测试覆盖 (Nova)

- Cookie reissue 行为无 regression test
- OAuth 原子更新无 test
- 建议补上但非 blocking

## Verdict

**✅ Approve with minor fix — 接近 merge！**

**R1→R5 的进化令人满意。** 从最初的数据丢失风险到现在全面的 TTL 实现（lazy expiry + periodic cleanup + sliding refresh + cookie sync + atomic OAuth），每轮 review 都有实质性进步。

**Merge 前建议修一个：** stale `expires_at` return（一行改动）。WebSocket 过期断连建议开 follow-up issue。
