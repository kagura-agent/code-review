# Stella review — kagura-agent/cove PR #510

**Verdict: ⚠️ Needs Changes**

## Summary

This PR correctly recognizes that a resolved `sendDurableMessageBatch()` call is not automatically a successful final delivery, and it improves the failed/partial/malformed outcome coverage. However, the confirmation gate changes valid OpenClaw terminal states into delivery failures and makes `payloadOutcomes` mandatory even though the SDK declares it optional. That breaks compatibility with valid send results and violates the no-send/suppression contract. The preview cleanup path also loses the only draft ID after a failed delete, so the newly claimed failed-fallback cleanup is not reliable.

## Must fix

### 1. `payloadOutcomes` is optional, so valid visible sends are now rejected
**File:** `packages/plugin/src/outbound.ts:36-49`  
**Severity:** P1 / correctness

`assertConfirmedVisibleDelivery()` throws whenever `payloadOutcomes` is absent (lines 36-39), even if the batch returned the valid `status: "sent"` result and a visible `results`/`receipt` message ID. In the installed OpenClaw SDK contract, `payloadOutcomes` is explicitly optional on `status: "sent"`; its documentation describes `sent` as “at least one visible platform message was delivered,” and reserves `payloadOutcomes` for batches that mix sent/suppressed/failed payloads.

Consequently, a normal successful final reply from an older compatible SDK or an SDK path that omits per-payload outcomes is converted into an error, marked recoverable, and its preview is removed. The PR's new global mock at `dispatch-behavior.test.ts:44-49` always supplies `payloadOutcomes`, so it cannot catch this regression.

Accept a `sent` result with a verifiable visible receipt/result when `payloadOutcomes` is absent. If outcomes are present, validate the requested payload's outcome; do not require an optional compatibility field for the all-sent case. Add a regression for `{ status: "sent", results: [{ channel: "cove", messageId: "…" }], receipt: … }` without `payloadOutcomes`.

### 2. Valid suppression/no-send outcomes are incorrectly treated as failed final delivery
**File:** `packages/plugin/src/outbound.ts:31-39`  
**Severity:** P1 / product behavior

The first guard treats every status other than `sent` as an error. That includes the SDK's `suppressed` outcome, whose contract is specifically that no platform message should be treated as missing (for example, a message-sending hook cancelled it or the rendered payload became empty). Feishu/Discord's shared durable flow preserves this distinction rather than retrying or reporting a missing reply.

For Cove, a normal suppression will now throw through `freshSend()` (`dispatch.ts:122-130`), attach `coveFinalPayload`, and log that the final message “remains recoverable.” This turns an intentional no-send into an apparent failed send and may trigger inappropriate recovery/error handling. It is especially misleading because `progressDraft.markFinalReplyDelivered()` has already been called before the durable result is examined (`dispatch.ts:185-194`).

Return a distinct, non-error suppression result to the dispatcher (or explicitly model suppression as a completed no-send) and only attach recovery payload/error state for `failed` and appropriately handled `partial_failed` outcomes. Add tests for hook cancellation / `status: "suppressed"` both with and without a visible preview.

### 3. Failed fallback can still leave the stale preview permanently visible
**File:** `packages/plugin/src/dispatch.ts:115-119, 346-351`  
**Severity:** P1 / stale-preview cleanup

`freshSend()` clears `draftMessageId` unconditionally after attempting `deleteMessage()`. If deleting the preview rejects (for example, a transient REST failure) and the durable fallback then fails, the finalizer has no draft ID left. The orphan cleanup condition at lines 346-351 is skipped, so it cannot retry cleanup and the stale progress preview remains visible.

The new B2a test only covers a successful preview delete (`dispatch-behavior.test.ts:248-269`), so it validates the happy cleanup branch rather than the failure condition this PR claims to handle. Retain the ID until deletion succeeds, or preserve a separate orphan ID for final cleanup/retry. Add a test where `deleteMessage` rejects before a failed durable fallback and assert the finalizer makes a cleanup attempt using the retained ID.

## Tests

The PR adds useful coverage for `failed`, `partial_failed`, malformed outcomes, and a preview-edit failure with a successful fallback. It is still missing the three contract boundaries above:

- valid `sent` without optional `payloadOutcomes`;
- intentional `suppressed` / no-send behavior;
- preview delete failure followed by failed fallback.

I inspected the PR head `1a933bf69cff62fe71bb3c0675afbc45baa268b5`, its GitHub CI status (test passed), the local OpenClaw SDK declarations/documentation, and OpenClaw's Discord/Feishu final-delivery paths. I did not post to GitHub or run the local plugin suite: the available Cove checkout is on another dirty branch and the PR itself documents that its linked environment cannot resolve the matching SDK dependency tree.

## Positive notes

- The PR correctly stops treating `partial_failed`, malformed per-payload results, and unknown statuses as successful visible deliveries.
- Preserving the failed payload on the thrown error (`dispatch.ts:124-130`) is a useful recovery signal once it is limited to genuine failures.
- The added behavioral test names make the expected preview-finalization behavior clearer.
