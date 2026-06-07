# Consolidated Review R4 — cove#264: session TTL with lazy + periodic cleanup

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)
**Round:** 4

## R3 Issue Resolution

| # | Issue | Status | New Severity |
|---|-------|--------|--------------|
| 🟡 | Sliding threshold 对短 TTL 失效 | ❌ 未修 | 🔴 (3/3 agree) |
| 🟡 | 无 `expires_at` 索引 | ❌ 未修 | 🔴 (3/3 agree) |
| 🟡 | Cleanup 无日志 | ❌ 未修 | 🔴 (3/3 agree) |
| 🟡 | Cookie 不随 sliding refresh reissue | ❌ 未修 | 🔴 Stella/Vega, 🟡 Nova |

## Reviewer Verdicts

- 🌟 Stella: **⚠️ Needs Changes** — 4 escalated 🔴 + 1 new 🔴 (OAuth non-atomic)
- 🌠 Nova: **❌ Needs Changes** — 3 🔴 + 1 🟡 + 2 new 🟡 + 4 🟢
- 💫 Vega: **🛑 Needs Changes** — 4 escalated issues, all unaddressed

**Consensus: ❌ Needs Changes (3/3)**

## Escalated Issues (全部未修，从 R3 升级)

### 🔴 1. Sliding refresh threshold 对短 TTL 失效 (3/3 consensus)

`packages/server/src/auth.ts:65`

```ts
const refreshThreshold = SESSION_TTL_MS - 24 * 60 * 60 * 1000;
```

`SESSION_TTL_MS < 24h` 时 threshold 为负数 → `remainingMs < refreshThreshold` 永远 false → sliding 静默失效。

**Fix:** `const refreshThreshold = Math.max(SESSION_TTL_MS / 2, SESSION_TTL_MS - 86_400_000);`

### 🔴 2. 无 `expires_at` 索引 (3/3 consensus)

`v6-session-ttl.ts` migration 和 `schema.ts` 都没有 CREATE INDEX。每小时 cleanup 全表扫描。

**Fix:** migration + schema 加：
```sql
CREATE INDEX IF NOT EXISTS idx_users_expires_at ON users(expires_at) WHERE expires_at IS NOT NULL;
```

### 🔴 3. Cleanup 无日志 (3/3 consensus)

`packages/server/src/index.ts:26-30` — `cleanupExpired()` 返回 count 但被丢弃，无 observability。

**Fix:**
```ts
setInterval(() => {
  try {
    const removed = repos.users.cleanupExpired();
    if (removed > 0) console.log(`🧹 Session cleanup: cleared ${removed} expired tokens`);
  } catch (err) {
    console.error("Session cleanup failed:", err);
  }
}, SESSION_CLEANUP_INTERVAL_MS);
```

### 🔴 4. Cookie 不随 sliding refresh reissue (3/3 consensus, severity split)

`resolveUser()` 刷新了 DB `expires_at`，但没有 Hono Context 无法 `setCookie`。浏览器 cookie 过期后删除，即使服务端 session 还活着。

**Fix:** 要么把 sliding refresh 移到有 `c` 的 middleware 层，要么 `resolveUser` 返回 `{ user, refreshed }` 让 middleware reissue cookie。

## New Issues (R4 Fresh Findings)

### 🔴 OAuth token + expires_at 非原子更新 (Stella + Nova)

`routes/auth.ts:79-84` — OAuth 登录两次 UPDATE（profile+token → refreshTTL），crash 中间可能导致新 token 配旧 expires_at → 立即 401。

**Fix:** 合并为一条 UPDATE，包含 `expires_at = ?`。

### 🟡 v6 backfill 硬编码 7 天 (Nova)

`v6-session-ttl.ts:9-13` — grace period 用 `SEVEN_DAYS_MS` 硬编码，不尊重 `SESSION_TTL_MS` 配置。

### 🟡 Default bot footgun (Nova)

`repos/users.ts:48` — `const isBot = opts.bot !== false` → `undefined` 也算 bot，创建永不过期的 session。建议改为 `opts.bot === true`。

### 🟢 Minor (Nova)
- OAuth callback double-write 可合并
- `findByToken` lazy cleanup race（幂等但可加 guard）
- `refreshTTL` 调了两次 `Date.now()`
- 缺少 sliding refresh 触发的测试

## Verdict

**❌ Needs Changes — R3 的 4 个问题全部未修，按规则升级为 🔴。**

这些不是 polish — sliding refresh 是 PR 的核心功能，目前对短 TTL 静默失效；cookie 不 reissue 意味着浏览器用户的 sliding session 实际上不工作。

**必修清单（按优先级）：**
1. Sliding threshold math（一行改动）
2. `expires_at` 索引（一行 SQL）
3. Cleanup logging + error handling（3 行）
4. Cookie reissue on sliding refresh（需要重构 resolveUser 或移到 middleware）
5. OAuth 原子更新（合并两条 UPDATE）
