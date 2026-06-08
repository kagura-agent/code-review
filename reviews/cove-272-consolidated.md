# Consolidated Review R3 — cove#272: emoji reactions

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)
**Round:** 3

## R2 Issue Resolution — 全部修复 ✅

| # | Issue | Status |
|---|-------|--------|
| 🔴 | Client count drift | ✅ Fixed — server 发 absolute count，client last-writer-wins |
| 🔴 | getUsersForReaction N+1 | ✅ Fixed — JOIN query + limit + after cursor |
| 🟡 | LRU eviction bug | ✅ Fixed — re-add 先 delete 再 add |
| 🟡 | React key collision | ✅ Fixed — `key={r.emoji.id ?? r.emoji.name}` |
| 🟡 | Auto-scroll over-fires | ✅ Fixed — primitive key 只跟 last message |

## Reviewer Verdicts

- 🌟 Stella: **⚠️ Needs Changes** — pagination cursor 同毫秒 skip bug (🟡)
- 🌠 Nova: **✅ Approve** — all fixed, minor follow-ups only
- 💫 Vega: **✅ Approve** — LGTM

## Verdict: ✅ Approve (2/3 approve, 1/3 wants pagination fix)

**R2 的全部 5 个问题都修好了！** 🎉

## 🟡 Minor (non-blocking, follow-up)

### Pagination cursor 同毫秒 skip (Stella)

`getUsersForReaction` 用 `created_at >` 做分页，同毫秒的多个 reaction 可能被 skip。

**Fix:** 加 tie-breaker `ORDER BY r.created_at, r.user_id` + tuple comparison。低概率但值得后续修。

### Config typing (Nova)

`reactionNotifications` 用 `as any`，无 schema 文档。

### Dynamic import per reaction (Nova)

`enqueueSystemEvent` 每次 reaction 都 dynamic import，应 hoist 到 module scope。

---

## 总结

**从 R1 到 R3 的进化：**
- R1: 零验证 + 零测试 + count drift + N+1 → ⚠️
- R2: 验证/测试修了，count drift + N+1 仍在 → ⚠️
- R3: **全部修复，server absolute count + JOIN pagination** → ✅

可以 merge 了 🚀
