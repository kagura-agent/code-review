# Round 2 Review — cove PR #405

## Summary

This update wires Cove final delivery through the SDK live-preview finalizer and adds a large SPEC-401 behavioral test suite. Two of the prior critical lifecycle issues look addressed in the implementation, but the most user-visible blocker remains: fresh final sends now use direct `restClient.sendMessage`, so final replies that exceed Cove's text limit are no longer chunked. The tests were also changed to assert the regressed behavior instead of preserving the old contract. **Rating: ❌ Major Issues**

## Critical Issues

### 1. [Critical — escalated from Round 1] Fresh final sends still bypass SDK chunking

- **Where:** `packages/plugin/src/dispatch.ts:95-105`, `packages/plugin/src/dispatch-behavior.test.ts:205-214`
- **Previous finding:** `freshSend()` used direct `restClient.sendMessage` instead of `sendDurableMessageBatch`, dropping automatic chunking for messages > 4000 chars.
- **Round 2 status:** **Not addressed.** The updated code explicitly documents fresh sends as “direct REST, no SDK indirection” and calls `restClient.sendMessage(channelId, text)` directly. The B3 test was also changed from expecting `sendDurableMessageBatch` to expecting `restClient.sendMessage`, which locks in the regression.
- **Why this blocks merge:** Any fresh final delivery path can produce a long assistant response: no draft, stopped draft, or final-edit fallback. Those paths no longer use `COVE_TEXT_CHUNK_LIMIT` / markdown chunking, so long replies can fail, truncate, or be rejected by Cove instead of being split into valid messages. This is a real product regression in final answer delivery.
- **Fix:** Restore `sendDurableMessageBatch` in `freshSend()` using Cove's configured chunk limit (or route through the existing outbound/message adapter that applies `COVE_TEXT_CHUNK_LIMIT`). Add/restore a regression test that sends a payload above the chunk limit and asserts multiple Cove sends / SDK batch delivery rather than one direct `sendMessage`.

## Product Impact

- Long final replies are at risk in exactly the cases where users most need reliability: fresh responses, fallback after preview edit failure, and recovery from stopped previews.
- The new adapter integration otherwise moves Cove closer to SDK-managed preview finalization, which is a good direction, but it should preserve final delivery durability/chunking before merge.

## Suggestions

### 1. Previous critical double-delete appears addressed, but keep a regression test against the real failure mode

- **Where:** `packages/plugin/src/dispatch.ts:96-118`, SDK finalizer behavior via `deliverWithFinalizableLivePreviewAdapter`
- **Round 2 status:** Addressed in the current flow. `freshSend()` clears `draftMessageId = undefined` after deleting, so the SDK `draft.clear()` finally step should not delete the same draft again.
- **Suggestion:** Keep or add an explicit test that final-edit fallback deletes the orphan draft exactly once. The current tests assert deletion occurred, but not that it only occurred once.

### 2. Previous post-seal staleness guard is partially addressed; test the race after `seal()`

- **Where:** `packages/plugin/src/dispatch.ts:121-145`
- **Round 2 status:** The adapter's `editFinal` now checks `isCurrent()` before editing, which prevents a stale dispatch from editing after the SDK seals the draft. That addresses the visible safety issue.
- **Remaining gap:** The added stale tests cover supersession before `deliver()` starts (`H5b`), not the specific race where `isCurrent()` flips after `draft.seal()`/flush but before `editFinal()`.
- **Suggestion:** Add a test where `draft.seal()` supersedes the dispatch before resolving, then assert no final edit/fresh send occurs.

### 3. Delete-before-send ordering remains risky

- **Where:** `packages/plugin/src/dispatch.ts:96-104`
- **Previous finding:** `freshSend()` deletes the draft before sending the replacement.
- **Round 2 status:** Still present.
- **Why it matters:** If the fresh send fails, the user loses both the preview draft and the final response. Prefer send-first-then-delete for fallback recovery, or at least only delete once replacement delivery is confirmed.

### 4. SPEC status is still misleading for the actual diff

- **Where:** `packages/plugin/SPEC-401.md:3-5`, `packages/plugin/SPEC-401.md:222-240`, `packages/plugin/src/dispatch.ts:107-145`
- **Round 2 status:** Still inconsistent. The spec says “Phase 0 (behavioral tests only, no implementation changes)”, but the PR includes Phase 1 implementation changes: adapter definition and `deliverWithFinalizableLivePreviewAdapter` wiring.
- **Suggestion:** Update the status to reflect that this PR includes Phase 1, or split implementation from behavioral tests.

## Positive Notes

- The prior dead import/comment issue was cleaned up: `COVE_TEXT_CHUNK_LIMIT` is no longer imported in `dispatch.ts`, and the stale JSDoc was replaced.
- The adapter keeps `sendOrEdit`, `editQueue`, and `createFinalizableDraftLifecycle` in place, avoiding the PR #399 race regression.
- Local verification passed: `pnpm -F openclaw-cove test -- packages/plugin/src/dispatch-behavior.test.ts` reported 8 test files passed, 125 tests passed, 4 skipped.
