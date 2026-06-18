# Nova R2 Review — cove#405 (SPEC-401 Phase 1 adapter wiring)

## Summary

This round addresses some of Round 1's findings but **the most consequential issue — lost chunking in `freshSend` — was not fixed and was instead locked in by an inverted test assertion**. The B3 test now asserts `restClient.sendMessage` directly, codifying the regression as "the contract." Double-delete on fallback is genuinely fixed via the new `draftMessageId = undefined` line in `freshSend`. The post-seal `isCurrent()` guard is partially restored in `editFinal`. Net: real progress on (2) and (4), but (1) is now both an unfixed regression and a frozen test assertion, and (5) was untouched. Escalating per the re-review rule.

## Round 1 status

| # | Finding | R1 Severity | R2 Status | R2 Severity |
|---|---------|-------------|-----------|-------------|
| 1 | Lost chunking — `freshSend` uses direct `restClient.sendMessage` | Critical | **Not addressed; test rewritten to lock in regression** | **Blocker** ⬆️ |
| 2 | Double-delete on fallback | Critical | Fixed (`draftMessageId = undefined` after delete in `freshSend` makes adapter's `clear()` a no-op for the same id) | Resolved |
| 3 | Post-seal `isCurrent()` guard lost | Critical | Partially addressed (`editFinal` re-checks `isCurrent()`); silent success has minor state-inconsistency cost | Suggestion |
| 4 | Dead `COVE_TEXT_CHUNK_LIMIT` import / stale doc | Suggestion | Fixed | Resolved |
| 5 | `freshSend` delete-before-send ordering | Suggestion | Not addressed | **Suggestion ⬆️ given #1** |
| 6 | Tests don't exercise real lifecycle | Suggestion | Partial — adapter is now real via partial mock; `createFinalizableDraftLifecycle` (seal/flush/loop) remains mocked as no-ops | Suggestion |

## Critical Issues

### C1. [Blocker] Lost chunking is now a frozen contract (escalated from R1#1)

`packages/plugin/src/dispatch.ts` lines ~94-104 — `freshSend` still calls `restClient.sendMessage(channelId, text)` directly with no chunking. Any final text > Cove's per-message limit (the 4000-char `COVE_TEXT_CHUNK_LIMIT` previously enforced via `sendDurableMessageBatch` + `formatting.textLimit`) will either be rejected by the REST API or silently truncated server-side.

What makes this worse than R1: the B3 test was **rewritten** to assert the regression instead of fixing it:

```ts
// dispatch-behavior.test.ts B3 (was, R1):
expect(sendDurableMessageBatch).toHaveBeenCalled();
// now (R2):
expect(restClient.sendMessage).toHaveBeenCalled();
```

The PR comment ("direct REST, no SDK indirection") suggests this was an intentional design choice, but `channel.ts` still imports and uses `COVE_TEXT_CHUNK_LIMIT` for `base.textChunkLimit`, indicating chunking is a real product requirement, not vestigial. Bypassing `sendDurableMessageBatch` for the final delivery path means Cove no longer gets:

1. Markdown-aware chunking at the 4000-char boundary
2. Per-chunk durable retry semantics
3. The recovery-state classification surface (`classifyDurableSendRecoveryState`) used by SDK consumers

**Required fix**: Either restore `sendDurableMessageBatch` for the `freshSend` path (the R1 recommendation) or add an explicit `text.length > COVE_TEXT_CHUNK_LIMIT → chunk` path inside `freshSend`. Revert B3 to assert the chunking-aware send. If "no SDK indirection" is genuinely the intent, document why long replies are acceptable to drop and update SPEC-401 §6 risks to include it; the current SPEC §6.2 explicitly claims `freshSend()` preserves the `sendDurableMessageBatch` call path — the code no longer matches the spec.

## Suggestions

### S1. `freshSend` delete-before-send ordering (R1#5, still present)

Lines ~94-104. The delete-then-send sequence still loses the draft on send failure. With C1 unresolved (any >4000-char text can fail), this matters more than in R1. Reorder to send-then-delete:

```ts
const freshSend = async (text: string) => {
  if (!isCurrent()) return;
  const sent = await restClient.sendMessage(channelId, text);  // throws → draft preserved
  if (draftMessageId) {
    try { await restClient.deleteMessage(channelId, draftMessageId); }
    catch (e: any) { log?.warn?.(`cove: failed to delete draft ${draftMessageId}: ${e.message}`); }
    draftMessageId = undefined;
  }
  log?.info?.(`cove: reply → [${channelId}] (${text.length} chars)`);
  return sent;
};
```

This also makes the chunked variant (C1 fix) trivially correct.

### S2. `editFinal` silent stale-skip leaves SDK state inconsistent

Lines ~118-119:
```ts
editFinal: async (id, text) => { if (isCurrent()) await restClient.editMessage(channelId, id, text); },
```

When `!isCurrent()`, `editFinal` resolves without throwing. The SDK (`live-CM5Ctqtt.js` lines 60-89) interprets resolution as success → sets `editSucceeded = true` → `markLiveMessageFinalized` → calls `onPreviewFinalized` etc. Net user-visible behavior is fine (stale dispatch → nothing happens), but the SDK's live-state machine claims a finalized preview that was never written. Today cove doesn't read `liveState`, so this is latent.

Two clean options:
- Return early from `deliver()` if `!isCurrent()` *and* skip calling the adapter entirely (the redundant `if (!isCurrent()) return;` on line ~131 was clearly added with this intent — see S5 below).
- Or make `editFinal` `throw` on stale so the adapter falls through to `handlePreviewEditError → "fallback"` and `freshSend` short-circuits via its own `isCurrent` guard.

### S3. `canFinalize` snapshot is read before `flush()` / `seal()`

Line ~136: `const canFinalize = Boolean(draftMessageId && !draftState.stopped);` is captured *before* the SDK awaits `draft.flush()` and `draft.seal()`. If the flush triggers a streaming write that errors, `draftState.stopped` flips to `true` inside the await, but `canFinalize` is still `true` → `editFinal` runs against a known-broken draft → fails → `handlePreviewEditError: "fallback"` → ends up in `freshSend` anyway.

End result is correct, but you pay one extra failing API call per such race. Either move the snapshot inside the adapter (`buildFinalEdit: (p) => draftState.stopped ? undefined : (p.text || undefined)`) or wire `canFinalizeInPlace` to a live getter via custom adapter hooks. Low priority; correctness intact.

### S4. Tests don't verify the double-delete fix (R1#2 regression guard)

H4b and H6c both check `expect(restClient.deleteMessage).toHaveBeenCalledWith("ch-1", "msg-draft-1");` but not `toHaveBeenCalledTimes(1)`. The double-delete bug from R1 would still pass these assertions. Strengthen to pin the call count, otherwise a future change that reintroduces the double-delete (e.g., dropping the `draftMessageId = undefined` line in `freshSend`) won't fail any test.

### S5. Duplicate `isCurrent()` check in `deliver()`

Lines ~131-135:
```ts
if (!isCurrent()) return;
typingCallbacks.onCleanup?.();
const text = payload.text ?? "";
if (!text) return;
if (!isCurrent()) return;   // ← duplicate, no awaits between
```

Only synchronous code between the two checks. Likely a leftover from an intermediate refactor — drop the second, or (preferred) move the surviving check to wrap the adapter call so it covers the post-seal window for real (see S2).

### S6. Lifecycle is still half-mocked (R1#6)

The R2 partial mock of `channel-message` (`real.deliverWithFinalizableLivePreviewAdapter`) is a real improvement — the adapter integration is now exercised end-to-end. But `createFinalizableDraftLifecycle` is still fully mocked with `seal: vi.fn(async () => {})` and `loop: { flush: vi.fn(async () => {}) }`. The contracts that depend on real seal semantics (A3 serialization under contention, A6 stop semantics, A7 seal-discards-pending) are still measured against a no-op. Consider a second test file that imports the real lifecycle and only mocks the REST client; keep this file for callback-wiring tests.

## Product Impact

The chunking regression (C1) directly affects the user-visible behavior: long agent replies (any tool that returns a long message — research summaries, code reviews, audit reports) will either error out at the Cove REST layer or be truncated server-side without warning. The PR description and SPEC-401 §6.2 both promise the `sendDurableMessageBatch` path is preserved; the code and tests no longer match that promise.

## Positive Notes

- The `freshSend` double-delete fix (`draftMessageId = undefined` after the delete) is the right surgical change; clean and correct given the SDK's `draft.clear()` is a no-op on an undefined id.
- Behavioral test suite H1–H7 is genuinely valuable — H4a/H4b/H4c map directly to SPEC §1.2 B1/B2/B3, H5a–H5e provide good coverage of supersession races, H7 pins the trim semantics.
- Moving `typingCallbacks.onReplyStart?.()` into `runDispatch` is a sensible ordering improvement — typing keepalive now reliably starts before the originalDispatcher's first await.
- Adapter shape (`flush/id/seal/discardPending/clear`) cleanly maps to the lifecycle's surface; the `clear` callback's `if (draftMessageId)` guard is the right shape to compose with the freshSend cleanup.
- Dropping the manual `draftState.final = true` matches SPEC §6.3 mitigation and reduces double-source-of-truth between cove and SDK.

## Verdict

**⚠️ Needs Changes**

C1 alone is blocking — it's a functional regression (long replies break) that has been locked in by a rewritten test assertion. Once chunking is restored and B3 is reverted to assert it, the remaining items are suggestions and the PR is mergeable.

— Nova 🌠

---
File: `/home/kagura/.openclaw/workspace/code-review/reviews/cove-405-nova-r2.md`
