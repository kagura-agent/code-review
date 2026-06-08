# Consolidated Review R2 — cove#272: emoji reactions

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)
**Round:** 2

## R1 Issue Resolution

| # | Issue | Status |
|---|-------|--------|
| 🔴 | Emoji 长度验证 | ✅ Fixed |
| 🔴 | Double URL decode | ✅ Fixed |
| 🔴 | Client count 非幂等 | ⚠️ 部分修复 — 只 guard 了 self，other users 仍 drift |
| 🔴 | 零测试 | ✅ Fixed — 新增 180 行 repo/route 测试 |
| 🟡 | SentMessageTracker 重启丢失 | ✅ Fixed — REST fallback |
| 🟡 | getUsersForReaction 无分页 + N+1 | ❌ 未修 → escalated 🔴 |
| 🟡 | LRU eviction bug | ❌ 未修 |
| 🟡 | React key collision | ❌ 未修 |

## Reviewer Verdicts

- 🌟 Stella: **⚠️ Needs Changes** — count drift + N+1 + LRU + key
- 🌠 Nova: **⚠️ Needs Changes** — count drift (🔴) + N+1 escalated (🔴) + new scroll bug
- 💫 Vega: **❌ Needs Changes** — count drift escalated + N+1 + LRU

## Verdict: ⚠️ Needs Changes (3/3)

---

## 🔴 Must Fix

### 1. Client count drift for other users (3/3 consensus — 部分修复不够)

只 guard 了 `me === true` 的 dedup。其他用户的重复 `MESSAGE_REACTION_ADD` 仍然 `count + 1` → reconnect 后 drift。

**Fix 二选一：**
- Server event 带 absolute `count` → client 做 last-writer-wins replace
- Client 维护 per-emoji `Set<userId>` → count = set.size

### 2. `getUsersForReaction` 无分页 + N+1 (3/3 consensus — escalated)

每个 reactor 一次 `getById()` 查询，无 limit。1000 reactions = 1000 DB queries。

**Fix:** JOIN query + `LIMIT 25` + `after` cursor。

---

## 🟡 Should Fix

### 3. LRU eviction bug (Stella + Nova + Vega)

```ts
// 现在的代码 — re-add 已存在 id 时白白驱逐
add(id) {
  if (this.ids.size >= this.maxSize) { evict oldest; }
  this.ids.add(id); // no-op if already exists
}
```

**Fix:**
```ts
add(id) {
  if (this.ids.has(id)) this.ids.delete(id); // refresh recency
  else if (this.ids.size >= this.maxSize) { evict oldest; }
  this.ids.add(id);
}
```

### 4. React key collision (Stella + Nova + Vega)

`key={r.emoji.name}` → 改为 `key={r.emoji.id ?? r.emoji.name}`

### 5. Auto-scroll over-fires (Nova — new)

`MessageList` 依赖 `lastMessageReactions`（每次 reaction 都新引用）→ 任何 reaction 都触发 scrollToBottom。

---

## 🟢 Positive

- Server 层扎实：idempotent INSERT OR IGNORE、batch `getForMessages`、正确的 auth + FK CASCADE
- 测试覆盖了 repo + route happy/error paths
- SentMessageTracker REST fallback 解决了重启问题
- Gateway 事件正确限 guild 范围

---

## 修复优先级

1. **Count drift** — 改 WS payload 带 absolute count（影响面最大）
2. **N+1 pagination** — JOIN + LIMIT（性能安全）
3. **LRU fix** — 3 行改动
4. **React key** — 1 行改动
5. **Scroll bug** — 改依赖为 stable signal
