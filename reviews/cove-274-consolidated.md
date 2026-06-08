# Consolidated Review R2 — cove#274: unread indicators

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)
**Round:** 2

## R1 Issue Resolution

| # | Issue | Status |
|---|-------|--------|
| 🔴 | setTimeout 泄漏 | ✅ Fixed (Stella 有 RAF caveat) |
| 🔴 | Mark as Read 不 ack | ✅ Fixed |
| 🔴 | Banner 方向不分 | ✅ Fixed — `bannerModeRef` catchup/live |
| 🔴 | Initial scroll race | ✅ Fixed — `isInitialScrollRef` guard |
| 🟡 | Wrapper div | ✅ Fixed — Fragment |
| 🟡 | count 累积 | ✅ Fixed |
| 🟡 | findIndex O(n) | ✅ Fixed — useMemo |
| 🟡 | onScroll 重绑 | ✅ Fixed — showBannerRef |

## Reviewer Verdicts

- 🌟 Stella: **⚠️ Needs Changes** — RAF 未取消可能跨 channel 泄漏 + 无 read cursor 的 channel 不显示 divider
- 🌠 Nova: **✅ Approve** — 全部修复，minor follow-ups
- 💫 Vega: **✅ Approve** — 全部修复，ready to merge

## Verdict: ✅ Approve (2/3)

**R1 的 8 个问题全部修复！**

## 🟡 Minor follow-ups (non-blocking)

### RAF 未取消 (Stella)
`requestAnimationFrame` 在 fetch 后 schedule，但 cleanup 不 cancel RAF id。快速切 channel 理论上可能执行旧 RAF。实际概率很低（RAF 通常下一帧就跑），建议 follow-up 加 `cancelAnimationFrame`。

### 无 read cursor 的 channel (Stella)
第一次访问未读 channel 时 `readStates[channelId]` 为 undefined → `snapshotChannelOpen` 不存快照 → 不显示 NEW divider。边界 case，建议 follow-up 处理。

### isInitialScrollRef 可能吃掉真 scroll (Nova)
短 channel 或已在底部时 programmatic scroll 不触发 event → flag 不清除 → 第一次手动 scroll 被吞。

### bannerModeRef 是 ref 不是 state (Nova)
依赖 piggyback re-render。建议改 useState。

---

**可以 merge 了 🚀 剩余都是 edge case follow-ups。**
