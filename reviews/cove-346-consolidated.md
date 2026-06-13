# Consolidated Review — PR #346: feat: NEW separator line and unread banner

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)
**Overall Verdict: ⚠️ Needs Changes** (unanimous)
**Individual:** Stella ⚠️ · Nova ⚠️ · Vega ⚠️

Architecture and frozen-snapshot design are sound. The separation of entry indicators from real-time indicators is correct. Issues are focused on edge cases and UX correctness.

---

## Consensus Issues (2+ reviewers agree — high confidence)

### 🔴 C1 — NEW line unreachable when `lastReadIdx === -1` (all 3)

When `lastReadId` is not in the loaded messages array (older than the loaded window), `showNewLine` is set to `true` but the render condition `prev.id === lastReadId` can never match — the NEW separator never appears. Banner says "N new messages" but no red line is visible.

Also, `entryUnreadCount = messages.length` is wrong-by-direction: if `lastReadId` is *newer* than the loaded slice (e.g. cross-device read), the count is dramatically over-reported.

**Fix:** Render the NEW line at the top of the loaded list when `lastReadIdx === -1`, or track `firstUnreadMessageId` explicitly. Suppress banner if the direction is ambiguous.

### 🔴 C2 — No indicators for never-read channels (Stella + Nova)

When `lastReadId` is null (never-read channel / new user), the compute effect short-circuits with no indicators. But all messages should be unread.

**Fix:** Treat `!lastReadId` as "everything is unread" — show banner with `messages.length` count, place NEW line before first message.

### 🔴 C3 — Top banner persists forever on bottom-entry (Nova + Vega)

When a user enters a channel and lands at the bottom (most common case — `scrollMemory.wasAtBottom === true`):
1. `scrollToBottomImmediate` runs with `restoringRef = true`, suppressing the scroll listener
2. Banner is shown by the compute effect
3. No scroll event fires → `if (atBottom) setShowTopBanner(false)` never runs
4. Banner stays "N new messages — Mark as Read" forever until manual scroll

**Fix:** After entry restore, if landed at bottom, schedule `setShowTopBanner(false)`. Or clear in the own-message branch. Or trigger an explicit `isNearBottom` check after restore completes.

---

## Per-Reviewer Unique Findings

### 🌠 Nova

- **🔴 "Mark as Read" doesn't actually mark as read** — Only calls `scrollToBottom()` + `setShowTopBanner(false)`. Works coincidentally because effect #3 auto-acks on mount. If auto-ack is ever refactored, this button becomes a lie. Messages arriving between mount and click are not acked. Fix: explicitly call `clearUnread(channelId)` + `api.ackMessage(...)`.
- **🟡 Wrapping `<div key={msg.id}>`** around `LazyMessageItem` adds 1 DOM node per message. Use `<React.Fragment>` to avoid layout/CSS surprises.
- **🟡 Bottom pill `position: absolute`** rendered outside the relative wrapper — may anchor to wrong element in some layouts.
- **🟡 `getLastReadId` in useLayoutEffect deps** — if Zustand rebinds the reference, effect re-runs and wipes snapshot. Safer to dereference inside effect.
- **🟡 "Mark as Read" / bottom pill are `<span onClick>`** — should be `<button>` for keyboard accessibility.
- **🟡 Three branches in compute effect share identical trailing lines** — extract a helper to avoid drift.

### 🌟 Stella

- **🟡 Missing tests** for: no read cursor, lastReadId older than loaded window, one unread, zero unread, channel switch with cached messages.
- **🟡 Clear `newMessagesBelowCount`** in Mark as Read handler to avoid brief pill visibility during smooth scroll.

### 💫 Vega

- **🔴 Batch message pill counter** — `setNewMessagesBelowCount(c => c + 1)` only increments by 1. If multiple messages arrive in a single React batch, counter is inaccurate. Fix: increment by actual delta.
- **🟡 Race condition on channel switch** — If `messages` array doesn't update synchronously with `channelId`, compute effect may use wrong channel's messages. Verify messages belong to current channelId before locking.
- **🟡 `isOwnMessage` detection** — `lastMsg.id.startsWith("pending-")` misses messages sent from another device. Consider also checking `lastMsg.authorId === currentUserId`.
- **🟡 Throttle state updates in scroll handler** — wrap in `if (showTopBanner)` to avoid unnecessary dispatches.

---

## What's Done Well (consensus)

- ✅ **Frozen-snapshot architecture** (`lastReadIdSnapshotRef` + `unreadComputedForRef`) cleanly separates entry state from current state
- ✅ **Layout-effect reset** syncs with `channelId` — avoids race between old/new channel snapshots
- ✅ **Effect #5** correctly distinguishes own messages (clear NEW line + scroll) from received messages (pill increment when scrolled up)
- ✅ **`docs/unread-spec.md`** is excellent documentation — review can be done against an authoritative spec
- ✅ **Zero server changes** — reuses existing `useReadStateStore`
- ✅ Uses CSS variables for theming consistency
- ✅ Existing scroll restoration and prepend behavior preserved

---

## Blocking Summary

| # | Issue | Severity | Consensus |
|---|-------|----------|-----------|
| C1 | NEW line unreachable when lastReadId not in loaded messages | 🔴 Critical | All 3 |
| C2 | No indicators for never-read channels (null lastReadId) | 🔴 Critical | Stella + Nova |
| C3 | Top banner persists forever on bottom-entry | 🔴 Critical | Nova + Vega |
| Nova-1 | "Mark as Read" doesn't actually mark as read | 🔴 Critical | Nova only (but logically correct) |
| Vega-1 | Batch message pill counter off-by-N | 🟡 Medium | Vega only |

**Recommend fixing C1, C2, C3, and Nova-1 before merge.** The rest are non-blocking improvements.
