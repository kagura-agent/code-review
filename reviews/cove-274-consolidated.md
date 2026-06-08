# Consolidated Review R1 — cove#274: unread indicators

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)
**Round:** 1

## Reviewer Verdicts

- 🌟 Stella: **⚠️ Needs Changes** — timer leak + banner/divider desync
- 🌠 Nova: **⚠️ Needs Changes** — 3 🔴 (timer leak, Mark as Read 不 ack, wrapper div)
- 💫 Vega: **❌ Needs Changes** — race condition + banner 方向错 + divider 不清理

## Verdict: ⚠️ Needs Changes (3/3)

**方向对，实现有几个真 bug。**

---

## 🔴 Must Fix

### 1. setTimeout 泄漏 / 跨 channel 状态污染 (3/3 consensus)

5s auto-hide timer未存储未清理。快速切换 channel 时旧 timer 会 `setShowBanner(false)` 到新 channel。

**Fix:** timer id 存 ref，在 cleanup 里 clearTimeout。

### 2. "Mark as Read" 不调 `api.ackMessage` (Nova)

只清了本地 UI 状态，server 的 `last_read_message_id` 没更新 → 其他 client / 下次加载还有 badge。

**Fix:** `handleMarkAsRead` 里先调 `api.ackMessage(channelId, lastMessage.id)`。

### 3. Banner 点击 vs 实际滚动方向不一致 (Stella + Vega)

两种场景的 banner 行为不同但代码没区分：
- **Catch-up**（打开有 unread 的 channel）：应该跳到 NEW divider（↑）
- **Live arrival**（滚上去时新消息来）：应该跳到底部（↓）

目前 live arrival 场景没有 divider anchor，点 Jump 是 no-op。

**Fix:** 区分两种状态，live arrival 时 banner 指向底部（↓），或为 live 到达的消息也创建 divider。

### 4. 初始加载 scrollToBottom 触发 onScroll → banner 立即消失 (Vega)

打开 unread channel → scrollToBottom → scroll event → `wasNearBottomRef.current = true` + `showBanner = true` → 立即 `setShowBanner(false)`。

**Fix:** 在初始 scroll 后加 guard（skip 第一次 scroll event 或用 flag 区分 programmatic scroll）。

---

## 🟡 Should Fix

### 5. 额外 wrapper div 可能破坏 CSS (Nova)

每条消息包了一层 `<div>`，之前是 flex 直接子元素。sibling-selector CSS 可能失效。

**Fix:** 用 Fragment + 条件渲染 divider。

### 6. unreadInfo count 不 reset (Nova + Stella)

scroll 到底隐藏 banner 但不清 count → 再滚上去新消息来时 count 累积显示错误数字。

### 7. findIndex O(n) 每次 render (Nova)

应 useMemo。string `>` 比较 message ID 也需确认 ID 格式安全。

### 8. onScroll listener 随 showBanner 重绑 (Nova + Vega)

用 ref 读 showBanner，listener 只在 mount 绑一次。

---

## 🟢 Positive

- Snapshot lifecycle 设计正确（mount-if-unread 快照 → unmount 清理）
- `channelOpenReadIds` 独立于 `readStates`，不被 auto-ack 覆盖
- Gateway dual-ack 注释清晰
- `isGroupStart` 在 divider 后强制为 true — 细节到位

---

## 修复优先级

1. setTimeout 清理（必修，1 分钟改完）
2. Mark as Read 调 ackMessage（必修，1 行）
3. Banner 状态分离（catch-up ↑ vs live ↓）
4. 初始 scroll race condition
5. Wrapper div → Fragment
