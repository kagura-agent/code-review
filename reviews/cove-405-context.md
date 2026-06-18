# PR #405 Context

**Repo:** kagura-agent/cove
**PR:** #405
**Title:** refactor(plugin): adopt SDK delivery adapter + typing keepalive (#401)
**Branch:** refactor/401-draft-preview-v2 → main
**Stats:** +931 / -35, 3 files changed

## Files Changed
1. `packages/plugin/SPEC-401.md` — NEW (326 lines) — detailed spec document for the refactor
2. `packages/plugin/src/dispatch-behavior.test.ts` — +568/-12 — 23 new behavioral tests (Group H)
3. `packages/plugin/src/dispatch.ts` — +37/-23 — core delivery refactor

## What This PR Does

Phase 0-1 of #401 (incremental SDK adoption for dispatch):

1. **`deliverWithFinalizableLivePreviewAdapter`** — replaces hand-written if/else final delivery logic in `deliver()` with SDK adapter pattern. Defines cove-specific adapter via `defineFinalizableLivePreviewAdapter` with draft operations, buildFinalEdit, editFinal, handlePreviewEditError.

2. **Typing keepalive fix** — moves `typingCallbacks.onReplyStart()` into `runDispatch` so typing fires at dispatch start and maintains 5s keepalive during tool execution (previously typed once then disappeared).

3. **`sendDurableMessageBatch` removal** — `freshSend()` now uses direct `restClient.sendMessage()` instead of SDK's `sendDurableMessageBatch` (which was found to silently succeed without delivering in PR #404).

4. **23 new behavioral tests** (Group H) — lock down draft streaming lifecycle contracts before further implementation changes.

## Important Background
- PR #399 attempted full SDK adoption and failed (duplicate streaming, race conditions)
- PR #400 took conservative approach (behavioral tests as safety net)
- This PR continues incrementally: tests first, then minimal adapter wire-up
- The spec review (spec-401) identified multiple concerns about SDK API semantics — this PR addresses some by verifying APIs exist and work

## Review Focus Areas
- Does the `deliverWithFinalizableLivePreviewAdapter` wiring preserve existing behavior?
- Is the `liveState` construction (`canFinalize` flag) correct?
- Does `freshSend` revert from `sendDurableMessageBatch` to direct `restClient.sendMessage` lose chunking?
- Are the 23 new tests sufficient for the behavioral contracts they claim to lock down?
- Is the SPEC-401.md accurate and complete?
