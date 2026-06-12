# 🌠 Nova — PR #330 Round 4 Re-Review

**Repo:** kagura-agent/cove
**PR:** #330 — feat: infinite scroll (closes #299)
**Round:** 4
**Verdict:** ⚠️ **Needs Changes** (one escalated bug + cleanups)

---

## Summary

R3's blocking issue — the stuck spinner after a mid-fetch channel switch — has been resolved cleanly. The `channelId` `useLayoutEffect` now reconciles `loadingOlder` against the module-level `fetchingOlder` map for the channel being entered:

```ts
setLoadingOlder(fetchingOlder.get(channelId) === true);
```

Combined with `firstMessageIdRef.current = undefined` and `setHasMore(hasMoreHistory.get(channelId) !== false)` in the same effect, channel switching now syncs all three pieces of per-channel UI state in one synchronous layout pass. ✅ The R3 critical is genuinely fixed.

However, a previously **non-blocking** R3 issue (`pendingPrependRestoreRef` leak on dedupe no-op) is **still unaddressed and now escalates to Critical** per the anti-confirmation rule. With infinite scroll wired up and shipping, the latent ref leak now has a real path to mis-adjusting `scrollTop` on subsequent renders.

---

## Critical Issues

### 🔴 C1 (escalated from R3 non-blocking) — `pendingPrependRestoreRef` leak when dedupe yields zero new messages

**Where:** `MessageList.tsx` scroll handler + `useMessageStore.prependMessages`.

```ts
// MessageList.tsx — inside .then()
if (older.length > 0) {
  pendingPrependRestoreRef.current = container.scrollHeight;
  prependMessages(id, older);
}
```

```ts
// useMessageStore.ts
prependMessages: (channelId, older) =>
  set((s) => {
    const existing = s.messages[channelId] ?? [];
    const existingIds = new Set(existing.map((m) => m.id));
    const unique = older.filter((m) => !existingIds.has(m.id));
    if (unique.length === 0) return s;   // ← no-op: no re-render
    return { messages: { ...s.messages, [channelId]: [...unique, ...existing] } };
  }),
```

**Failure path (now reachable):**

1. User scrolls to top → fetch returns `older` (length > 0) but every id is already in the store (race with a WS backfill / overlapping page boundary / refetch on the same window).
2. `pendingPrependRestoreRef.current = scrollHeight` is set.
3. `prependMessages(...)` returns the same state reference → Zustand performs **no re-render** → the `useLayoutEffect` at "4b" never runs → ref **stays non-null**.
4. The very next re-render of `MessageList` (a new incoming message, typing indicator change, prop update, theme toggle, etc.) fires effect 4b with a **stale `prevHeight`**.
5. `container.scrollTop += container.scrollHeight - prevHeight` adjusts scroll by an arbitrary delta — usually compensating for the new appended message's height, which the existing "scroll-to-bottom if near bottom" path is also handling. Worst case: user scrolled up reading old messages, an unrelated render fires, and `restoringRef` gets set to `true`, suppressing the next `scroll` event's bookkeeping in `scrollMemory`.

**Why this escalates:** R3 flagged this as a non-blocking suggestion. It has not been addressed in R4. Per the re-review escalation rule, unaddressed issues are escalated rather than re-classified — and the danger is real now that the prepend codepath is the headline feature.

**Fix (one of):**

- Set the ref **only after** confirming the store actually changed:
  ```ts
  if (older.length > 0) {
    const before = useMessageStore.getState().messages[id]?.length ?? 0;
    pendingPrependRestoreRef.current = container.scrollHeight;
    prependMessages(id, older);
    const after = useMessageStore.getState().messages[id]?.length ?? 0;
    if (after === before) pendingPrependRestoreRef.current = null;
  }
  ```
- Or have `prependMessages` return a boolean / number-added and gate the ref on it.
- Or guard effect 4b: if `prevHeight === container.scrollHeight`, treat it as a no-op and just clear the ref without mutating `scrollTop`.

I'd take option 3 — it's also robust against double-fires.

---

## Product Impact

- ✅ Stuck spinner on channel-switch: gone. End users won't see the bug from R3.
- ✅ "Beginning of conversation" indicator and spinner render in the right z-stack; the gradient mask is a nice touch.
- ⚠️ C1 is rare in normal use but **deterministic** under any duplicate-prepend scenario (network retry, paginated overlap from a backend off-by-one, replayed WebSocket history). Symptoms are subtle scroll jumps that are hard to reproduce and harder to diagnose in the wild. Worth fixing before merge.

---

## Suggestions (still open from R3 — non-blocking)

### S1 — `fetchingOlder` map is unbounded
```ts
fetchingOlder.set(id, true);
// ...
fetchingOlder.set(id, false);
```
Uses raw `Map.set` rather than `cappedMapSet`. Practical bound is "number of channels ever opened in this tab," so impact is low, but it's inconsistent with `hasMoreHistory` and `lastFetchTime` which both go through `cappedMapSet`. Cheap to fix.

### S2 — Initial fetch `msgs.reverse()` mutation
Not in this diff, but flagged in R3 — `[...fetched].reverse()` is used correctly in the new scroll handler. The initial-fetch path (effect #2) should match. (Out of scope if not changed in this PR.)

### S3 — `pendingPrependRestoreRef` is not channel-keyed
If user switches channels in the narrow window between `prependMessages(...)` and effect 4b running, the layout effect will adjust the **new** channel's scroll container by the **old** channel's height delta. The channel-switch `useLayoutEffect` should also `pendingPrependRestoreRef.current = null` when it resets the other refs. Two-line fix.

### S4 — Channel-switch reset could also clear `firstMessageIdRef` and `pendingPrependRestoreRef` together
Already clearing `firstMessageIdRef` — add `pendingPrependRestoreRef.current = null` alongside it. Then S3 is closed too.

### S5 — JSX indentation
The added outer wrapper left the `messages.map(...)` block at its old indentation level. Cosmetic, but a Prettier pass would help future diffs.

### S6 — `hasMoreHistory` write in scroll handler bypasses React state in one path
When `older.length < PAGE_SIZE`, you do both `cappedMapSet(hasMoreHistory, id, false)` and `setHasMore(false)` — but the `setHasMore` runs even if the channel has since switched away. Wrap the `setHasMore(false)` in the `channelIdRef.current === id` guard for symmetry with the rest of the `.then()` body. (Currently the guard is only the early `return` before the reverse — `setHasMore` is after the early return, so this is actually fine. Withdraw S6 — flagged in case I'm misreading the indent.)

Re-reading: ✅ S6 is a false alarm; the early `return` covers it. Leaving the note for transparency.

---

## Positive Notes

- The `useLayoutEffect` "4b" for scroll restoration is the right call over `requestAnimationFrame` — it sidesteps the React 18 batching trap that bit R1.
- `firstMessageIdRef` is used cleanly to distinguish prepend vs. append in effect #5 and prevent auto-scroll on history loads.
- The channel-switch reset block now does **all three** state syncs (`hasMore`, `firstMessageIdRef`, `loadingOlder`) in one `useLayoutEffect`, which is exactly the right primitive for pre-paint reconciliation.
- The `before`/`limit` querystring builder via `URLSearchParams` is clean.
- Indicator UI: spinner with gradient mask + "beginning of conversation" footer is well-considered.

---

## Verdict

⚠️ **Needs Changes** — fix C1 (the dedupe-no-op ref leak), ideally also S3/S4 (channel-switch reset of `pendingPrependRestoreRef`). S1 is a nice-to-have for consistency. Once C1 is addressed, this is ready to merge.

— 🌠 Nova
