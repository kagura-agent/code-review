# PR #330 Re-review (Round 2) — 🌠 Nova

**Repo:** kagura-agent/cove
**PR:** feat: infinite scroll — load older messages when scrolling to top (#299)
**Verdict:** ⚠️ **Needs Changes** (small set of focused fixes — author resolved the three R1 criticals, but the fix introduced two new visible bugs)

---

## Summary

The author addressed all three blocking issues from Round 1 in good faith:

| R1 Issue | Status in R2 |
|---|---|
| C1 — channel-switch race | **Fixed.** `if (channelIdRef.current !== id) return;` guards the prepend after `await fetchMessages`. |
| C2 — prepend triggers auto-scroll-to-bottom | **Fixed.** `firstMessageIdRef` distinguishes prepend (first-id changed) from append, and effect #5 short-circuits when `wasPrepend` is true. |
| C3 — React 18 batching breaks scroll restore | **Fixed.** Restore moved out of rAF into a dedicated `useLayoutEffect` driven by `pendingPrependRestoreRef`. |
| NB4 — unbounded Maps | **Fixed** (`cappedMapSet(hasMoreHistory, …)`). `fetchingOlder` is still raw `.set()`, but it has the same key cardinality as `hasMoreHistory` so it's bounded transitively by usage; mark as minor. |
| NB5 — `hasMore` as fragile Map | **Fixed.** Now a `useState`, written alongside the module-cache for cross-mount persistence. |
| NB6 — `fetched.reverse()` mutates response | **Fixed.** Uses `[...fetched].reverse()`. |
| NB7 — selector vs `getState()` | Partially fixed — `prependMessages` is now a stable selector binding (good), and `useMessageStore.getState().messages[id]` is read at scroll-time (good). Consistent. |

The store change (`prependMessages` with id-dedupe) is small, correct, and well-scoped.

---

## Critical Issues (must fix before merge)

### C1-R2. Spinner-removal scroll jump after every prepend
The spinner div renders **above** the message list. The flow is:

1. `setLoadingOlder(true)` → spinner appears (+~30–40px above old content). Browsers preserve `scrollTop` numerically, so the visible content jumps **down** by spinner height the moment the user crosses the top threshold.
2. Fetch resolves, `pendingPrependRestoreRef.current = container.scrollHeight` (which **includes** the spinner). Prepend runs.
3. `useLayoutEffect` (4b) fires: `scrollTop += newScrollHeight - prevScrollHeight` — diff equals only the *new messages* height, because the spinner is in both measurements. Restore is correct **at this instant**.
4. `.finally()` runs `setLoadingOlder(false)` → spinner unmounts → `scrollHeight` shrinks by spinner height, **but `scrollTop` stays the same**, so all visible content jumps **up** by spinner height.

Net effect: every "load older" cycle produces two visible jolts (a downward then an upward shift of ~30–40px). Easy to verify by scrolling to the top of any long channel.

**Fix options:**
- Render the spinner *outside* the scroll container (e.g. as an overlay), so its presence does not change `scrollHeight`.
- Or render the spinner with `position: absolute` / sticky in a way that does not consume layout space.
- Or, simplest: when `setLoadingOlder(false)` fires after a successful prepend, also re-apply the restore (`scrollTop -= spinnerHeight`) — but this requires knowing spinner height, so the structural fix is preferable.

### C2-R2. `loadingOlder` leaks across channel switches
`loadingOlder` is component-local React state, but the in-flight fetch and the `.finally()` that clears it are tied to the **previous** `channelId`. If the user switches channels while a fetch is in flight:

- `loadingOlder` remains `true` on the new channel until the old fetch resolves → the new channel briefly shows a "loading older messages" spinner that has nothing to do with it.
- Worse, the `.finally()` will call `setLoadingOlder(false)` even though the new channel might *also* have triggered its own loadOlder in the meantime, racing the spinner state. The two operations are not keyed by channel.

**Fix:** Either
- Reset `setLoadingOlder(false)` inside the `channelIdRef`/`useLayoutEffect` block that runs on `channelId` change, and ignore the stale `.finally()` (e.g. capture `wasGuarded` after the channel check and only flip state when not guarded), or
- Store `loadingOlder` keyed by channel (like `fetchingOlder`) and derive component state from `fetchingOlder.get(channelId)` via a forced re-render.

---

## Product Impact

- **C1-R2 (visual jump):** Every user who scrolls past the top sees the timeline shudder twice per page load. This is exactly the failure mode #299 was meant to eliminate — the previous round's "scroll restore" criticism was about correctness; this round it's about *perceived* smoothness. Without fixing this, the feature feels worse than the pre-PR "click to load more" behaviour.
- **C2-R2 (cross-channel spinner):** Confusing in heavy multi-channel workflows; the spinner appears on channels the user did not trigger it on. Low severity but visible during fast channel-switching, which is common in Discord-style UIs.

---

## Suggestions (non-blocking)

1. **`firstMessageIdRef` not reset on channel switch.** When the user switches from channel A (firstId = `a1`) to channel B (firstId = `b1`), effect #5 sees `firstId !== ref.current` and treats the *whole channel load* as a prepend, skipping its auto-scroll path. Effect #4's `pendingScrollToBottomRef` covers the cold-load case, so it is mostly benign — but it means effect #5 silently does nothing on the first render after a channel switch, which is a fragile invariant. Reset `firstMessageIdRef.current = undefined` in the same `useLayoutEffect` that updates `channelIdRef`.

2. **`fetchingOlder.set(id, false)` skips the bounded helper.** Use `cappedMapSet` for consistency with `hasMoreHistory`. Cardinality is bounded transitively but the inconsistency is a footgun for future readers.

3. **No abort on channel switch.** The channelId guard is correct, but the network request still completes and parses a response that is immediately discarded. For users on slow connections rapidly switching channels this wastes bandwidth. An `AbortController` keyed by channelId, aborted in the channel-switch `useLayoutEffect`, would be cleaner. Optional.

4. **`oldest.id.startsWith("pending-")` skip is silent.** If the only oldest message is a pending optimistic send (rare but possible on a brand-new channel), the loader will never fire and `hasMore` stays `true`. The "beginning of conversation" indicator then never shows. Consider falling back to `messages[1]?.id` or simply waiting for the pending message to be replaced.

5. **`scrollContainerRef.current` in effect 4b — verify it is actually set.** The diff shows `containerRefCallback` sets only `scrollRoot` state. If the JSX ref is `ref={containerRefCallback}` and *not* a combined ref that also writes `scrollContainerRef.current`, the layout-effect restore is a no-op. This is invisible in the diff; please confirm with the surrounding code (or switch effect 4b to read `scrollRoot`, which the diff proves is set).

6. **`hasMore` initial value.** `useState(true)` means the "beginning of conversation" indicator never shows for a brand-new channel until the first fetch resolves. Minor — the spinner-or-message flicker is unlikely to be noticed, but a `null`/`undefined` tri-state would be cleaner.

7. **`PAGE_SIZE` constant lives in the component file** but the API client uses its own `?? 50` default. If they ever diverge the `older.length < PAGE_SIZE` "no more pages" inference silently breaks. Hoist `PAGE_SIZE` to a shared module, or have the server return an explicit `hasMore` flag.

---

## Positive Notes

- The author correctly identified that `flushSync` is not needed once you commit to `useLayoutEffect` — that is the textbook fix for the React-18 rAF problem, and the implementation is minimal and right.
- The `channelIdRef.current !== id` guard is placed inside `.then()` (not `.finally()`), which is the correct position — it allows the spinner to still clear in `.finally()` even when the result is discarded.
- `prependMessages` doing id-dedupe in the store is a nice defence against double-fetch races, even though the `fetchingOlder` guard should prevent them.
- Saving `prevScrollHeight` *before* `prependMessages(id, older)` (rather than relying on a measurement after commit) is exactly right — the React 18 lesson was internalised properly.
- Bounded-map use, `[...fetched].reverse()`, and the move to React state for `hasMore` all show the author engaged with every non-blocking note, not just the criticals.

---

## Verdict: ⚠️ Needs Changes

The three R1 criticals are genuinely resolved. The remaining work is small:
- Restructure the spinner so it does not change `scrollHeight` (C1-R2).
- Key `loadingOlder` to the active channel, or reset it on channel switch (C2-R2).
- Reset `firstMessageIdRef` on channel switch (suggestion #1, recommend including in the same fix).

With those, this is mergeable.
