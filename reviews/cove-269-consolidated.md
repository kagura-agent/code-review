# Consolidated Review R3 — cove#269: PR #264 follow-ups

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)
**Round:** 3

## R2 Issue Resolution — 全部修复 ✅

| # | Issue | Status |
|---|-------|--------|
| 🟡 | Short TTL test tautological | ✅ Fixed — 提取 `getRefreshThreshold()` 纯函数 + 真实测试 |
| 🟡 | 60s per-connection polling | ✅ Fixed — 改为 `setTimeout(close, ttl)` 单次定时器 |
| 🟢 | `@deprecated` re-export | ✅ Fixed |
| 🟢 | preAuthUser revalidation | ✅ Fixed (indirectly) |

## Reviewer Verdicts

- 🌟 Stella: **⚠️ Needs Changes** — timer 不 reschedule + preAuth 仍有 gap
- 🌠 Nova: **⚠️ Needs Changes** — timer 不 reschedule (🟡)
- 💫 Vega: **❌ Needs Changes** — timer 不 reschedule + revocation gap (🔴)

## Verdict: ⚠️ Needs Changes (3/3)

---

## 🟡 核心问题：Expiry timer 不 reschedule after sliding refresh (3/3 consensus)

`ws/index.ts` — `setTimeout` 在原始 `expires_at` 时触发。如果用户中途通过 REST 触发了 sliding refresh（`expires_at` 延长到 t+11d），timer 在 t+7d 触发时发现 token 仍有效 → **什么都不做，也不重新调度** → WS 连接永远不会被服务端断开。

**场景（7d TTL）：**
- t=0: IDENTIFY, timer 调度到 t+7d
- t=4d: REST sliding refresh → expires_at 延长到 t+11d
- t=7d: timer 触发, `findByToken` 返回 valid → 不 close, 不 reschedule
- t=11d+: WS 永久存活 ❌

**Fix（所有 reviewer 同意的方案）：**
```ts
function scheduleExpiry(token: string, delayMs: number) {
  if (expiryTimer) clearTimeout(expiryTimer);
  expiryTimer = setTimeout(() => {
    const row = users.findByToken(token);
    if (!row || !row.expires_at) {
      session.close(4004, "Authentication expired");
      return;
    }
    const remaining = row.expires_at - Date.now();
    if (remaining <= 0) session.close(4004, "Authentication expired");
    else scheduleExpiry(token, remaining);
  }, delayMs);
}
```

## 🟢 Minor (follow-up)

- `setTimeout` delay > 2^31-1 ms (~24.8d) 会立即触发 — 加 `Math.min(ttl, 2_147_483_647)` (Nova)
- Token revocation (logout) 不主动断 WS — dispatcher 应该主动 close (Vega)
- WS expiry 行为缺测试 (Stella)

---

## 总结

**进步很大！** R2 的 4 项全部清零，config 集中化、`getRefreshThreshold` 提取、OAuth 路由测试都很扎实。只差 timer reschedule 这一个逻辑补全就可以 merge 🚀
