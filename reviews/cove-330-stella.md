# Review: PR #330 — feat: infinite scroll

## Summary
This PR adds cursor-based message pagination on the client, a `prependMessages` store action with ID deduplication, and top-of-list infinite scroll with scroll-height-delta restoration. The general approach is sound and the API query construction is clean, but I would not merge as-is: there are a couple of scroll/state race conditions that can cause visible jumps or mutate the wrong channel after navigation.

**Rating: ⚠️ Needs Changes**

## Critical Issues

1. **Older-message fetch can update/restores against the wrong channel after a channel switch/unmount.**
   - `onScroll` captures the current `container` and starts `api.fetchMessages(id, ...)`, but there is no cancellation or current-channel/container check before `prependMessages`, `setLoadingOlder(false)`, or the `requestAnimationFrame` scroll adjustment.
   - Because the same DOM node is reused across channel switches, a slow fetch started in channel A can finish while channel B is visible and then adjust B's `scrollTop` using A's `prevScrollHeight`.
   - Please guard promise continuations with something like `if (channelIdRef.current !== id || scrollContainerRef.current !== container) return;`, and avoid `setLoadingOlder` after unmount. Ideally make loading/cancellation scoped per request/channel.

2. **Prepends are treated as generic message-count increases and can trigger bottom auto-scroll.**
   - Effect #5 runs whenever `messages.length` increases. Loading older history also increases length, but the last message has not changed.
   - If `wasNearBottomRef.current` is true while also near the top (short/compact message lists, small history, or content smaller than the viewport), prepending older messages can cause `scrollToBottom()` and defeat the scroll-position restoration.
   - Fix by distinguishing appends from prepends, e.g. compare previous last message id, track an `isPrependingOlderRef`, or update `prevCountRef`/append detection before the prepend-induced render.

## Product Impact

- The feature addresses an important user gap: users can finally access messages older than the initial latest 50.
- Main user-facing risk is scroll instability: users may see sudden jumps to another position, especially when switching channels during a load, using slow networks, or in short channels where top and bottom thresholds overlap.
- If fetches fail, the client logs the error and immediately allows retries on every top scroll. That is acceptable for a first pass, but repeated failures could feel noisy/rate-limit-prone.

## Suggestions

- Add tests or a small manual regression checklist for:
  - switch channel while an older-page request is in flight;
  - initial list shorter than viewport but exactly `PAGE_SIZE` messages;
  - rapid repeated top scrolling;
  - empty older-page response;
  - dedup when a fetched page overlaps existing messages.
- Consider making `hasMoreHistory` and `fetchingOlder` bounded like the other module-level maps, or store this state in Zustand per channel. Currently they can grow for every visited channel.
- Include `prependMessages` in the scroll-listener effect dependency array, or document why the selected Zustand action is intentionally stable. This avoids stale-closure/lint issues.
- `prependMessages` dedup is correct for existing-message overlap and is O(existing + fetched), which is fine at current scale. If message lists can grow very large, consider virtualization/windowing or a per-channel ID index to avoid rebuilding a Set over the full list on every page.
- Avoid mutating fetched arrays with `fetched.reverse()` unless the API helper contract permits it; `[...fetched].reverse()` is safer and clearer.

## Positive Notes

- API parameter handling with `URLSearchParams` is straightforward and correctly encodes `before` and `limit`.
- The per-channel request gate prevents most duplicate concurrent older-page loads during rapid scrolling.
- Scroll restoration via `scrollHeight` delta is the right core strategy for prepending content.
- The store-level dedup prevents overlapping cursor pages from duplicating visible messages.
- The loading spinner and beginning-of-conversation affordance are good UX additions.
