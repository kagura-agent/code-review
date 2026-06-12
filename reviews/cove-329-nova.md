# 🌠 Nova Review — PR #329 (kagura-agent/cove)

**PR:** fix: auto-scroll to bottom on own message send (closes #317)
**Scope:** `packages/client/src/components/MessageList.tsx` (+14 / −2)
**Verdict:** ✅ Ready

---

## 1. Summary
Effect #5 (new-message auto-scroll) is extended so that an optimistic own-message insert (id prefix `pending-`) unconditionally scrolls the viewport to the bottom, regardless of the user's current scroll position. After such a scroll, `wasNearBottomRef` is forced to `true` so subsequent incoming messages behave naturally. Other users' messages keep the previous "only scroll if near bottom" behavior. Targeted, minimal, and correctly addresses #317.

## 2. Critical Issues
None. Logic is sound and consistent with the rest of the file.

## 3. Product Impact
- ✅ Sending a message while scrolled up now jumps to the bottom — matches user expectation.
- ✅ Others' messages still won't yank focus when reading history (unchanged path).
- ⚠️ Minor behavioral nuance: once the user sends a message, `wasNearBottomRef` is pinned to `true` until the next scroll event re-evaluates it (effect #2 / scroll handler). This is intentional per the PR description and matches the "I'm now caught up" mental model, but worth flagging — if the user immediately scrolls up again before another message arrives, the scroll handler will reset the flag, so there is no lasting side effect.

## 4. Suggestions (non-blocking)
- **Helper extraction:** `lastMsg.id.startsWith("pending-")` now appears at lines 240, 272, and 313. A small `isPendingMessage(msg)` helper would deduplicate and make the "optimistic insert" concept first-class. Optional, can land in a follow-up.
- **Stability of `scrollToBottom` in deps:** the dep array uses `[messages?.length, scrollToBottom]` with an eslint-disable for exhaustive-deps. If `scrollToBottom` is not memoized with `useCallback`, this effect re-runs every render, which is harmless here (guarded by the length check) but slightly wasteful. Not a regression introduced by this PR.
- **Edge case for completeness:** if a batch update appends both an own pending message and another user's message in the same render and the server message ends up last in the array, the `lastMsg` check would miss the own message and only scroll if already near bottom. Extremely unlikely given how optimistic inserts work in this codebase (pending is appended client-side before the network round trip), so not worth guarding here, but worth keeping in mind if batch logic ever changes.

## 5. Positive Notes
- Uses the existing `pending-` convention already established elsewhere in the file — no new contract introduced.
- Comment block clearly explains the intent and the `wasNearBottomRef = true` follow-up.
- Diff stays inside effect #5; no collateral changes, no churn.
- Preserves the previous behavior path for other users' messages — low regression risk.
- Test plan in the PR body covers both the positive case (own message scrolls) and the negative case (others' messages don't yank).

## Hook / React Checks
- ✅ No stale closure risk — reads `messages` from the current effect run, refs read at call time.
- ✅ No new subscriptions or timers introduced; no cleanup needed.
- ✅ No floating promises.
- ✅ Functional updater not required — only mutating a ref, not setState.
- ✅ Consistent with surrounding patterns (same `pending-` prefix check used in effects above).

**Rating:** ✅ Ready to merge.
