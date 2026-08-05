# Independent review — kagura-agent/cove PR #510

**PR:** `fix(plugin): verify final reply delivery outcomes`  
**Head reviewed:** `1a933bf69cff62fe71bb3c0675afbc45baa268b5`  
**Verdict:** **Request changes**

## Scope and method

Reviewed the exact PR head in an isolated Git worktree, inspected the PR diff and its targeted tests, and compared its final-delivery handling against the installed OpenClaw channel-message SDK contract and finalizable-preview helper.

The intended improvement is sound: a resolved durable call must not by itself be interpreted as a visible final message. The new checks cover failed, partial, malformed, and unknown outcomes; successful in-place preview finalization remains a proper visible final delivery; and fallback success deletes the preview only after the normal send succeeds.

## Blocking findings

### P1 — Intentional durable suppression is incorrectly converted into a delivery failure

**Evidence**

- `packages/plugin/src/outbound.ts:31-34` accepts only `result.status === "sent"`; it throws for every other documented status.
- OpenClaw explicitly models `"suppressed"` as a normal durable outcome with a receipt and a reason (`channel-message-jidZ1m78.d.ts:203-215`).
- `sendDurableMessageBatch()` itself commits both `"sent"` **and** `"suppressed"` outcomes (`send-ld3lzjwT.js:168-175`).
- The durable state model also has a distinct `suppressed` terminal state (`channel-message-jidZ1m78.d.ts:151-172`).
- The final-delivery test matrix in `packages/plugin/src/dispatch-behavior.test.ts:272-286` has no suppressed-outcome case.

**Impact**

A message-sending hook that intentionally cancels the final reply, reduces it to no visible payload, or causes the adapter to return no identity will produce the SDK's successful **no-send** result. This patch turns that result into an exception. `dispatch.ts:123-130` then marks the payload as “recoverable,” propagates an error through the dispatcher, and its cleanup path removes the progress preview. That is the opposite of the SDK's suppression/no-send contract and can create false delivery failures, erroneous retries/recovery, and misleading error logs for policy-controlled suppression.

This diverges from OpenClaw’s explicit `handled_no_send` final-delivery result, which is treated as handled rather than failed (`kernel-CNkk_fVx.d.ts:35-48`).

**Recommended fix**

Preserve the three semantic classes instead of collapsing them into sent-or-error:

- `sent`: require a visible receipt/identity and report success.
- `suppressed`: return an explicit no-send signal (for example `false` from the normal-delivery callback, if that is the dispatcher contract) and do **not** attach a recoverable payload or throw.
- `failed` / `partial_failed` / malformed or unconfirmed sent result: throw, retaining the original failure as the error cause.

Add a regression that starts a preview, returns a `suppressed` batch outcome, asserts that no recovery error is emitted, and asserts the chosen preview-cleanup/no-send behavior.

### P1 — The check rejects a valid, peer-compatible successful SDK response because `payloadOutcomes` is optional

**Evidence**

- The plugin declares `openclaw: ">=2026.3.0"` in `packages/plugin/package.json`.
- `packages/plugin/src/outbound.ts:36-39` throws whenever `payloadOutcomes` is absent.
- In the OpenClaw SDK type used by the repository, a `status: "sent"` result has a required `receipt` and `results`, while `payloadOutcomes` is optional (`channel-message-jidZ1m78.d.ts:203-208`).
- The same contract defines a visible receipt as `platformMessageIds` (and an optional primary ID) (`types-4cKgiLCG.d.ts:39-48`).
- The test mock was changed at `packages/plugin/src/dispatch-behavior.test.ts:41-50` so every ordinary success contains `payloadOutcomes`; no regression exercises a valid sent result with a visible receipt but without the optional field.

**Impact**

For any supported OpenClaw version or compatible implementation that returns the documented successful result without `payloadOutcomes`, every normal Cove final send now fails after the platform has already accepted it. The result is a false “undelivered” final, potential recovery/retry duplication, and loss of normal finalization behavior. The repository lock currently resolves a newer OpenClaw version, but the broad peer range expressly allows the older shape; a plugin must either maintain that compatibility or raise its peer minimum to the version that makes outcomes mandatory.

**Recommended fix**

Use the stable visible receipt as the primary success proof:

1. Require `status === "sent"`.
2. Validate one or more non-empty `receipt.platformMessageIds` (or a non-empty primary platform ID, if the SDK permits that representation).
3. If `payloadOutcomes` is present, validate its ordering and per-payload visible IDs as additional consistency checks.

Alternatively, make `payloadOutcomes` mandatory only after raising the `openclaw` peer minimum to the SDK version that guarantees it, and document the compatibility break. Add a test for `{ status: "sent", results, receipt }` without `payloadOutcomes`.

## Non-blocking implementation notes

- **[Verified] Preview/fallback ordering is otherwise improved.** The helper only clears a preview after `deliverNormally` succeeds (`live-CM5Ctqtt.js:101-110`). Cove’s `freshSend` deletes the stale preview before attempting the fallback and clears its message ID (`dispatch.ts:115-133`), so a failed fallback does not leave a frozen preview. The new B2a test covers that path (`dispatch-behavior.test.ts:248-270`).
- **[Verified] The thrown durable errors discard diagnostic causes.** `assertConfirmedVisibleDelivery()` constructs generic errors at `outbound.ts:32-49`, so a `partial_failed` or `failed` outcome’s `error` is not included as `cause` or message detail. This makes final fallback incidents harder to diagnose than necessary. Preserve `result.error` as `new Error(..., { cause: result.error })` (or append a safely formatted message) while retaining the no-false-success rule.
- **[Verified] Success receipt data is validated but not surfaced by the bridge.** `sendCoveDurableBatch()` discards `result` after validation and `sendText()` returns `{}` (`outbound.ts:54-87`), although `ChannelMessageOutboundBridgeResult` can carry a receipt. This is pre-existing rather than introduced by the PR, so it is not a blocker for this change, but returning the receipt would make the visible-delivery guarantee auditable by higher layers.

## Test assessment

- **[Verified] PR CI reported `test` passing (49s) and deployment checks passing when queried on 2026-08-05.**
- **[Verified] I attempted the advertised focused command in the isolated PR worktree:**
  ```sh
  pnpm --filter openclaw-cove exec vitest run src/dispatch-behavior.test.ts
  ```
  It could not run locally because that linked worktree has no installed `vitest` binary (`ERR_PNPM_RECURSIVE_EXEC_FIRST_FAIL: Command "vitest" not found`). I did not install or modify dependencies for the review.

## Required regression coverage before approval

1. `status: "suppressed"` (including a hook-cancel reason): assert handled no-send semantics, no recovery error, and correct preview disposition.
2. `status: "sent"` with a valid visible `receipt` but no `payloadOutcomes`: assert delivery succeeds for the declared peer range.
3. Failed and partial outcomes: assert the original platform error remains inspectable as the thrown error/cause.
4. Existing preview-finalized, edit-failure/fallback-success, and failed-fallback stale-preview-cleanup cases should remain green.
