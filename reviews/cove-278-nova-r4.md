# 🌠 Nova — Round 4 Re-Review: PR #278 (cove)

**PR:** fix: rewrite MessageList scroll — position restore, no flash, lazy rendering (closes #181)
**Files:** `packages/client/src/components/MessageList.tsx`, `packages/client/src/components/LazyMessageItem.tsx`, `.gitignore`
**Verdict:** ✅ **Ready to Merge** (with one non-blocking observation noted below)

---

## R3 follow-through

| R3 item | Status |
|---|---|
| 🟡 Dead code: unused `cappedSetAdd` / `SET_CAP` / `SET_EVICT` in MessageList.tsx | ✅ **Resolved** — no longer present. MessageList now only carries `cappedMapSet` / `MAP_CAP` / `MAP_EVICT`, all of which are used (`scrollMemory`, `lastFetchTime`, `lastAckedIds`). LazyMessageItem owns its own `cappedRevealedAdd` / `REVEALED_CAP` / `REVEALED_EVICT`, also used. No dead exports remain. |
| 💡 Tests | Not added (follow-up, not blocker). |
| 💡 IntersectionObserver root / one observer per item | ✅ Shared observer with explicit `root` — addressed in R3 already. |
| 💡 Date parsing overhead | Partially: switched to `Date.parse` (slightly cheaper than `new Date(...).getTime()`), still 2× per message. Acceptable. |
| 💡 Fixed 60 px placeholder height | Unchanged (follow-up). |
| 💡 Silent fetch failure (`console.error`) | Unchanged (follow-up). |

Per escalation rule: nothing unaddressed warrants escalation. The only R3 cleanup item is resolved.

---

## Fresh review of current code

### Correctness ✅
- **Scroll architecture is sound.** Distance-from-bottom + `restoringRef` + `channelIdRef` cleanly handle the "shared instance across channels" gotcha. Effect ordering is correct: `channelIdRef` update precedes the restore effect (both `useLayoutEffect`), so the scroll listener never sees a stale channel id between commit and paint.
- **Cached-path ack** correctly skips `pending-*` ids and dedups via `lastAckedIds`. Stale (>5 min) cache triggers refetch without losing user scroll position (`pendingScrollToBottomRef` is set only when `wasAtBottom`).
- **Race conditions:** `cancelled` flag in fetch effect handles fast channel switches. Multiple parallel fetches for the same channel would each write the same data and ack — idempotent.
- **`revealedIds` persistence** correctly prevents previously-rendered messages from regressing to 60 px placeholders on remount; combined with browser scroll anchoring this keeps the restored position visually stable.

### Performance — one observation 🟡 (non-blocking)
- **`scrollRoot={scrollContainerRef.current}` is `null` on the first render.** Refs are assigned after render commits, so the first paint hands `null` to every `LazyMessageItem`, which calls `getSharedObserver(null)` → IO uses the viewport as root. On the second render the ref is populated, prop changes, every item's `useEffect` re-runs, the first re-runner calls `getSharedObserver(element)` which `disconnect()`s and `observerMap.clear()`s — wiping all sibling registrations — and every other item then re-registers via its own re-run.
  - Net effect: O(N) observer churn on initial mount and on every channel switch where the scroll container element identity changes.
  - Functional outcome is correct (items eventually register against the right root), but it's wasteful and conceptually fragile.
  - **Suggested follow-up:** convert `scrollRoot` to a `useState` set inside a one-shot `useLayoutEffect`, or pass the ref object itself and have `LazyMessageItem` read `.current` inside its effect. Filed as a polish item, not a blocker.

### Security / Input Validation ✅
- No new user-controlled data paths. Message rendering already sanitized by `MessageItem`. `Date.parse` on a malformed timestamp returns `NaN`; the resulting `NaN > 420_000` is `false`, so the worst case is incorrect grouping for a single malformed message — acceptable.

### Readability ✅
- Architecture comment block at the top of MessageList is excellent — explains the non-obvious "same instance across channels" constraint and why the scroll listener is the sole writer to `scrollMemory`.
- Minor: indentation inside the `messages.map(...)` return block (`const eager = ...` and the `<LazyMessageItem>` block) is off by 2 spaces relative to surrounding code. Prettier will fix on next save.

### API / Interface Design ✅
- `LazyMessageItem` exposes a clean prop surface (`messageId`, `eager`, `scrollRoot`, `children`). `registerVisibilityTarget` is exported but only used internally — fine.

### Product Impact ✅
- Directly fixes #181 and the scroll-flash regression. Behavior now matches Discord. No user-visible downsides expected.

---

## Summary
Author successfully addressed the lone R3 cleanup item; dead code is gone, all module-level helpers are exercised. No new blockers introduced. The `scrollRoot=ref.current` first-render observer churn is a real but cosmetic perf wart worth a follow-up issue, not a merge blocker.

**Recommendation: ✅ Approve / Merge.** File a follow-up issue for: (1) the `scrollRoot` ref-prop pattern, (2) tests, (3) configurable placeholder height, (4) surfacing fetch errors to the user.
