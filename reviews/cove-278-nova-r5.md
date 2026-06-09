# 🌠 Nova — Round 5 Re-Review

**PR:** kagura-agent/cove#278 — `fix: rewrite MessageList scroll`
**Head:** `b033b7903aeb979ce05ba641e74dd31725f98caa`
**Verdict:** ✅ **APPROVE** — R4 blocker resolved; no new blockers found.

---

## R4 Blocker — RESOLVED ✅

**Issue:** `<LazyMessageItem scrollRoot={scrollContainerRef.current}>` read a ref during render, violating `react-hooks/refs`.

**Fix verified** (MessageList.tsx ~L156-163):
```tsx
const scrollContainerRef = useRef<HTMLDivElement>(null);
const [scrollRoot, setScrollRoot] = useState<HTMLDivElement | null>(null);
const scrollContainerCallbackRef = useCallback((node: HTMLDivElement | null) => {
  scrollContainerRef.current = node;
  setScrollRoot(node);
}, []);
```
The scroll container uses `scrollContainerCallbackRef`, and `<LazyMessageItem scrollRoot={scrollRoot}>` now consumes the state value. This is the textbook callback-ref + useState pattern. ESLint rule satisfied, render is pure.

Side effect: a re-render fires once after mount (scrollRoot null → node) and all lazy items re-render. Cost is acceptable; the shared `IntersectionObserver` already handles root changes via `getSharedObserver`'s `currentRoot !== root` branch (disconnects, clears map, recreates).

---

## R4 Follow-ups — Status

| # | R4 follow-up | Status in R5 |
|---|---|---|
| 1 | No tests added | Still none. Non-blocking, but `scrollMemory` + `restoringRef` interaction is exactly the kind of logic that regresses silently. Tracking issue recommended. |
| 2 | Fixed 60 px placeholder | Unchanged. `revealedIds` Set keeps previously-rendered items real on remount, so the visible damage is bounded to first-paint of cold items. Acceptable. |
| 3 | Silent `api.ackMessage().catch(() => {})` | Unchanged. Two call sites (fresh-cache branch and post-fetch branch) both swallow. Non-blocking. |
| 4 | `lastFetchTime` not updated by WebSocket | Unchanged. Stale check still uses fetch time only, so a chatty channel can still trigger an unnecessary refetch every 5 min. Non-blocking. |

---

## Fresh Review (R5)

### Correctness — ✅
- **Scroll listener stale-closure protection**: `channelIdRef` + `restoringRef` accessed via `.current` inside `onScroll`, no captured-id bug. `useLayoutEffect(() => { channelIdRef.current = channelId; }, [channelId])` runs before paint and before `useEffect #2` re-setup.
- **Cleanup vs setup ordering on channel switch**: comment correctly notes that cleanup of effect #1 cannot save A's position (DOM already swapped). Authority for saving sits with the scroll listener (effect #2). Verified: every user scroll on A writes to `scrollMemory[A]` before the channel changes.
- **Spin → list transition**: when B has no cache, first render is `<Spin>` (no container). Effect #1 short-circuits on `container && messages.length > 0`. After fetch, container mounts → effect #1 does NOT re-run (deps: `[channelId]`), but effect #4 (`pendingScrollToBottomRef`, no deps) handles scroll-to-bottom on the next layout. Sound.
- **`hasMessages` in effect #2 deps**: needed precisely because the container DOM is conditionally rendered. Re-attaching the listener when the container appears is correct.
- **Programmatic-scroll suppression**: `restoringRef` set sync, cleared in RAF. The scroll event fired by `el.scrollTop = …` is queued before the RAF callback, so it'll observe `restoringRef === true` and bail. Solid.

### Performance — ✅
- Single shared `IntersectionObserver` per scroll-root (was per-item in earlier iterations). Good.
- `revealedIds` capped at 10 000 with FIFO eviction of 2 000 — bounded.
- `scrollMemory` / `lastFetchTime` / `lastAckedIds` all use `cappedMapSet(MAP_CAP=100, MAP_EVICT=20)`. Bounded.
- `Map.set` on existing key doesn't change insertion order, so a hot channel won't get evicted ahead of cold ones.

### Hook Hygiene — ✅
- All disabled `react-hooks/exhaustive-deps` lines carry justifications (or are obvious closure-by-design cases).
- No floating promises except the two intentional `.catch(() => {})` (ack).
- No render-time ref reads anywhere I can see.
- `useLayoutEffect` chosen correctly for both pre-paint scroll restore and ref-mirror updates.

### Security / Input Validation — N/A
Pure client-side scroll logic; no new untrusted inputs.

### API / Interface Design — ✅
`registerVisibilityTarget(el, onVisible, root)` is a clean public seam. The module-level `revealedIds` + `observerMap` are appropriate for cross-instance persistence semantics described in the PR body.

---

## Nits (non-blocking, don't gate merge)

1. **Indentation drift, MessageList.tsx ~L320-329** — `const eager` / `return (` are indented one extra level relative to `const isGroupStart`. Parses fine; Prettier would normalize. Cosmetic.
2. **Cold-cache + user-was-scrolled-up edge case** — if B's cached messages were evicted from the store AND `scrollMemory[B].wasAtBottom === false`, the post-fetch path neither restores from memory (effect #1 already missed its window) nor scrolls to bottom (`pendingScrollToBottomRef` only set when `wasAtBottom`). Container stays at whatever scrollTop it inherited. Rare path; consider scrolling-to-bottom as a safe default OR re-running restore once messages populate.
3. **`useLayoutEffect` with no deps (effect #4)** runs on every render. Cheap (one bool check + early return) but if you later add expensive work here, watch out.
4. **`lastMsg` declared twice** in this file (`const lastMsg = reversed[…]` inside fetch effect; `const lastMsg = messages?.[…]` later). Different scopes, just easy to confuse during future edits.

---

## Bottom Line

R4's single blocker is fixed using the recommended pattern. The new code is internally consistent, hook rules are respected, memory is bounded, and the scroll-restore architecture as documented matches the implementation. Ship it.

**Recommended merge condition:** none from me. Nits 1-4 can be follow-up issues.
