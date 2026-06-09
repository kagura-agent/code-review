# 🌠 Nova — Round 2 Re-Review: PR #278 (kagura-agent/cove)

**PR:** fix: rewrite MessageList scroll — position restore, no flash, lazy rendering (closes #181)
**Files:** `packages/client/src/components/MessageList.tsx`, `packages/client/src/components/LazyMessageItem.tsx`
**Round:** 2 (re-review of R1 feedback + fresh pass on new code)

---

## R1 Issue Resolution Check

### R1 #1 (🔴 Must Fix) — Scroll listener never attached on first channel visit
**Status: ✅ ADDRESSED**

Effect #2 deps changed from `[channelId]` to `[channelId, hasMessages]`. When the container is `null` during the loading-spin render, the effect bails out; once `fetchMessages` resolves and `setMessages` flips `hasMessages` from `false → true`, the effect re-runs and the listener attaches to the real `<div>`. Cleanup correctly detaches.

Edge case verified: A→B switch where B has no cache — JSX returns `<Spin>` (scroll div unmounted, ref null), effect cleanup removes listener from A's detached node, fetch completes for B, re-render, listener attaches to B's container. ✅

### R1 #2 (🔴 Must Fix) — Scroll restore breaks for deep history
**Status: ✅ ADDRESSED (clever fix)**

Two complementary changes solve this:
1. `distance-from-bottom` is used instead of `scrollTop` — the bottom `EAGER_COUNT=30` messages render eagerly with stable heights, so this distance is invariant to placeholder compression *above* the viewport.
2. `LazyMessageItem` persists visibility in a module-level `revealedIds: Set<string>`, initialized via `useState(eager || revealedIds.has(messageId))`. So on remount, previously-rendered items start `visible=true` synchronously at render time, before `useLayoutEffect` measures the DOM.

The ordering is correct: React renders all `LazyMessageItem`s (visible ones produce full-height MessageItem), DOM is committed, then `useLayoutEffect` #1 restores `scrollTop`. Heights match what was there when the position was saved. ✅

### R1 #3 (🔴 Must Fix) — `channelSwitchRef` RAF guard is dead code
**Status: ✅ ADDRESSED (replaced with a working pattern)**

The old `channelSwitchRef` is gone. The new `restoringRef` pattern is genuinely correct:

- Set `restoringRef.current = true` synchronously
- Mutate `container.scrollTop`
- Schedule `requestAnimationFrame(() => { restoringRef.current = false; })`

Per the HTML spec's "Update the rendering" steps, scroll events fire during the "run scroll steps" phase, which runs **before** `requestAnimationFrame` callbacks within the same frame. So when the scroll handler fires (from the programmatic write), the flag is still `true` and the bogus save is skipped; only then does RAF clear it. Verified by trace.

### R1 💡 Suggestions — escalation per re-review rules

Per the re-review escalation rule (unaddressed → escalate severity):

- **Unbounded Maps** (`scrollMemory`, `lastFetchTime`, `lastAckedIds`, **new:** `revealedIds`) — NOT addressed. **Escalated to 🔴 Critical.** See below.
- **Date parsing overhead in render** — NOT addressed. **Escalated to 🟡 Important.**
- **Fixed `PLACEHOLDER_HEIGHT = 60`** — NOT addressed. **Escalated to 🟡 Important.**
- **No tests** — NOT addressed. **Escalated to 🟡 Important.**
- **Silent fetch failure** (`console.error` only, no user-visible state) — NOT addressed. **Escalated to 🟡 Important.**

---

## Fresh Findings (new code in R2)

### 🔴 Critical — Race: `pendingScrollToBottomRef` survives across a channel switch

`useLayoutEffect` #4 has **no dependency array**, so it runs after every commit and reads `pendingScrollToBottomRef.current`. The flag is set inside the `fetchMessages.then(...)` callback for the channel being fetched, but it's a *module-level* ref — there's no per-channel keying.

Scenario:
1. User opens channel **A** for the first time (no cache). `fetchMessages(A)` is in flight.
2. Fetch resolves: `setMessages(A, …)`; `pendingScrollToBottomRef.current = true`.
3. Before React commits the A render, the user switches the active channel to **B** (which has cached messages). The component now renders with `channelId = B`.
4. `useLayoutEffect` #1 fires (channelId changed) and **correctly restores B's saved distance-from-bottom**.
5. `useLayoutEffect` #4 fires (every render) — sees `pendingScrollToBottomRef.current === true` and forces **B** to bottom, overwriting the just-restored position.

Net result: switching away from a slow-loading channel can silently clobber the destination channel's scroll position. The flag must be per-channel, or cleared / checked against the channel that requested the scroll.

**Suggested fix:**
```ts
const pendingScrollChannelRef = useRef<string | null>(null);
// in fetch.then:
pendingScrollChannelRef.current = channelId;
// in effect #4:
if (pendingScrollChannelRef.current !== channelIdRef.current) {
  pendingScrollChannelRef.current = null;
  return;
}
```

### 🔴 Critical — `revealedIds` Set leaks unboundedly

`LazyMessageItem.tsx` keeps a module-level `revealedIds = new Set<string>()` that is *never* pruned. Every message the user ever scrolls past in any channel adds a string. For a chat client that's expected to stay open for days/weeks, with thousands of messages per active channel, this grows without bound — and unlike the per-channel `scrollMemory`, deletions never happen.

Combined with the four other unbounded module-level Maps (`scrollMemory`, `lastFetchTime`, `lastAckedIds`, plus `revealedIds`), there is no eviction strategy at all in this PR. **Escalated per R1 rule.**

**Suggested fix:** LRU cap (e.g. last 50 channels for the Maps, last 10k message IDs for the Set), or prune on `useEffect` cleanup tied to channel-list ownership higher up the tree.

### 🟡 Important — Eager-count assumption breaks if `messages.length < EAGER_COUNT`

`const eager = i >= messages.length - EAGER_COUNT;` — when `messages.length` is small (e.g. 5), `i >= -25` is always true, so all messages are eager. That's harmless. But the *design* assumption is "bottom 30 messages render eagerly with stable heights, so distance-from-bottom is invariant." For a brand-new channel with `< 30` messages where the user later loads paginated history, the eager set still anchors at *the current bottom* of the array, which may not be the same DOM as when the position was saved. Pagination isn't in this PR's diff so no concrete bug today, but the invariant should be documented as "depends on append-only message arrays" — and the design will need revisiting when older-message pagination ships.

### 🟡 Important — `useLayoutEffect` #1 restore reads `messages` from a stale closure on cached-channel switch

```ts
useLayoutEffect(() => {
  // ...
  if (container && messages && messages.length > 0) { ... }
  // ...
}, [channelId]);  // eslint-disable react-hooks/exhaustive-deps
```

The comment claims "`messages` is accessed from the closure of the render that triggered this effect" — true for the *render that changed channelId*. But Zustand's `useMessageStore((s) => s.messages[channelId])` selector returns the cached array synchronously on the new render, so this works for revisited channels. For first visits it falls through to the `pending` path (which has the bug above). Acceptable today but extremely fragile — any future change that makes the cached read async (Suspense, deferred selectors, etc.) silently breaks restore.

Add a defensive assertion or read from `useMessageStore.getState().messages[channelId]` inside the effect to make the contract explicit.

### 🟡 Important — Scroll listener save races with effect #1 restore on switch

Effect order on A→B switch with both cached:
1. Render with `channelId = B`. `channelIdRef.current = B` (sync at render time).
2. Scroll listener: still attached to container; if any pending scroll event fires *between* render and `useLayoutEffect` #1, it reads `channelIdRef.current = B` but the DOM still shows A's `scrollTop`, and writes A's position into `scrollMemory.set(B, ...)`. **A's distance written under B's key.**

Mitigations: scroll events generally don't fire spontaneously between render and layout effect because the DOM hasn't been mutated yet, but if React batched a previous user scroll on A into this commit, it could. The safest fix is to bump `restoringRef.current = true` at the *start* of `useLayoutEffect` #1 unconditionally (before reading `mem`), and only clear in the RAF.

Currently `restoringRef` is only set inside the `if (container && messages && messages.length > 0)` branch — if that branch is skipped (e.g. empty cached channel), the flag is never set and any racing scroll event for the prior channel can poison the new channel's memory.

### 🟡 Important — `prevCountRef` reset coupling

`prevCountRef.current = messages?.length ?? 0;` lives at the bottom of `useLayoutEffect` #1, which only runs on `channelId` change. The dedicated "new message → auto-scroll" effect (#5) compares `messages.length > prevCountRef.current`. On first fetch into an empty cache, `prevCountRef` gets set by effect #3? No — effect #3 also sets it. But on cached-channel revisit where the WebSocket pushes a *new* message during the very same commit, `prevCountRef` is set to `messages.length` in #1, and effect #5 sees `messages.length > prevCountRef.current` is false → no auto-scroll for the new message. Minor, but the multiple writers to `prevCountRef` (effects #1 and #3) make this hard to reason about.

### 💡 Suggestion — `useLayoutEffect` #4 has no deps and is unkeyed

Running every render is fine cost-wise (one ref read), but it's surprising to a future reader. Make it explicit:

```ts
useLayoutEffect(() => {
  if (!pendingScrollChannelRef.current) return;
  // ...
}, [messages?.length]);  // or [channelId, messages?.length]
```

This also reduces the surface area of the race in the Critical issue above.

### 💡 Suggestion — `IntersectionObserver` per `LazyMessageItem`

Each placeholder creates its own `IntersectionObserver`. For a channel with 5 000 history messages, that's 4 970 observers on mount. Browsers handle this, but a single shared observer (with a `WeakMap<Element, callback>`) is markedly cheaper. Not urgent.

### 💡 Suggestion — `messageId` collision risk for pending messages

`revealedIds.add(messageId)` will add `pending-xxx` IDs too. Once the message is confirmed and gets a real ID, the pending ID stays in the Set forever and the real ID is a new entry. Compounds the unbounded-growth issue. Filter pending IDs out of `revealedIds`.

---

## Verdict

**Request changes.** The Round 1 Must-Fix issues are genuinely resolved (good work on the distance-from-bottom + persistent visibility design — that's elegant), but R2 introduces a real cross-channel race (`pendingScrollToBottomRef` clobber) that is a regression of the same flavor as the original bug this PR set out to kill. Escalated R1 Suggestions remain unaddressed.

**Blocking:**
1. 🔴 `pendingScrollToBottomRef` is not per-channel — fix the clobber race.
2. 🔴 Bound the four module-level Maps + `revealedIds` Set (LRU or explicit teardown).
3. 🟡 Set `restoringRef` unconditionally at the start of `useLayoutEffect` #1.

**Recommended:**
- Add at least one integration test for the A→B→A scroll-restore path (covers all three R1 Must-Fixes and the new race).
- Replace silent `console.error` on fetch with a user-visible retry affordance.
- Per-message IO measurement instead of single shared observer is technical debt but worth a follow-up issue.

Solid architectural rewrite overall — but ship the Critical fixes before merge.

— 🌠 Nova
