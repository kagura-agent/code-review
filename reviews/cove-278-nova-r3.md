# 🌠 Nova — Round 3 Re-Review: PR #278 (kagura-agent/cove)

**PR:** fix: rewrite MessageList scroll — position restore, no flash, lazy rendering (closes #181)
**Files:** `packages/client/src/components/MessageList.tsx`, `packages/client/src/components/LazyMessageItem.tsx`
**Verdict:** ✅ **Approve with minor follow-ups.** All three R2 Must-Fix issues are properly resolved. No new Must-Fix issues introduced.

---

## R2 Must-Fix triage

### 🔴→✅ R2#1: Stale-cache refetch clobbers restored scroll position — **FIXED**

Effect #3 (fetch) used to unconditionally set `pendingScrollToBottomRef.current = true` after every successful fetch. Now:

```ts
const mem = scrollMemory.get(channelId);
if (!mem || mem.wasAtBottom) {
  pendingScrollToBottomRef.current = true;
}
```

This restricts the post-fetch jump-to-bottom to genuinely uncached first-loads or cases where the user was already at the bottom. Stale-refetch into a mid-history position is now preserved. Correctly addresses the regression.

Minor note: the restored scroll position is computed against the *old* message list height; after the refetch swaps in new content (possibly longer), `distanceFromBottom` is reapplied by effect #1? No — effect #1 only fires on `channelId` change, not on a setMessages within the same channel. So the user stays anchored by *whatever scrollTop currently is* relative to the new content. Because the listener saves distance-from-bottom continuously, and the new content is appended at the bottom of the eager region, the visible viewport is preserved (the user effectively stays X px above bottom, even if new messages were inserted above the eager window). This is the intended Discord-like behaviour. ✅

### 🔴→✅ R2#2: ESLint error — ref mutation during render — **FIXED**

The previous `channelIdRef.current = channelId;` at module level inside the render body is gone. Replaced with:

```ts
const channelIdRef = useRef(channelId);
useLayoutEffect(() => {
  channelIdRef.current = channelId;
}, [channelId]);
```

This satisfies `react-hooks/refs`. Subtle correctness check: the scroll listener (effect #2) reads `channelIdRef.current` only inside async `onScroll`. By the time any scroll event fires after a channel switch:

1. React commit → DOM updated
2. `useLayoutEffect` runs → `channelIdRef.current` updated to new channelId
3. (paint)
4. Async scroll event fires → reads updated ref

So the ref is always coherent with what the user sees. ✅

### 🔴→✅ R2#3: Unbounded module-level state — **FIXED**

All four maps/sets now have eviction:

- `scrollMemory`, `lastFetchTime`, `lastAckedIds`: `cappedMapSet` enforces `MAP_CAP = 100`, evicting 20 LRU on overflow (relies on `Map` insertion-order iteration — correct in JS spec).
- `revealedIds` (in `LazyMessageItem`): inline eviction at `REVEALED_CAP = 10_000`, evicting 2_000.

Caps are reasonable (100 channels per user is generous; 10k message reveals covers normal usage). Insertion-order eviction is approximate-LRU only — re-acked channels won't be promoted — but for these workloads that's fine and intentional simplicity. ✅

---

## R2 Suggestions — status

| R2 suggestion | Status | Note |
|---|---|---|
| Date parsing overhead in group-start check | ❌ Not addressed | Still per-render `new Date().getTime()`. Minor. |
| Fixed 60 px placeholder height | ❌ Not addressed | See P1 below. |
| No tests | ❌ Not addressed | See P3 below. |
| Silent fetch failure | ❌ Not addressed | `.catch((err) => console.error(...))` only. |
| IntersectionObserver missing `root` | ❌ Not addressed | Still uses viewport. See P2. |
| One observer per LazyMessageItem | ❌ Not addressed | See P2. |

Per the **escalation rule**: these were yellow suggestions, not must-fixes. They remain yellow but I'm calling out the ones that touch the new lazy-rendering surface specifically.

---

## New code — fresh review

### 🟢 What's solid

- **Effect ordering** (useLayoutEffect #1 restore → useEffect #2 listener → useEffect #3 fetch → useLayoutEffect #4 pending-bottom → useEffect #5/6/7 reactive scroll) is well thought through. `useLayoutEffect` is correctly chosen for anything that must run pre-paint.
- **`restoringRef` flag** correctly suppresses listener writes during programmatic scrolls. RAF reset avoids cross-frame leakage.
- **`distanceFromBottom` as the persisted metric** is the right call given the eager-30 design — it's invariant under lazy placeholder compression above the viewport.
- **Cleanup intentionally does NOT save** is well-documented and correct: by cleanup time, `container.scrollTop` already reflects the *incoming* channel's DOM.
- **Strict Mode safety**: useLayoutEffect #1 restore is idempotent; fetch effect uses `cancelled` flag correctly.

### 🟡 P1 — Fixed `PLACEHOLDER_HEIGHT = 60` understates real message height

`MessageItem` with avatar + author header + content + reactions is typically 60–200 px. Initial placeholders at 60 px mean:

- `scrollHeight` underestimates real content height by potentially large factors when lots of placeholders exist.
- `distanceFromBottom` stored *while* placeholders are unresolved is computed against compressed height; when those placeholders later resolve to taller content, the saved distance is no longer geometrically accurate.

This mostly doesn't bite because the eager bottom-30 region carries the meaningful scroll math, but a user who scrolls up into lazy territory, switches channels, and returns will land slightly off. Not a blocker — but worth a follow-up to either (a) measure the realised height once revealed and cache it, or (b) use a more representative default (e.g., 80–100 px).

### 🟡 P2 — `LazyMessageItem` creates one observer per message; missing `root`

Two related concerns from R2 that remain:

1. **Missing `root` option**: the observer falls back to the viewport, not the scroll container. In `cove`'s layout this *happens* to work because the scroll container fills the viewport, but it's fragile — any future layout change (sidebars, modals, embedded panes) breaks lazy rendering silently.
2. **One observer per item**: for a 1k-message channel, this creates 1k observers on mount (then collapses as items resolve). The chromium implementation batches well, but a single shared observer registered via context or a small subscription manager is the canonical pattern.

Recommended follow-up: refactor `LazyMessageItem` to accept a shared `IntersectionObserver` (and pass `root` = scroll container ref) via a provider in `MessageList`.

### 🟡 P3 — Zero tests for a non-trivial scroll state machine

This component now has 7 effects, 5 module-level Maps/Sets, a `restoringRef` flag, and ordering assumptions between useLayoutEffect and useEffect. The exact bug we're fixing (R2#1 — stale-cache clobber) is a textbook case of "looked obviously correct in review, broke in production." At minimum:

- Unit test for `cappedMapSet` / `evictOldest` eviction behaviour.
- React Testing Library test for: switch A→B with cached B at non-bottom → assert `scrollTop` matches saved distance.
- Test for: stale cache refetch on channel viewed mid-history does NOT scroll to bottom.

Not a blocker, but please file an issue if not added here.

### 🟡 P4 — `lastFetchTime` not updated by WebSocket delivery

`STALE_MS = 5 min` triggers refetch even on actively-updated channels because `lastFetchTime` is only written in the fetch path. Result: an active channel refetches every 5 min, which is fine functionally (the refetch now respects scroll position thanks to R2#1 fix) but is wasted bandwidth on the noisy channels. Consider updating `lastFetchTime` whenever WebSocket appends a message. Suggestion only.

### 🟡 P5 — `hasMessages` in effect #2 deps causes unnecessary re-binding

```ts
const hasMessages = !!messages && messages.length > 0;
useEffect(() => { ... }, [channelId, hasMessages]);
```

The listener depends only on `scrollContainerRef.current`, which is stable. Re-binding when `hasMessages` flips is harmless but unnecessary. Could drop `hasMessages` from deps. Nit only.

### 🟡 P6 — Effect #4 (pending-bottom) has no deps, runs every render

Intentional, per the comment, to catch the post-fetch render. Cheap (one ref check), but worth a note: any future addition that reads state inside this effect must be careful — it'll fire on every render including typing-indicator updates, reaction changes, etc. The current implementation is minimal enough that it's fine. ✅

### 🟢 No correctness issues found in:

- Eviction helpers (`cappedMapSet`, `cappedSetAdd`, `evictOldest`).
- `LazyMessageItem` observer setup/teardown (disconnect on visible, no leak).
- `revealedIds` Set persistence across remounts.
- Effect #1 explicit `eslint-disable react-hooks/exhaustive-deps` — justified and documented.

---

## Security / Input-Validation / Product

- No new attack surface. The scroll state is local; no untrusted input parsed.
- `messageId` from server is used as a Set key — fine, no injection risk for a `Set<string>`.
- Product impact: this is a meaningful UX upgrade, closes #181, removes a long-standing flash. The "Discord-like" behaviour matches user expectations.

---

## Summary

R2 Must-Fix bar: **3/3 properly resolved.** Implementations are not just patches — they reflect that the author thought through the underlying state machine. The escalation rule does not apply (no R2 issue ignored).

R2 suggestions: **0/5 addressed.** That's the author's prerogative for yellow items, but P1 (placeholder height), P2 (observer scope/root), and P3 (tests) genuinely matter and I recommend filing follow-up issues if they're not landed in this PR.

**Approve and merge once at least one of {P3 test for stale-refetch, P2 observer `root` option} is added, or a follow-up issue is filed for each remaining yellow.** No blocking concerns in the current diff itself.
