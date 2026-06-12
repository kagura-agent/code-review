# 🌠 Nova's Review — cove#330: infinite scroll

**Verdict:** ⚠️ Needs Changes (mostly small fixes; core approach is sound)

## 1. Summary
PR adds infinite scroll to `MessageList`: cursor pagination on `fetchMessages({ before, limit })`, a `prependMessages` action with id dedup, and a scroll listener that loads older pages within 200 px of the top, restoring scroll position via `scrollHeight` delta inside `requestAnimationFrame`. A top spinner and "beginning of conversation" sentinel are rendered. Module-level `hasMoreHistory` / `fetchingOlder` maps track per-channel state. Conceptually clean and small (~78 LOC). Functionally close to merge but a few correctness/cleanliness issues should be addressed.

## 2. Critical Issues
1. **Fetch logic lives inside `onScroll`, but the effect only re-attaches on `channelId` / `setMessages` changes.** `prependMessages` is read via the `useMessageStore` selector and captured in the closure — fine because it's a stable Zustand action — but the new behavior is *not* in the effect dep array. More importantly the `onScroll` handler closes over `prependMessages` and `setLoadingOlder`; if the store ref were ever swapped (HMR, tests), the listener would be stale. Either (a) move the loader into a `useCallback` and reference via ref, or (b) call `useMessageStore.getState().prependMessages` like you already do for `messages`. Consistency with the `getState()` pattern used two lines above is the easy fix.

2. **Race condition on rapid channel switch.** `fetchingOlder` is keyed by channel id, but `setLoadingOlder(true/false)` is component-scoped. If the user switches channels mid-fetch, the `.finally` will flip `loadingOlder` to `false` for the *new* channel, and if the prepend resolves after the switch, `prependMessages(id, older)` writes to the previous channel (correct) but the spinner UI for the new channel may briefly toggle. Guard with `if (id !== channelIdRef.current) return;` before `setLoadingOlder` and before the rAF scroll restore (which would otherwise mutate the new channel's scroll container).

3. **Scroll-restore can fire against a re-mounted container.** The `container` captured at fetch start may have been unmounted by the time `.then` resolves (channel switch). `container.scrollHeight` / `container.scrollTop +=` would touch a detached node. Add `if (!container.isConnected) return;` (or compare to `scrollContainerRef.current`) inside the `.then` / rAF.

4. **Pending-message edge case in cursor.** `oldest.id.startsWith("pending-")` correctly skips optimistic IDs at the head, but if *every* message in the channel is pending (fresh channel, user typed before first load) the fetch never fires — probably fine, but also means `hasMoreHistory` is never set to `false` and the "beginning" sentinel won't show. Minor; document or handle.

5. **`hasMoreHistory.get(channelId) === false` in render.** This reads from a module-level `Map` during render. React won't re-render when the map mutates inside `.then`. It happens to work because `loadingOlder` toggling triggers a render that re-evaluates the map — coincidental coupling. Either lift `hasMoreHistory` into a `useState`/ref + state, or document this dependency explicitly. Today: when the *last* page returns and sets `hasMoreHistory=false`, `setLoadingOlder(false)` in `finally` happens to trigger the re-render that shows the sentinel. OK by accident, fragile by design.

## 3. Product Impact
- **Positive:** unblocks #299. Users can finally see history beyond 50 messages. Scroll-position preservation is the right UX.
- **Risk — flash of spinner on channel mount:** if a user lands on a channel whose initial fetch returns ≥ 50 and they're already at scrollTop=0 (short viewport), `onScroll` may not have fired yet, but the next render with messages doesn't cause it either. Probably fine; verify with a tall message and a small window.
- **Risk — back-to-back pages:** after a successful prepend, if the user is *still* within 200 px of top (likely, since restore keeps them at the same content position which is now ~oldPageHeight from the new top), the next `onScroll` triggers another fetch. That's intended infinite scroll behavior — but with `NEAR_TOP_THRESHOLD=200` and average message height < 200 px, you could chain several pages on one inertial scroll. Acceptable, but watch for thrash on slow networks.
- **No telemetry / no error toast** when fetch fails — `console.error` only. Users on flaky networks silently lose history. Consider a small inline retry affordance.

## 4. Suggestions (non-blocking)
- Inline the `getState().prependMessages` instead of subscribing via selector — removes one re-render trigger per store change and matches the pattern used for `messages`.
- Extract the loader into a `useCallback(loadOlder, [channelId])` invoked from `onScroll`; keeps the scroll handler readable and easier to unit-test.
- `older.length < PAGE_SIZE` correctly assumes a full page means more exists; if the server ever returns exactly `PAGE_SIZE` on the last page, you'll do one extra empty fetch. Acceptable.
- The bottom-page check on initial load uses `reversed.length >= PAGE_SIZE` — symmetric, good. But if the user already has cached messages for the channel, the effect that sets `hasMoreHistory` may not run (depending on cache path not shown in diff). Verify the initial-load effect actually runs on every channel mount.
- Move the inline `style={{...}}` for the spinner / sentinel into CSS modules or the existing `listStyle` pattern for consistency.
- `older.reverse()` mutates the fetched array — fine here since it's a fresh array, but `.slice().reverse()` is the safer idiom.
- Consider `AbortController` on the fetch and abort on channel switch — cleanly solves issues #2/#3 above.

## 5. Positive Notes
- Cursor-based pagination over offset is the right call.
- `prependMessages` dedup via `Set` is O(n+m), correct, and short-circuits when nothing's new — nice.
- `restoringRef` + double rAF to avoid the scroll listener echoing the restore is a thoughtful touch.
- Per-channel `fetchingOlder` map prevents the obvious "fire on every scroll event" footgun.
- Module-level state survives unmounts → consistent with the existing `scrollMemory` / `lastFetchTime` pattern. Codebase consistency 👍.
- Tiny, focused diff. Easy to review.

---

**TL;DR:** Approach is correct, code is readable, but please add channel-switch guards in the `.then`/`finally` and consider an AbortController; the `hasMoreHistory` Map driving render is fragile. Ship after those tweaks.
