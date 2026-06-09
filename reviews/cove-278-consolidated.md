# Consolidated Review R1 — cove#278: MessageList scroll rewrite

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)
**Round:** 1

## Reviewer Verdicts

- 🌟 Stella: **⚠️ Needs Changes** — scroll restore fragile for deep history
- 🌠 Nova: **⚠️ Needs Changes** — `channelSwitchRef` dead code + deep-scroll restore fragile
- 💫 Vega: **⚠️ Needs Changes** — scroll listener not attached on first visit

## Verdict: ⚠️ Needs Changes (3/3)

**Architecture is excellent — distance-from-bottom, layout-effect restore, single-writer scroll memory are all the right primitives. Three real issues need fixing before merge.**

---

## 🔴 Must Fix

### 1. Scroll listener never attached on first channel visit (Vega)

Effect #2 (scroll listener) depends only on `[channelId]`. On first visit, `messages` is `undefined` → `<Spin />` renders → `scrollContainerRef.current` is `null` → effect returns early. When fetch completes and messages populate, the `<div ref={scrollContainerRef}>` mounts, but Effect #2 doesn't re-run because `channelId` hasn't changed.

**Result:** Scroll position is never saved for freshly loaded channels. User scrolls up, switches away, comes back → position lost.

**Fix:** Add a dependency so the effect re-runs when the container becomes available. E.g.:
```ts
const hasMessages = !!messages;
// Effect #2 deps:
[channelId, hasMessages]
```

### 2. Scroll restore breaks for deep history across channel switches (Stella + Nova — 2/3 consensus)

`LazyMessageItem` stores `visible` in component state initialized from `eager`. When a user scrolls up past the eager zone (>30 messages) in channel A, older items become visible and their real heights contribute to `scrollHeight`. `distanceFromBottom` is saved against this expanded DOM.

On switching back to A, `LazyMessageItem` remounts → non-eager items reset to 60px placeholders → `scrollHeight` shrinks → `restoreDistanceFromBottom` computes `scrollTop = scrollHeight - dist - clientHeight`, which can go **negative** (clamped to 0) → user lands at the top instead of their reading position.

**Fix options (pick one):**
- Persist `visible` state outside the component (e.g. a module-level `Set<channelId:msgId>`) so lazy items that were previously rendered stay rendered on remount
- Save `visibleCountAtSave` alongside `distanceFromBottom` and use it as the initial eager range on restore
- Pragmatic: bump `EAGER_COUNT` to ~50 and accept the tradeoff

### 3. `channelSwitchRef` RAF guard is dead code (Stella + Nova — 2/3 consensus)

The ref is set `true` in `useLayoutEffect` and cleared via `requestAnimationFrame`. Effects #5/#6/#7 are passive `useEffect`s that check this ref. Standard browser ordering:

```
layout effects → microtasks → rAF callbacks → paint → passive effects
```

The RAF callback clears the ref **before** passive effects run, so the guard is never `true` when those effects read it. It works today only because secondary guards (`prevCountRef`, `wasNearBottomRef`) independently prevent the unwanted scrolls.

**Fix:** Either remove `channelSwitchRef` entirely (secondary guards are sufficient) or clear it in a passive `useEffect([channelId])` instead of RAF. Current code is misleading — the comment promises behavior the code doesn't deliver.

---

## 💡 Suggestions

- **S1 — `scrollMemory` / `lastFetchTime` / `lastAckedIds` grow unbounded.** In a long-running SPA with many channels, these Maps leak. Consider an LRU cap (~100 entries) or cleanup on channel-delete events. (Nova)
- **S2 — Date parsing overhead in render loop.** `isGroupStart` calls `new Date(msg.timestamp)` twice per message on every render. Consider pre-computing or using epoch comparison. (Vega)
- **S3 — `PLACEHOLDER_HEIGHT = 60` is fixed.** Real message heights vary widely (one-liner vs. embeds). On fast scroll-up, placeholder→real transitions may cause visible content shifts. The 2000px rootMargin mitigates this but doesn't eliminate it. (Nova)
- **S4 — No tests.** This module now has 7 effects coordinating via 6 refs and 3 module Maps. Even basic jsdom tests for the channel-switch matrix (cached/uncached × bottom/mid-scroll × first-visit/return) would pay for themselves quickly. (Nova)
- **S5 — Silent fetch failure.** `console.error("loadMessages:", err)` is the only error surface. Consider a user-visible notification or retry. (Nova)

---

## ✅ Positive Notes

- **Architecture documentation is outstanding.** The `SCROLL ARCHITECTURE` block comment clearly explains the why behind each design choice — rare and valuable for future maintenance. (3/3 consensus)
- **Distance-from-bottom over scrollTop** is the correct insight for a lazy-rendered list. Most implementations get this wrong. (Nova, Vega)
- **Single-writer principle for scrollMemory** (scroll listener only) is clean and explicitly stated. (Nova)
- **`restoringRef` suppression pattern** correctly prevents save-during-restore races. (Nova)
- **Stable `msg.id` keys** — no array-index key pitfall. (Stella)
- **`LazyMessageItem`** is small, focused, and self-cleans its observer. (Nova)
