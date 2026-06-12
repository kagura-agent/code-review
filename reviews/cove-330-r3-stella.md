# Round 3 Re-review — PR #330 (`feat: infinite scroll`)

**Verdict:** ⚠️ Needs Changes

## Summary

The Round 3 patch does address two of the three R2 critical issues directly: prepend detection is reset on channel changes, and the loading spinner is now an absolute overlay that no longer changes the scroll container height. However, the `loadingOlder` channel-switch leak is **not fully fixed**; the new guard prevents stale requests from clearing state for the wrong channel, but there is still no channel-switch reset/reconciliation, so a spinner can leak *into* the next channel and remain visible indefinitely.

I also found one new product-level issue: stale refetches overwrite previously prepended history with only the latest page, which defeats infinite scroll after cache expiry.

## Critical Issues

### 1. R2 issue not fully fixed: `loadingOlder` still leaks across channels, now as a stuck spinner

**Status:** Not fully addressed — escalated from previous round.

R3 changed the `finally` block to guard `setLoadingOlder(false)`:

```ts
.finally(() => {
  fetchingOlder.set(id, false);
  if (channelIdRef.current === id) {
    setLoadingOlder(false);
  }
});
```

This avoids clearing the spinner for the wrong channel, but it does not reset `loadingOlder` when `channelId` changes. Repro path:

1. In channel A, scroll near the top and start `fetchMessages(A, { before })`.
2. `setLoadingOlder(true)` runs.
3. Switch to channel B before the request finishes.
4. The component instance is reused, so the React state `loadingOlder` is still `true` while rendering B.
5. When A's request finishes, `channelIdRef.current !== A`, so `setLoadingOlder(false)` is skipped.
6. Channel B can now show a stuck top spinner even though B is not loading older messages.

This is the same cross-channel state leak class as R2, just in the opposite direction. The state should be derived/reset on channel switch, for example in the `channelId` layout effect:

```ts
setLoadingOlder(fetchingOlder.get(channelId) === true);
```

or by making loading state channel-keyed rather than a single component boolean.

## Product Impact

- Users can see an infinite-scroll loading spinner on the wrong channel after switching channels mid-fetch.
- Because the stale request is intentionally prevented from clearing React state, the wrong-channel spinner may remain until another older-history fetch happens in the current channel.
- This makes the conversation look like it is still loading and undermines confidence in the history loading UX.

## Previous Findings Checklist

1. **`firstMessageIdRef` not reset on channel switch** — ✅ Addressed. R3 resets `firstMessageIdRef.current = undefined` in the `channelId` layout effect, so channel-load renders should no longer be misclassified as prepends.
2. **Spinner inside scroll container causes double jolt** — ✅ Addressed. The spinner is now rendered as an absolutely positioned overlay outside the scroll container, so it should not contribute to `scrollHeight`.
3. **`loadingOlder` leaks across channels** — ❌ Not fully addressed. The `finally` guard is present, but without resetting/reconciling `loadingOlder` on channel switch, a `true` state can leak into the next channel and become stuck.

## Suggestions

- **Preserve already-loaded history during stale refetches.** The stale fetch path still calls `setMessages(channelId, reversed)`, replacing the channel's message array with only the latest page. After a user has loaded older pages, revisiting the channel after `STALE_MS` can drop those older messages from the client cache and make infinite scroll feel like it lost history. Consider merging/deduplicating the fresh latest page into the existing array instead of replacing all messages.
- **Use `cappedMapSet` for `fetchingOlder`.** This R2 non-blocking suggestion remains open; `fetchingOlder.set(id, true/false)` is still unbounded.
- **Channel-key `pendingPrependRestoreRef`.** This remains open. The current stale-response guard reduces risk, but the restore intent is still stored as a single component ref while requests are channel-specific.
- **Consider `AbortController` for channel switches.** This would simplify stale request handling and avoid unnecessary network/results work.
- **Avoid mutating API arrays in the initial fetch path.** `const reversed = msgs.reverse()` still mutates the fetched array. Use `[...msgs].reverse()` for consistency with the older-page path.

## Positive Notes

- The `firstMessageIdRef` reset is in the right place conceptually and directly addresses the R2 prepend-misclassification bug.
- Moving the spinner to an overlay is a good UX fix and should eliminate the scroll-height jolt from the loading indicator itself.
- The `.finally()` channel guard is a useful half of the fix; it just needs a matching channel-switch reset or channel-keyed loading state.
- `prependMessages` deduplicates by message id, which is important for pagination boundaries and retry behavior.
