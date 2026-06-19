# PR #409 — refactor(plugin): adopt SDK progress compositor, remove hand-written tool-progress

**Reviewer**: 🌟 Stella  
**Verdict**: ✅ Ready  

## Summary

This PR replaces Cove's hand-written `createToolProgressTracker` (and its `editQueue` serialization) with the SDK's `createChannelProgressDraftCompositor`, aligning Cove's streaming progress display with the pattern already used by Discord/Telegram plugins. It deletes `tool-progress.ts` and `tool-progress.test.ts` (448 lines), simplifies `sendOrEdit` by removing the manual `editQueue` (now handled by `createDraftStreamLoop`'s single-flight semantics inside `createFinalizableDraftLifecycle`), and updates all test cases in `dispatch-behavior.test.ts` to mock and verify the compositor API. The `onPartialReply` callback is intentionally not wired in "progress" mode, matching Discord's behavior. Net deletion of ~337 lines of application code. CI passes with 106 tests passing. Clean refactor, ready to merge.

## Critical Issues

None.

## Product Impact

- **Behavioral parity confirmed**: The compositor in `mode: "progress"` with `active: true` replicates the old tracker's behavior — gate-delayed display, tool line accumulation, compaction messages, reset on new assistant message. Users should see no change in streaming UX.
- **`onPartialReply` removed**: The old code wired `onPartialReply` to both update the tracker and push partial text to the draft. The new code does *not* wire `onPartialReply` at all, matching Discord's "progress" mode pattern. This means partial reply text is no longer streamed to draft previews. The tests explicitly verify this (`E2`, `H2c`, `H2d`, `H5d`). This is an intentional design choice (progress-only mode), but worth noting that users won't see incremental text while the model is typing — they'll only see tool progress lines, then the final reply.
- **`markFinalReplyDelivered` called but not `markFinalReplyStarted`**: The compositor exposes both methods. Only `markFinalReplyDelivered` is called (in `deliver`). Examining the SDK source, `markFinalReplyStarted` gates `pushToolProgress` and `pushCommentaryProgress` (preventing new progress after reply starts), while `markFinalReplyDelivered` gates those plus `pushReasoningProgress`. Since Cove delivers final replies in one shot (not streamed), skipping `markFinalReplyStarted` is acceptable — `markFinalReplyDelivered` is the stronger guard and covers it.

## Suggestions

1. **`sendOrEdit` race window** (`dispatch.ts:47-65`): The old `editQueue` serialized concurrent calls. Now `sendOrEdit` is a plain async function. The SDK's `createDraftStreamLoop` provides single-flight semantics for `draft.update()` calls, but `sendOrEdit` is also called directly by `draft.seal()` / finalize paths. If two callers hit `sendOrEdit` concurrently before `draftMessageId` is set, both could execute `restClient.sendMessage` and create duplicate messages. In practice this is unlikely (the draft loop throttles to 250ms and the compositor internally coalesces), but a comment documenting why `editQueue` removal is safe would help future readers.

2. **Unused compositor capabilities**: The compositor offers `pushReasoningProgress` and `pushCommentaryProgress` which aren't wired. Consider a TODO comment noting these could be connected to `onReasoningDelta`/commentary events in a future PR for richer progress display.

3. **Test cleanup** (`dispatch-behavior.test.ts`): Tests `H2d` ("onPartialReply not wired — no-op") and `E2` ("onPartialReply not wired in progress mode") assert the same thing. `H2d` could be collapsed into `E2` or given a more distinct description.

4. **Skipped tests `F4`/`F8`**: The skip bodies were cleaned to empty `() => {}` but the skip comments explaining *why* were removed. The original comments were useful context for future contributors. Consider keeping a one-liner explanation.

## Positive Notes

- **Excellent deletion ratio**: -2438/+974 (most of the additions are lockfile churn), with ~337 net lines of application code removed. The hand-written tracker + editQueue were significant maintenance surface.
- **Clean SDK adoption**: The compositor wiring is straightforward — `pushToolProgress` for each event type, `reset` for state transitions, `markFinalReplyDelivered` for finalization. Matches Discord plugin patterns closely.
- **Thorough test migration**: All E-series and H-series tests were updated to verify compositor interactions rather than tracker internals. The tests now validate integration behavior (compositor mock verification) rather than internal state, which is more resilient to future SDK changes.
- **Phase-filtering preserved**: The `onPlanUpdate` (`phase !== "update"`), `onApprovalEvent` (`phase !== "requested"`), `onCommandOutput`/`onPatchSummary` (`phase !== "end"`) guards are correctly carried over from the old tracker, keeping the same event filtering semantics.
