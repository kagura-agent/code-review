1. Summary

This PR is directionally strong: moving scroll restoration into `useLayoutEffect`, tracking distance-from-bottom, suppressing programmatic scroll events, and keeping stable `msg.id` keys are all the right primitives for eliminating channel-switch flash. However, the lazy-rendering implementation currently breaks the main product promise for previously visited, scrolled-up channels: lazy item visibility is local React state and is lost on channel switches, while scroll restoration relies on scroll heights from the previous lazy-rendered DOM. That means saved distances can be restored against a compressed placeholder DOM and land at the wrong position. I would not merge until that behavior is fixed or the restoration/lazy strategy is adjusted.

2. Critical Issues (must fix, blocking)

- **Scroll restoration is not stable across channel switches when older lazy messages have been rendered.** `LazyMessageItem` stores `visible` only in component state initialized from `eager` (`LazyMessageItem.tsx:17-18`). When the user scrolls up in a long channel, older items become visible and their real heights contribute to `scrollHeight`; `MessageList` then saves `distanceFromBottom` from that expanded DOM (`MessageList.tsx:197-200`). After switching away and back, the old message item components are remounted for that channel and non-eager items start as 60px placeholders again (`LazyMessageItem.tsx:39-41`). `restoreDistanceFromBottom` then applies the previously saved distance to a different, compressed scrollHeight (`MessageList.tsx:105-106`, `154-164`), so the restored position can be substantially wrong. This directly undermines the PR goal of exact position restore/no flash for revisited channels. A few possible fixes: persist per-message lazy visibility outside the item component, measure/cache actual message heights, or avoid placeholder compression for channels with saved non-bottom positions until after restoration.

3. Product Impact (user-facing behavior changes/risks)

- Users reading older history in long channels may return to the wrong location after switching channels, especially after scrolling far enough that lazy placeholders have been replaced by real message content.
- Because the wrong restore can happen before paint, it may look like the app "forgot" the user's place rather than just a minor visual glitch.
- The 5-minute fetch skip improves perceived speed, but it also increases reliance on WebSocket delivery. If messages were missed during disconnect/reconnect, a fresh-looking cached channel may remain stale until the cache ages out.

4. Suggestions (non-blocking)

- Add a regression test or manual test case for: long channel >30 messages, scroll into older history until several lazy items render, switch to another channel, switch back, and verify the same message remains anchored.
- Consider making `LazyMessageItem` respond to `eager` changes (`if (eager) setVisible(true)`) so messages that move into the eager window after deletes/truncation cannot remain placeholders. This is not the main blocker, but it is a small correctness hardening.
- The `requestAnimationFrame` used to clear `channelSwitchRef` may run before passive effects in some browser/React timing paths, so it is not a very robust guard for effects #5/#6/#7. Current count/content guards may already prevent most unwanted scrolls, but if this flag matters, clear it in a later passive effect or with a more explicit channel-transition state.
- The review environment could not run client lint/build because dependencies were not installed in the temporary clone (`eslint: not found`). CI or a local install should verify this before merge.

5. Positive Notes

- Using `useLayoutEffect` for pre-paint restoration is the correct approach for eliminating visible scroll flash.
- Stable `msg.id` keys are preserved in the message list, avoiding the common array-index key pitfall.
- The scroll listener cleanup is present and correctly removes the event listener on dependency changes/unmount.
- Ack calls intentionally catch failures, so there are no unhandled/floating promise warnings from those fire-and-forget paths.
- The code is much more explicit about scroll invariants than the previous version; the architecture comment makes the intended behavior easy to review.

Rate: ⚠️ Needs Changes
