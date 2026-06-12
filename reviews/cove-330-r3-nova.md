# PR #330 Re-Review — Round 3 (🌠 Nova)

**Repo:** kagura-agent/cove
**PR:** feat: infinite scroll — load older messages when scrolling to top (closes #299)
**Files:** `api.ts`, `useMessageStore.ts`, `MessageList.tsx`

---

## Summary

Round 2's three critical issues are all genuinely addressed in this diff. The fixes are minimal, targeted, and match what the author claimed. One new edge-case bug surfaced during fresh review: the prepend-restore ref can be left dangling when the store's dedupe step short-circuits, causing a phantom scroll-jolt on the next unrelated re-render. R2's non-blocking suggestions remain unaddressed but were not promised for this round.

**Verdict:** ⚠️ **Needs Changes** (one new medium-severity issue; R2 criticals are resolved).

---

## R2 Issue Verification

### R2-#1: `firstMessageIdRef` not reset on channel switch — ✅ **Fixed**

In the `channelId` `useLayoutEffect`:
```ts
channelIdRef.current = channelId;
setHasMore(hasMoreHistory.get(channelId) !== false);
firstMessageIdRef.current = undefined;
```
On switch, `firstMessageIdRef` is cleared. Effect #5's prepend check explicitly guards `firstMessageIdRef.current !== undefined`, so the first render of a new channel correctly classifies as non-prepend → auto-scroll path runs as expected. Verified.

### R2-#2: Spinner inside scroll container caused double jolt — ✅ **Fixed**

Spinner is now lifted into a wrapper `<div style={{ position: "relative", flex: 1, display: "flex", flexDirection: "column", minHeight: 0 }}>` that sits **outside** the scroll container:

```jsx
<div style={{ position: "relative", ... }}>
  {loadingOlder && (<div style={{ position: "absolute", top:0, ..., background: "linear-gradient(...)" }}><Spin/></div>)}
  <div ref={scrollContainerCallbackRef} style={listStyle} className="scroll-container">
    ...
  </div>
</div>
```
Spinner show/hide no longer mutates the scroll container's `scrollHeight`, so the prepend-restore math (`scrollTop += scrollHeight - prevHeight`) stays stable. The gradient overlay also avoids hiding text underneath visually jarringly. Verified.

### R2-#3: `loadingOlder` state leaks across channels — ✅ **Fixed**

```ts
.finally(() => {
  fetchingOlder.set(id, false);
  if (channelIdRef.current === id) {
    setLoadingOlder(false);
  }
});
```
React state only updates if we're still on the originating channel. The module-level `fetchingOlder` map is keyed per channel, so clearing it unconditionally is correct (it doesn't affect other channels). Verified.

---

## Critical Issues

### C1 (NEW) — `pendingPrependRestoreRef` leak when prepend dedupes to zero

**Severity:** Medium (edge case, but produces a visible scroll-jolt).

In the load-older `.then()`:
```ts
if (older.length > 0) {
  pendingPrependRestoreRef.current = container.scrollHeight;  // (A)
  prependMessages(id, older);                                  // (B)
}
```

And in the store:
```ts
prependMessages: (channelId, older) =>
  set((s) => {
    const existing = s.messages[channelId] ?? [];
    const existingIds = new Set(existing.map((m) => m.id));
    const unique = older.filter((m) => !existingIds.has(m.id));
    if (unique.length === 0) return s;   // <-- no state change → no re-render
    ...
  }),
```

If every message returned by the API is already in the store (e.g. a duplicate fetch caused by a fast double-trigger near the threshold, an in-flight WebSocket backfill, or React StrictMode double-invoking effects in dev), `prependMessages` returns the same state object → no re-render → effect 4b **never runs** → `pendingPrependRestoreRef.current` stays non-null.

Then, on the **next** unrelated re-render (new incoming message, typing indicator, etc.), effect 4b fires with a now-stale `prevHeight`, computes a bogus delta, and shoves `scrollTop` by `scrollHeight - prevHeight`. The user sees a sudden jump.

**Fix options:**
- Set the ref inside the unique-check (return the `unique` array or a boolean from `prependMessages` and only stash the ref when something actually changed), or
- Capture `scrollHeight` *and* immediately clear it on a microtask if no commit followed, or
- In effect 4b, additionally gate on a counter / prepend epoch so it can only run once per intent.

The cleanest: have `prependMessages` return whether it mutated, and only set `pendingPrependRestoreRef.current` when it did.

---

## Product Impact

- **Happy path:** Works as intended. Scroll up → spinner appears as overlay, older page loads, position is preserved, "beginning of the conversation" sentinel appears when exhausted.
- **Channel switching mid-load:** Safe. Stale results are dropped, spinner doesn't bleed across channels, `firstMessageIdRef` reset prevents misclassification.
- **Edge case (C1):** Rare in normal use, but anyone who scroll-spams near the top, or runs with React StrictMode, or has a WebSocket that delivers backfill concurrently, can hit a phantom jolt on the *next* re-render. Not catastrophic, but breaks the "no surprise movement" contract this PR is built around.
- **First visit to a never-seen channel:** `hasMoreHistory.get(id)` is `undefined`, defaults to "try" — correct.

---

## Suggestions (non-blocking; carry-over from R2)

1. **`fetchingOlder` map is still unbounded.** Wrap writes in `cappedMapSet` for consistency with `lastFetchTime` / `lastAckedIds`.
2. **`pendingPrependRestoreRef` is not channel-keyed.** Combined with C1, this is a small footgun: if a load-older fires for channel A, user switches to B before the response, then the response arrives and dedupe-noops, the ref pollutes channel B's render. Channel-keying the ref (or storing `{ channelId, height }`) closes the door.
3. **No `AbortController`.** Channel-switch races are handled by the `channelIdRef` guard, which is correct, but you still pay the network round-trip and the parse cost.
4. **Initial fetch still uses `msgs.reverse()` mutation** — harmless but inconsistent with the `[...fetched].reverse()` used in the load-older path. Pick one style.
5. **Magic numbers** — `NEAR_TOP_THRESHOLD = 200` and `PAGE_SIZE = 50` are both well-named constants now (good), but you may want a brief comment on why 200px (≈ enough for slow scrollers to trigger before hitting the top).
6. **Indentation drift inside the `messages.map` JSX.** The block was not re-indented after being nested one level deeper inside the new wrapper. Cosmetic, but ESLint/Prettier may complain.

---

## Positive Notes

- The R2 fixes are surgical and *don't* introduce churn elsewhere — exactly what a re-review wants to see.
- Splitting the spinner out of the scroll container with a gradient overlay is a clean visual fix; many implementations get this wrong and force users to live with the jolt.
- `useLayoutEffect` for the prepend restore is the right primitive (no rAF flash, no React 18 batching trap).
- Resetting `firstMessageIdRef` in the same `useLayoutEffect` as `channelIdRef.current` is the right place — same commit phase, atomic with respect to subsequent effects.
- `hasMoreHistory` cached at module level survives channel re-mounts, so revisiting an exhausted channel doesn't fire a wasted fetch.
- `prependMessages` correctly dedupes by id (the very fact that it can be a no-op is what introduces C1 — the dedupe itself is the right call).

---

**Verdict:** ⚠️ **Needs Changes** — please address C1 (and ideally the channel-keying suggestion #2, since it's the same root cause). R2's three critical fixes are all genuine and well-implemented; this is one round away from ✅.
