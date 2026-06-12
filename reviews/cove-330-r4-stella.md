# PR #330 Round 4 Re-review — Stella

## Summary

The Round 3 critical spinner issue appears to be fixed: `loadingOlder` is now re-synchronized from the per-channel `fetchingOlder` map in the `channelId` layout effect, so switching from channel A to B while A's older-history fetch is in flight should no longer leave B showing A's spinner.

However, the previous non-blocking issues were not addressed. Per the re-review escalation rule, I am escalating the scroll-restore ref issues because they can still produce cross-channel scroll jumps under timing races, especially around prepend commits and channel switches.

**Rating: ⚠️ Needs Changes**

## Critical Issues

### 1. `pendingPrependRestoreRef` is still not channel-keyed and can restore the wrong channel's scroll position

**Status from previous rounds:** Still open; escalated.

In `MessageList.tsx`, the pending prepend restore is still a single component-local ref:

- `pendingPrependRestoreRef` is declared once for the component instance (`MessageList.tsx:175-176`).
- Older-message loading stores the previous height into that ref before calling `prependMessages(id, older)` (`MessageList.tsx:263-266`).
- The layout effect later consumes the ref and applies the height delta to whatever channel's DOM is currently rendered (`MessageList.tsx:370-381`).

Because the same `MessageList` instance is reused across `channelId` changes, this restore token can belong to channel A while the layout effect runs after channel B has been committed. A realistic race is:

1. User is at top of channel A.
2. Older fetch for A resolves; `pendingPrependRestoreRef.current = A.scrollHeight` is set.
3. `prependMessages(A, older)` schedules a render.
4. Before the prepend render/layout effect commits, user switches to channel B.
5. Effect 4b runs against B's scroll container and applies `B.scrollTop += B.scrollHeight - A.prevHeight`.

That can jump B to an arbitrary position. This is the same class of channel-switch race the earlier rounds were trying to remove.

**Suggested fix:** Store `{ channelId, prevHeight }` rather than just `prevHeight`, and in effect 4b only restore if the stored `channelId === current channelIdRef.current`. Clear stale entries on channel switch. A per-channel `Map<string, number>` would also work, but a tagged single pending restore is probably enough.

## Product Impact

- The main stuck-spinner regression from Round 3 is resolved, which is good.
- Users can still see unexpected scroll jumps when switching channels at the same time older messages are being prepended.
- The risk is timing-dependent, but it affects the core UX this PR is meant to improve: stable scroll position while loading history.

## Suggestions

### 1. Clear/avoid `pendingPrependRestoreRef` on dedupe no-op

**Status from previous rounds:** Still open; escalated from suggestion.

`pendingPrependRestoreRef.current` is set before `prependMessages` deduplicates (`MessageList.tsx:263-266`, `useMessageStore.ts:91-99`). If `older.length > 0` but every fetched message already exists, `prependMessages` returns the same Zustand state and no message-list render is caused by the prepend itself.

In the current code, the subsequent `setLoadingOlder(false)` usually causes a render and clears the ref, so this is less dangerous than the channel-keying issue above. But it is still brittle because the restore token's lifecycle depends on an unrelated spinner state update.

Better options:

- Have `prependMessages` return the number of actually inserted messages, then only set a pending restore when `inserted > 0`.
- Or dedupe in the component before setting `pendingPrependRestoreRef`.
- Or clear the pending restore explicitly when prepend is a no-op.

### 2. `fetchingOlder` remains unbounded

**Status from previous rounds:** Still open; escalated from suggestion.

`fetchingOlder` is declared as a module-level `Map` (`MessageList.tsx:96-97`) but is still written with raw `.set()` calls (`MessageList.tsx:250`, `MessageList.tsx:271`). Unlike `scrollMemory`, `lastFetchTime`, `lastAckedIds`, and `hasMoreHistory`, it does not use `cappedMapSet`.

This is probably low practical risk in normal usage, but it is inconsistent with the rest of the file's bounded cache strategy and can grow across many channel IDs.

### 3. Initial fetch still mutates the API response with `msgs.reverse()`

**Status from previous rounds:** Still open; escalated from suggestion.

The initial fetch still does:

```ts
const reversed = msgs.reverse();
```

at `MessageList.tsx:316`. The older-page path correctly uses `[...fetched].reverse()` (`MessageList.tsx:258`). The initial path should do the same for consistency and to avoid mutating a value returned by the API helper.

### 4. Effect #5 tracks prepend detection only when `messages.length` changes

Fresh observation.

The prepend/append effect depends on `[messages?.length, scrollToBottom]` (`MessageList.tsx:394-412`) but updates `firstMessageIdRef.current` inside that effect. If messages are replaced with a new array of the same length, `firstMessageIdRef` can become stale. Later, an append can be misclassified as a prepend because the first ID changed earlier but the effect did not run at that time.

This can happen during stale refetches where the latest 50 messages replace a cached 50-message array. Consider depending on the first/last message IDs explicitly, or maintaining prepend metadata from the prepend operation instead of inferring it from `firstMessageIdRef` inside a length-only effect.

## Positive Notes

- The Round 3 critical `loadingOlder` stuck-spinner issue looks properly addressed with the new channel switch synchronization (`MessageList.tsx:155-163`).
- The fetch `.finally()` still avoids mutating React state for a channel that is no longer active (`MessageList.tsx:270-276`), which is the right guard.
- Older fetches now reverse via a copy (`[...fetched].reverse()`), so that part avoids response mutation.
- `hasMoreHistory` is now capped with `cappedMapSet`, which is consistent with the module-level cache pattern.
