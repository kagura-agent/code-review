# Stella Review — PR #330 Round 2

## Summary

Verdict: ⚠️ Needs Changes

The Round 2 patch addresses several of the concrete Round 1 items: the older-message fetch now has a channel guard before prepending, prepend scroll restoration was moved into `useLayoutEffect`, `hasMore` is React state, `hasMoreHistory` uses `cappedMapSet`, and the older-fetch reverse now avoids mutating the response array.

However, the fixes are still not fully safe. The prepend/append discriminator can misclassify normal appends after a channel switch, and the prepend restore state is not keyed to the channel, so a pending restore can still affect the wrong channel in a narrow but real race. One Round 1 suggestion also remains unaddressed (`fetchingOlder` is still an unbounded module Map), which I am escalating per the re-review rules.

## Critical Issues

### 1. Append/prepend detection is not channel-safe and can skip required auto-scroll

Round 1 issue: **Prepend triggers bottom auto-scroll**. The new `firstMessageIdRef` approach is a good direction, but the implementation is not synchronized with channel changes.

Current code:

- `firstMessageIdRef` is a single component-level ref (`MessageList.tsx` lines 169-170).
- Effect #5 only runs when `messages?.length` changes (`lines 387-405`).
- `channelId` is not part of that effect's dependencies, and `firstMessageIdRef` is not reset in the channel-switch layout effect.

Because the same `MessageList` instance is reused across channels, switching from channel A to channel B with the same message count can leave `firstMessageIdRef` holding A's first message id. The next normal append in B will see `firstId !== firstMessageIdRef.current`, set `wasPrepend = true`, and skip auto-scroll entirely (`line 393`) — including for optimistic own messages, which the comments explicitly say must always scroll.

Impact: after switching channels, a user can send a message or receive a new message while at the bottom and the list may not scroll to it. This is a regression in core chat behavior.

Suggested fix: make the prepend/appended detection channel-aware. For example, reset `firstMessageIdRef.current = messages?.[0]?.id` in the channel-switch `useLayoutEffect`, include `channelId` in the detection effect, or track previous `{ channelId, firstId, length }` together and only treat a first-id change as prepend when the channel is unchanged and length increased.

### 2. Pending prepend scroll restore is not keyed to the channel

Round 1 issue: **Channel-switch race condition** / **React 18 batching breaks scroll-restore**. The `.then()` guard prevents stale fetch results from immediately prepending after the user has already switched channels, which is an improvement. But after the guard passes, the pending restore is stored globally for the component:

- `pendingPrependRestoreRef.current = container.scrollHeight` (`MessageList.tsx` line 261)
- `prependMessages(id, older)` schedules the store update (`line 262`)
- Later, layout effect #4b applies the restore to whatever channel/container is current (`lines 363-374`) without checking that it is still the same `id`.

In concurrent/batched React, there is still a window where the fetch callback for channel A passes the guard and schedules the prepend, then the user switches to channel B before the commit/layout-effect restore runs. Effect #4b will then adjust B's `scrollTop` using A's `prevHeight`.

Impact: the original wrong-channel scroll mutation is reduced but not fully eliminated; a fast channel switch during an older-page load can still cause a visible jump in the newly selected channel.

Suggested fix: store the pending restore as `{ channelId, prevScrollHeight }` and in the layout effect apply it only if `pending.channelId === channelIdRef.current`. Clear it on channel switch if it belongs to another channel. Alternatively, perform the prepend+restore in a channel-keyed layout effect driven by the store update.

### 3. `fetchingOlder` is still an unbounded module-level Map (escalated from Round 1 suggestion)

Round 1 suggestion: **Unbounded Maps — `hasMoreHistory`/`fetchingOlder` should use `cappedMapSet`**.

`hasMoreHistory` was updated to use `cappedMapSet`, but `fetchingOlder` still uses direct `set` calls and never deletes entries:

- `fetchingOlder.set(id, true)` (`MessageList.tsx` line 246)
- `fetchingOlder.set(id, false)` (`line 267`)

Per the Round 2 escalation rule, this unaddressed Round 1 suggestion is escalated. The practical risk is long-session memory growth as users visit many channels.

Suggested fix: use `cappedMapSet(fetchingOlder, id, true/false)` or delete the entry in `finally` instead of setting it to false.

## Product Impact

- Infinite scroll generally works for the happy path, but the remaining races can produce exactly the kind of chat-list jump/failed auto-scroll behavior this PR is trying to avoid.
- Users may miss their own freshly sent message or a live incoming message after switching channels, because an append can be misclassified as a prepend.
- A fast switch while an older-page fetch is settling can still mutate the wrong channel's scroll position.
- Very long browsing sessions across many channels can retain unnecessary `fetchingOlder` entries.

## Suggestions

1. Make `loadingOlder` channel-aware too. Currently a stale request from channel A can call `setLoadingOlder(false)` after switching to B, and switching away during an A fetch can show A's spinner in B until A finishes. This is less severe than the scroll-position race, but the same `{ channelId, state }` pattern would make it robust.
2. Consider replacing the single `firstMessageIdRef` with a clearer previous-snapshot ref, e.g. `{ channelId, firstId, lastId, length }`, so append/prepend/replacement cases are explicit.
3. The initial fetch still uses `msgs.reverse()` (`MessageList.tsx` line 309). That is probably safe because the array is freshly returned from the API call, but using `[...msgs].reverse()` would match the older-fetch fix and avoid future accidental mutation surprises.
4. Add regression tests for: channel switch with same message count followed by own-message append; older fetch resolving during a channel switch; and repeated channel visits to ensure loading/hasMore state does not bleed between channels.

## Positive Notes

- The API client change for `before`/`limit` is simple and matches the existing server support.
- `prependMessages` deduplicates by id before prepending, which helps with overlapping pages.
- Moving scroll restoration into `useLayoutEffect` is the right timing model for avoiding pre-commit DOM measurements.
- `hasMore` being React state is cleaner than relying on incidental rerenders from `loadingOlder`.
