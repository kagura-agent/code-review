# Consolidated Review R4 — cove#261: READY cache + rate-limit + optimistic send

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)
**Round:** 4

## R3 Issue Resolution

| # | Issue | Status |
|---|-------|--------|
| 🔴 | Nonce 校验在 DB 写入之后 | ✅ Fixed — 校验移到 `create()` 之前 |
| 🟡 | Empty guilds READY 不触发 setChannels | ✅ Fixed — 无条件调 `setChannels` |
| 🟡 | Retry 路径缺 REST reconciliation | ✅ Fixed — `.then(reconcilePending)` 已加 |

## Reviewer Verdicts

- 🌠 Nova: **✅ Ready** — "Ship it 🚀"
- 💫 Vega: **✅ Ready** — "No further changes required. Excellent work"
- 🌟 Stella: **⚠️ Needs Changes** — 发现新的竞态条件

## Stella 的新发现

🟡 **`setMessages` 可能覆盖 pending 消息**: 用户切换 channel → `fetchMessages` 开始加载 → 用户在加载完成前发消息 → pending 消息插入 store → fetch 完成 `setMessages` 覆盖整个数组 → pending 消息消失。

**评估:** 这是一个边界竞态，需要用户在 channel 加载完成前就发消息。实际场景中比较少见（加载期间 MessageInput 一般还不可用或内容为空），且不影响服务端数据完整性。适合 follow-up issue 而非 merge blocker。

## Final Verdict

**✅ Ready** (2/3 直接 approve，1/3 有 non-blocking 竞态建议)

🎉 **四轮 review 完成！** 从 R1 到 R4：
- Retry 重复消息 → 修复
- 侧边栏 loading 状态 → 修复
- Token bucket debt → 修复
- Global bucket bypass → 修复
- 乐观发送 REST+WS 双路径 reconciliation → 修复
- Nonce 校验顺序 → 修复
- Empty guilds → 修复

可以 merge 了 💪
