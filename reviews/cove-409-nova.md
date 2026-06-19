# PR #409 — refactor(plugin): adopt SDK progress compositor, remove hand-written tool-progress

**Reviewer**: 🌠 Nova
**Verdict**: ✅ Ready

## Summary

This PR replaces Cove's hand-written `createToolProgressTracker` (222 lines in `tool-progress.ts` + 226 lines of unit tests) with the SDK's `createChannelProgressDraftCompositor` from `openclaw/plugin-sdk/channel-outbound`. It also removes the manual `editQueue` serialization wrapper from `sendOrEdit`, relying instead on the SDK's `createDraftStreamLoop` internal throttle+dedup. The import source for formatting helpers shifts from `channel-streaming` to `channel-outbound`. Net result: **-337 lines** of hand-maintained code with behavioral parity. All event handlers (`onToolStart`, `onItemEvent`, `onPlanUpdate`, `onApprovalEvent`, `onCommandOutput`, `onPatchSummary`, `onCompactionStart/End`, `onAssistantMessageStart`) are rewired through the compositor's `pushToolProgress`/`reset` API. Tests are updated to verify compositor interactions rather than internal tracker state. CI: 106 passed, 4 skipped, all checks green.

This is a clean, well-scoped refactor that correctly delegates complexity to the SDK. Ready to merge.

## Critical Issues

None.

## Product Impact

- **No user-facing behavior change.** The streaming UX, tool progress display, and final delivery all remain the same.
- **`onPartialReply` is no longer wired** — this is intentional and matches the Discord plugin's "progress" mode behavior. The compositor handles text composition internally, so partial reply text no longer needs to be forwarded. Multiple tests explicitly document and verify this decision (E2, H2c, H2d, H5d).
- **`editQueue` removal** — `sendOrEdit` is now a direct async function instead of chaining through a `Promise.resolve()` queue. This is safe because the SDK's `createDraftStreamLoop` (inside `createFinalizableDraftLifecycle`) already serializes calls; the old manual queue was redundant. The A3 test ("Edits sequential") still passes, confirming behavioral parity.

## Suggestions

1. **`progressDraft.markFinalReplyDelivered()`** (dispatch.ts L140) — This is called inside the `deliver` callback after two `isCurrent()` guards. Good placement, but consider whether it should also be called in error/abort paths so the compositor doesn't hold stale state. Not blocking since the compositor and dispatch are co-scoped and cleaned up together.

2. **Phase filtering duplication** — Several handlers (`onPlanUpdate`, `onApprovalEvent`, `onCommandOutput`, `onPatchSummary`) each do their own phase-gating (`if (p.phase !== "update") return;` etc.) before calling the SDK formatters. This is correct, but the pattern is repeated verbatim from the old `tool-progress.ts`. Long-term, the SDK compositor could absorb this filtering — worth a follow-up discussion with SDK maintainers, not a change for this PR.

3. **Test H2d ("onPartialReply not wired — no-op")** is nearly identical to H2c and E2. They all assert `onPartialReply` is `undefined`. Consider consolidating to reduce test maintenance surface. Minor — three assertions of the same invariant in different describe blocks is also a valid "belt and suspenders" approach.

4. **Skipped test stubs** (F4, F8) — The old versions had explanatory comments about what they test and why they're deferred. The new versions are empty stubs (`() => {}`). The skip descriptions still convey intent, but the old comment bodies were useful documentation for future implementers. Consider keeping a one-liner comment.

## Positive Notes

- **Excellent test migration.** Every old behavioral test has a clear counterpart. The tests verify compositor *interactions* (mock method calls) rather than internal tracker state, which is the right abstraction boundary for an SDK delegation.
- **Clean separation.** The PR touches exactly 2 source files (dispatch.ts + deleted tool-progress.ts) and 2 test files (dispatch-behavior.test.ts + deleted tool-progress.test.ts) plus the lockfile. No unrelated changes leaked in.
- **The `guardFwd` pattern is preserved.** All event handlers that should respect `isCurrent()` still go through the guard, and `onToolStart` has its own inline guard. Test H5c/H5e verify this thoroughly.
- **Good use of SDK affordances** — `startImmediately` option on compaction, `toolName` option on tool progress, `flush` forwarding through the update callback. Shows understanding of the compositor API surface.
- **The lockfile changes are all version bumps** (eslint, react, vitest, ws, tsx, etc.) — typical for a branch that's been rebased on an updated main. No unexpected dependency additions.
