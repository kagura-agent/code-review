# Stella Review — cove PR #405

## Summary

This PR is a careful step toward SDK-managed live preview finalization and adds a broad behavioral safety net, but it is not ready as-is. The adapter API exists and the basic edit-in-place path is wired correctly, yet the refactor changes important failure semantics around final delivery: fresh fallback now deletes the draft before the replacement message is confirmed, long fresh replies no longer use the existing chunking path, and the previous post-`seal()` staleness guard is lost inside the adapter call.

**Rating: ⚠️ Needs Changes**

## Critical Issues

1. **Fallback/fresh-send can delete the only visible draft before the final message is successfully sent**  
   `packages/plugin/src/dispatch.ts:97-103`

   The old `freshSend()` sent the durable/fresh message first and only deleted `draftMessageId` after that send completed. The new implementation deletes the draft before calling `restClient.sendMessage()`. If the final edit fails and the fallback send then fails (network, validation, Cove API error), the user loses the draft preview and receives no final response. This is a real behavior regression from the previous “fallback to fresh send + delete orphan draft” contract.

   Please preserve the old ordering: send/chunk the fresh final response successfully first, then best-effort delete the orphan draft. Add a test where `restClient.sendMessage` rejects during fallback and assert `deleteMessage` is not called before the send succeeds.

2. **Removing `sendDurableMessageBatch` drops fresh-send chunking for replies over `COVE_TEXT_CHUNK_LIMIT`**  
   `packages/plugin/src/dispatch.ts:95-103`, `packages/plugin/src/types.ts:18-19`, `packages/plugin/src/channel.ts:55`

   `sendDurableMessageBatch` was previously called with `formatting: { textLimit: COVE_TEXT_CHUNK_LIMIT }`, which split long final replies into multiple messages. The new direct `restClient.sendMessage(channelId, text)` path sends the entire final text as one Cove message. Cove still declares a 4000-character text limit, and `CoveRestClient.sendMessage()` does not chunk. Any fresh final delivery over that limit can now fail or be rejected/truncated by the API.

   The PR context says `sendDurableMessageBatch` was removed because it silently failed in #404; that motivation is valid, but the replacement still needs equivalent chunking. Either implement explicit markdown/text chunking around direct REST sends, or use a fixed SDK path that propagates errors while preserving `COVE_TEXT_CHUNK_LIMIT`. Add a regression test with final text longer than 4000 chars and assert multiple `sendMessage` calls.

3. **The post-`seal()` `isCurrent()` guard was not preserved inside the SDK adapter path**  
   `packages/plugin/src/dispatch.ts:131-144`, especially `editFinal` at `packages/plugin/src/dispatch.ts:120`

   The previous manual delivery path checked `isCurrent()` once before delivery and again after `await draft.seal()` before editing/fresh-sending. The new code checks before entering `deliverWithFinalizableLivePreviewAdapter()`, but the SDK then awaits `draft.flush()`/`draft.seal()` and calls `editFinal()` without another Cove staleness check. If a dispatch is superseded while flush/seal is in flight, a stale dispatch can still edit the draft into a final message.

   Please reintroduce the guard in the adapter boundary, e.g. have `editFinal` and `deliverNormally` no-op/return false when `!isCurrent()`, or wrap the draft operations so the post-seal check is preserved. Add a test that supersedes `pendingDispatches` while `draft.seal()` is pending and verifies no final edit/send occurs.

## Product Impact

- Long answers that previously arrived as chunked messages may now fail in fresh-send paths.
- On fallback send failure, users may see the in-progress draft disappear and receive no answer at all.
- Race conditions with superseded dispatches can reintroduce stale final edits in active Cove channels.

## Suggestions

1. **Use the existing lifecycle `draft.clear()` for adapter clearing, or clear `draftMessageId` after deletion.**  
   The adapter’s custom `clear` duplicates deletion logic and does not clear the local `draftMessageId`. Because the SDK calls `deliverNormally()` and then `draft.clear()` after successful fallback delivery, the current code can attempt to delete the same draft twice: once in `freshSend()` and once in adapter `clear()`. This is likely noisy rather than catastrophic, but using `clear: () => draft.clear()` would better preserve the SDK lifecycle semantics.

2. **Tighten SPEC-401 so it matches the actual PR.**  
   `packages/plugin/SPEC-401.md:3-5` still says “Phase 0 (behavioral tests only, no implementation changes)”, but this PR also performs Phase 1 adapter wiring. Section 6.2 also says Phase 1 preserves the same `sendDurableMessageBatch` path, while the actual diff removes it. Please update the spec before merge so future reviewers do not treat stale text as the source of truth.

3. **Strengthen the new tests around the actual regressions.**  
   The 23 Group H tests cover many happy-path contracts, but they miss the highest-risk cases above: fallback send failure ordering, long fresh-send chunking, and supersession during an awaited `seal()`. Also, the mocked lifecycle does not model real `createFinalizableDraftLifecycle` state transitions, so these tests are best viewed as wiring tests rather than full SDK behavior proof.

4. **Remove stale comments/imports after deciding the final send path.**  
   `dispatch.ts` now has back-to-back contradictory comments above `freshSend()`, and `COVE_TEXT_CHUNK_LIMIT` is still imported into `dispatch.ts` but unused. This is minor, but cleaning it up will make the intended delivery path clearer.

## Positive Notes

- The basic `defineFinalizableLivePreviewAdapter` shape matches the SDK type contract: `draft.flush/id/seal/discardPending/clear`, `buildFinalEdit`, `editFinal`, and fallback-on-preview-edit-error are all present.
- Moving `typingCallbacks.onReplyStart()` into `runDispatch` is a good behavioral fix for keepalive during longer tool execution.
- Keeping `sendOrEdit`, `editQueue`, and the existing draft lifecycle in place is the right conservative migration strategy after the PR #399 race issues.
- The added Group H tests are useful as a regression scaffold; they just need a few more adversarial cases around the failure paths introduced by this refactor.
