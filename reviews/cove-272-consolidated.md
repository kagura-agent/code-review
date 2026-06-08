# Consolidated Review R1 — cove#272: emoji reactions

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)
**Round:** 1

## Reviewer Verdicts

- 🌟 Stella: **⚠️ Needs Changes** — SentMessageTracker 不可靠
- 🌠 Nova: **⚠️ Needs Changes** — 4 blocking (count math / emoji 验证 / double decode / 零测试)
- 💫 Vega: **✅ Approve with minor** — emoji 长度限制

## Verdict: ⚠️ Needs Changes (2/3)

**架构扎实** — 访问控制正确 (`requireGuildMember`)、N+1 避免了 (`getForMessages` batch)、FK CASCADE 正确、Gateway 事件限 guild 范围。但有几个需要修的问题：

---

## 🔴 Must Fix

### 1. Emoji 路径参数无验证 (Nova + Vega consensus)

`routes/reactions.ts` — `decodeURIComponent(c.req.param("emoji"))` 直接入库。无长度限制、无格式检查。

**风险：** 恶意 client 可以插入 MB 级 "emoji" 字符串 → 撑爆数据库 + WS 广播。

**Fix:**
```ts
if (!emoji || emoji.length > 64) return c.json({ message: "Invalid emoji" }, 400);
```

### 2. 双重 URL decode (Nova)

Hono `c.req.param()` 已经 decode 了，再调 `decodeURIComponent` 是多余的。含 `%` 的 emoji name 会被错误处理。

**Fix:** 去掉 `decodeURIComponent` wrapper。

### 3. Client 非幂等 count math (Nova)

`useMessageStore` 的 `addReaction`/`removeReaction` 用 `count + 1` / `count - 1`。如果 WS 重发同一事件（reconnect、duplicate dispatch），count 会 drift。

**Fix:** 改为 set-membership 模型（track user list），或让 server event 带 absolute `count`。

### 4. 零测试 (Nova + Stella)

新 route + repo + dispatcher 没有任何测试。`ReactionsRepo` 的 add/remove idempotency、auth 路径、CASCADE 行为都没覆盖。

**Fix:** 至少加 repo + route happy/error path 测试。

---

## 🟡 Should Fix

### 5. SentMessageTracker 重启后丢失 (Stella + Vega + Nova)

Plugin 默认 `reactionNotifications: "own"` 但 tracker 纯内存。重启后对历史 bot 消息的 reaction 静默丢弃。

**Fix:** cache miss 时 REST fetch message 检查 `author.id`，或 READY 时 rebuild tracker。

### 6. `getUsersForReaction` 无分页 + N+1 user lookup (Nova)

无 `limit`/`after` 参数，per-user 逐条查。大量 reaction 时性能差。

### 7. SentMessageTracker LRU eviction bug (Nova)

已存在的 id 被 re-add 时仍会驱逐最老条目。

### 8. React key 用 `emoji.name` 不够唯一 (Nova)

---

## 🟢 Looks Good

- N+1 避免 — `getForMessages` batch query ✅
- Auth — `requireGuildMember` 所有 route 一致 ✅
- Dispatcher 只在实际变化时 emit (`if (added)` / `if (removed)`) ✅
- `INSERT OR IGNORE` 处理并发 ✅
- FK CASCADE 正确清理 ✅
- Client WS subscription 模式一致 ✅

---

## 修复优先级

1. Emoji 验证 + 去掉 double decode（2 行改动）
2. 加测试（repo + route）
3. Client count math 改 idempotent
4. SentMessageTracker 加 REST fallback
