# 🌠 Nova Review — cove PR #290

**PR:** fix: remove dispatch timeout — match Discord plugin behavior
**Verdict:** **Approve with Comments** ✅
**Scope:** +9 / −122 across `dispatch.ts`, `channel.ts`, `dispatch-resilience.test.ts`

---

## Summary

The change is correct and well-motivated. The 120 s `createAbortableDispatch` timeout was silently dropping legitimate agent responses (observed twice in production). Removing it aligns Cove with the Discord plugin, which is the de-facto reference behavior. The abort-on-superseding-message path is preserved through `pendingDispatches` + `isCurrent()` guards.

No bugs introduced. A couple of cleanup/testing observations below — none block merge.

---

## Correctness

- ✅ The abort branch logic survives the change. Previously the dispatch error was checked via `instanceof DispatchAbortedError`; now it's checked via `abortController.signal.aborted`, which is functionally equivalent and arguably more honest (the previous custom error class was only ever produced by the wrapper that's being deleted).
- ✅ Re-export removal in `channel.ts` is consistent with the deletion in `dispatch.ts`. `grep` across the repo (`createAbortableDispatch | DispatchTimeoutError | DispatchAbortedError | dispatchTimeoutMs`) shows zero remaining references.
- ✅ `dispatchTimeoutMs` config knob is removed cleanly — no orphan references in code or schema files.
- ⚠️ **Minor pre-existing nit (not from this PR):** the inner runtime (`dispatchInboundDirectDmWithRuntime`) is **not** wired to `abortController.signal`. So even before this PR, "abort" never actually cancelled the in-flight runtime work — it only short-circuited the wrapper's promise. After this PR the situation is unchanged: abort is enforced purely by `isCurrent()` guards in the deliver / streaming callbacks, which prevents stale writes but doesn't stop CPU/network work. Worth noting in a follow-up issue, but out of scope here.

## Security / Resource Use

- ⚠️ **Resource consideration (not a blocker):** removing the timeout means a stuck or runaway agent run on a channel will now hold an `AbortController` + closure state indefinitely until a new message arrives in the same channel (or process restart). This matches Discord plugin behavior, so consistency wins, but on a busy server this could accumulate. Consider a generous safety ceiling (e.g. 10–15 min) in a future PR — clearly tagged as a backstop rather than a UX timeout.
- ✅ No new injection / authz / secret-handling surface.

## Performance

- Neutral. One less `setTimeout` + listener pair per dispatch. Negligible.

## Readability

- ✅ Code is simpler and easier to reason about; the deleted `createAbortableDispatch` was a non-trivial 3-way race.
- 🟡 The `try { await dispatchInboundDirectDmWithRuntime({ ... }); }` block keeps the awkward 8-space indentation from the previous nested call. Re-indenting to 6 spaces would tidy the diff, but it's purely cosmetic.

## Testing

- 🟡 **Real concern, but minor for a small project.** The new tests in `dispatch-resilience.test.ts` no longer exercise production code — they only construct `AbortController`s and assert `signal.aborted === true` after `.abort()`. That's testing the standard library, not Cove. The actual abort-on-supersede behavior (the `pendingDispatches.get(channelId).abort(); set(channelId, newController)` block inside `dispatchMessage`) is now uncovered by unit tests.
  - Suggestion (follow-up): keep a lightweight integration test that calls `dispatchMessage` twice with the same `channelId` and a mocked `dispatchInboundDirectDmWithRuntime`, then asserts the first controller is aborted and `isCurrent()` short-circuits the first deliver callback.
  - Alternative cheap fix in this PR: delete the two now-tautological tests outright rather than keep them as scaffolding that gives false assurance.
- ✅ Removing the timeout-specific tests is correct — they would all fail or be meaningless against the new code.

## Input Validation / API Design

- ✅ Removal of the `dispatchTimeoutMs` knob is a small breaking change for any user who set it in config, but per the PR description that knob was actively harmful. Acceptable.
- Optional: add a one-liner CHANGELOG / release-notes entry noting that `channels.cove.dispatchTimeoutMs` is now ignored, so any operator who set it isn't surprised.

## Product Impact

- ✅ Directly fixes a user-visible silent-failure bug (#285). Two reproductions today justify shipping fast.
- ✅ Behavior now matches Discord plugin → fewer surprises across channels.

## AI-Generated Code Failure-Mode Checklist

| Check | Result |
|---|---|
| Catch-all error swallowing | No new instances; outer `catch` is pre-existing. |
| Hardcoded success | None. |
| Premature abstraction | Opposite — removing one. ✅ |
| Dead code | None left behind (grep clean). |
| Hallucinated APIs | None. |
| Plausible-but-wrong logic | None. `signal.aborted` check is correct. |
| Inconsistency with surrounding code | None — aligns with Discord plugin. |

## TypeScript Checklist

- ✅ No new `any` introduced.
- ✅ No floating promises added (the `dispatch.catch(() => {})` orphan-suppression line was specific to the deleted wrapper and is no longer needed since `await` propagates errors directly).
- ✅ No new null-safety issues.
- ✅ Error boundary in the `try/catch/finally` around the runtime call is preserved.

---

## Recommendation

**Merge.** The fix is small, targeted, and removes a real footgun. Two soft follow-ups worth a tracking issue:

1. Either delete or rewrite the two tautological tests in `dispatch-resilience.test.ts` so coverage of the supersede-abort path is honest.
2. Consider wiring `abortController.signal` into `dispatchInboundDirectDmWithRuntime` (or adding a generous safety ceiling) so abort actually cancels in-flight runtime work rather than just gating downstream writes.

— 🌠 Nova
