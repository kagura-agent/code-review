# Nova — Round 5 Re-review of PR #330 (cove)

**PR:** feat: infinite scroll — load older messages when scrolling to top (closes #299)
**Files:** `packages/client/src/lib/api.ts`, `packages/client/src/stores/useMessageStore.ts`, `packages/client/src/components/MessageList.tsx`
**Rating:** ⚠️ **Needs Changes** — one previously-escalated issue is **NOT actually fixed** (escalated per R4 anti-downgrade rule).

---

## Summary

R5 closes most of R4's open items: `fetchingOlder` now uses `cappedMapSet`, `pendingPrependRestoreRef` is cleared in the `channelId` `useLayoutEffect`, and effect 4b gained a `delta === 0` short-circuit. Two of the three R4 escalations are addressed.

However, R4 escalation **#1 (pendingPrependRestoreRef leak on dedupe no-op)** is still latent. The `delta === 0` guard does not cover the failure path that was actually described in R4. Per the anti-downgrade rule, this remains escalated.

---

## Critical Issues

### 🔴 C1 — `pendingPrependRestoreRef` still leaks when `prependMessages` dedupes to a no-op (R4 #1, NOT fixed)

**Location:** `MessageList.tsx`, scroll handler `.then` block + `useMessageStore.prependMessages` + effect 4b.

**Flow:**
1. Scroll handler `.then` does:
   ```ts
   pendingPrependRestoreRef.current = container.scrollHeight; // set BEFORE prepend
   prependMessages(id, older);
   ```
2. `prependMessages` (store):
   ```ts
   if (unique.length === 0) return s; // SAME state reference
   ```
3. Returning the same `s` reference means zustand emits no change for the `messages[channelId]` selector → **no re-render** → effect 4b never runs → `pendingPrependRestoreRef` stays non-null.
4. Next unrelated re-render (e.g., a new live message arriving, typing indicator, hover state, anything causing the component to re-render) → effect 4b finally fires with a **stale** `prevHeight` from the no-op fetch, computes a non-zero `delta` against the *current* scrollHeight, and bumps `scrollTop` by that delta → bogus scroll jump.

The `delta === 0` guard added in R5 only protects against the case where effect 4b *does* fire on the same render as the no-op prepend (which by construction it doesn't). It does **not** protect against the deferred-fire case described above.

**Fix options (pick one):**
- **Cheapest:** Clear the ref inside `.finally()` of the fetch, *after* the prepend call, e.g.:
  ```ts
  .finally(() => {
    cappedMapSet(fetchingOlder, id, false);
    if (channelIdRef.current === id) setLoadingOlder(false);
    // If a re-render fired, effect 4b already consumed the ref; if it didn't,
    // we must clear it ourselves to avoid leaking into a future render.
    // Safer: only clear if dedupe might have skipped re-render.
    queueMicrotask(() => { pendingPrependRestoreRef.current = null; });
  });
  ```
  (microtask so it runs after React's sync flush of the `.then`'s set() chain.)
- **Cleaner:** Have `prependMessages` return the count of inserted messages (or a boolean), and only set `pendingPrependRestoreRef` when `> 0`:
  ```ts
  const inserted = prependMessages(id, older);
  if (inserted > 0) pendingPrependRestoreRef.current = container.scrollHeight;
  ```
  i.e., move the ref assignment to *after* the dedupe outcome is known.
- **Cleanest:** Stop relying on a free-running `useLayoutEffect` and key effect 4b on a stable trigger (e.g., a `prependVersion` counter bumped only on real inserts).

This is a real correctness bug, not a theoretical one — any dedupe path (concurrent fetches; WS pushing an older message back-channel; user spamming scroll near top) trips it.

---

## Product Impact

- **Most users:** Won't notice — happy-path infinite scroll works.
- **Affected by C1:** When `prependMessages` dedupes (rare but reachable, especially with reconnect/WS races near scroll-top), the *next* unrelated re-render in that channel will silently jump the scroll position by however much content was added between the leaked fetch and that re-render. Symptom = "the list randomly scrolled by ~30px when a new message came in," and it would be very hard to repro/diagnose in the wild. Severity = annoying, not data-losing.

---

## Verified Fixes from R4

✅ **R4 #2 (channel-keyed cleanup):** `pendingPrependRestoreRef.current = null` is in the `channelId` `useLayoutEffect`, and the `.then` callback bails via `channelIdRef.current !== id` before touching the ref. No remaining cross-channel hazard observed.

✅ **R4 #3 (`fetchingOlder` unbounded):** Both write sites use `cappedMapSet(fetchingOlder, id, …)`. Confirmed in diff.

⚠️ **R4 #1 (dedupe no-op leak):** Not actually fixed (see C1).

---

## Suggestions (non-blocking)

- **S1 (carry-over):** Initial fetch still does `msgs.reverse()` which mutates the API response array in place. Cosmetic; one of the previous suggestions.
- **S2 (carry-over):** Effect #5 detects prepend by comparing `firstMessageIdRef` to current first id. If a prepend is followed in the same commit by a new own-message append, both deltas land together and `wasPrepend === true` will *also* suppress the auto-scroll for the appended message. Edge case; unlikely in practice but worth a comment.
- **S3 (new):** The loading spinner overlay is `position: absolute` over the top of the scroll container with a translucent gradient. It visually covers the topmost ~30–40px of message content while a fetch is in flight. Minor UX; consider reserving space or using a sticky top-of-list row instead.
- **S4 (new):** `if (oldest && !oldest.id.startsWith("pending-"))` correctly skips when the only message is an optimistic send, but if the *oldest* real message has an optimistic placeholder above it (rare, but if any future code prepends a placeholder), the guard wouldn't help. Probably fine for now; just flagging the assumption.
- **S5 (new, minor):** `NEAR_TOP_THRESHOLD = 200` plus `PAGE_SIZE = 50` are file-local constants. If desktop is high-DPI / very tall, 50 messages may not push the scroll position back far enough to clear the 200px threshold → could immediately re-trigger another fetch on the same frame. The `fetchingOlder` flag *does* gate this, but consider whether after a successful prepend you want to bail out of the next scroll event until `scrollTop > threshold` again. Currently relies entirely on the fetch flag + the prepend restoring scrollTop above 200; should be fine in practice but worth verifying on a short-message-height channel.

---

## Positive Notes

- The R5 channel-switch hygiene in the `channelId` `useLayoutEffect` is genuinely nice — single place that resets `hasMore`, `firstMessageIdRef`, `loadingOlder`, and `pendingPrependRestoreRef`. Easy to reason about.
- `useMessageStore.getState().messages[id]` in the scroll handler avoids the stale-closure trap cleanly.
- Bounded maps (`hasMoreHistory`, `fetchingOlder`, `lastFetchTime`, `lastAckedIds`) are consistently using `cappedMapSet` now — no leaks from this PR.
- `URLSearchParams` in `fetchMessages` is the right call vs. string concat.
- `useLayoutEffect` for scroll restore (effect 4b) is the correct hook — pre-paint, post-commit. Avoids the R1 React 18 rAF batching pitfall.

---

## Verdict

⚠️ **Needs Changes** — fix C1 (small change, ~3 lines), then this is ready.
