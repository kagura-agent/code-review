# Review: kagura-agent/cove PR #510 — Nova

## Verdict: ⚠️ Needs Changes

The PR correctly stops treating `partial_failed`, malformed `sent`, and unknown durable results as a confirmed visible final, and the preview-edit fallback continues to remove its stale draft before a fresh send. However, it changes two valid SDK outcomes into failures and does not actually propagate/persist a failed fallback for recovery. Those paths break the OpenClaw final-delivery contract the PR is trying to match.

## Critical issues

### 1. `suppressed` is an intentional no-send outcome, not a failed final delivery
**Severity: P1 — must fix**

`assertConfirmedVisibleDelivery()` rejects every status other than `"sent"` (`packages/plugin/src/outbound.ts:31-34`). That includes the SDK's `"suppressed"` result, whose contract is a terminal intentional no-send (for example a cancelled send hook or dry-run), rather than an absent message that must be recovered. The installed OpenClaw durable-send API declares `suppressed` separately from `failed`, with a reason and a receipt; its lifecycle documentation explicitly says it means “No platform message should be treated as missing.”

Consequently, a deliberately suppressed final enters `freshSend`’s error path (`packages/plugin/src/dispatch.ts:123-130`), is labelled “recoverable”, and is surfaced as a fallback failure. That is not Feishu/Discord-style suppression semantics: it turns a deliberate no-op into an error/retry candidate and can cause erroneous recovery output.

Handle `suppressed` explicitly as an intentional **normal-skipped/no-send** result. Do not attach an undelivered payload or treat it as a transport failure. Add a regression that verifies: no visible send, no recovery warning/error, no duplicate fallback, and stale preview handling is intentional.

### 2. A valid `sent` result is rejected merely because optional `payloadOutcomes` are absent
**Severity: P1 — must fix**

The SDK type makes `payloadOutcomes` optional even on a `status: "sent"` result. The new implementation requires it to be an array of exactly one element (`packages/plugin/src/outbound.ts:36-39`) and therefore rejects a successful durable send that provides a valid `receipt.platformMessageIds` / `results` but omits this optional diagnostic detail.

This is a compatibility and product regression for the plugin’s declared `openclaw >=2026.3.0` peer range: a runtime can confirm a visible receipt and still have Cove report delivery failure. The changed test default now manufactures `payloadOutcomes` (`packages/plugin/src/dispatch-behavior.test.ts:44-49`), so it masks rather than tests that compatibility path.

Accept a confirmed receipt/result when per-payload outcomes are unavailable; when outcomes are present, validate them as additional evidence. Add a test for `{ status: "sent", receipt: { platformMessageIds: ["…"] } }` without `payloadOutcomes`, plus a test rejecting an empty/missing receipt.

### 3. Failed fallback is neither durable nor observable to the real dispatch caller
**Severity: P1 — must fix**

The PR claims the final payload remains recoverable, but it only mutates the transient thrown `Error` (`packages/plugin/src/dispatch.ts:123-130`) and retains the text in a local variable that is later only logged (`:353-355`). The outer dispatch catch then consumes that error (`:357-358`), so `dispatchMessage()` resolves after logging it. No durable retry/recovery record is created, and no caller receives the annotated error.

The new test calls the captured `deliver` closure directly and observes the temporary property (`packages/plugin/src/dispatch-behavior.test.ts:248-269`); it does not exercise the real `dispatchMessage()` boundary, where that error is swallowed. Thus it cannot prove the advertised recovery behavior.

Either route the failure through the kernel’s supported durable-recovery/error contract, or explicitly remove the “recoverable” claim and preserve a correctly classified failed dispatch for the caller. Add an integration-level test through `dispatchMessage()` that proves the selected recovery/error behavior and verifies no stale preview remains.

## Product impact

As written, hook-cancelled/dry-run finals can be converted into failed responses, and legitimate successful sends can be reported as delivery failures. More seriously, an actual fallback failure leaves users with neither a final message nor a durable retry path despite the new log claiming otherwise. This is exactly the user-visible silent-loss gap the PR intends to close.

There is also an adjacent no-send concern worth covering: `freshSend()` returns `undefined` when it observes an abort (`packages/plugin/src/dispatch.ts:110-114`), while the live-preview helper only recognizes `false` as “normal skipped.” The result is then unconditionally recorded as delivered at `:194`. This code predates the patch, but the new outcome-validation tests should include it; otherwise the final-delivery invariant remains false for abort/no-send races.

## Suggestions

- Keep the strict visible-ID validation for present `payloadOutcomes`, but put it in a small result classifier that returns one of `delivered`, `suppressed`, or `failed`. This will make the distinction auditable and avoid relying on exceptions for normal control flow.
- Include the durable outcome status/reason in the warning/error for genuine failures (without logging reply text) to make production triage actionable.

## Positive notes

- Rejecting `partial_failed`, unknown statuses, and malformed outcomes is the right direction for avoiding false positive “delivered” state (`packages/plugin/src/outbound.ts:31-50`; `dispatch-behavior.test.ts:272-285`).
- The failed preview-edit path deliberately clears the stale preview before fresh delivery and has a focused regression for that cleanup (`packages/plugin/src/dispatch.ts:115-119`; `dispatch-behavior.test.ts:248-268`).
- The added test names improve the intended user-facing contract, especially distinguishing a confirmed fresh final from a preview finalization.

## Verification notes

- Inspected PR commit `1a933bf69cff62fe71bb3c0675afbc45baa268b5` via `gh` and `git`; GitHub CI `test` is passing.
- Compared the implementation with the installed OpenClaw durable-send result types and live-preview finalizer. The local SDK declares `payloadOutcomes?` optional and treats `suppressed` as a distinct terminal outcome.
- No GitHub review/comment was posted.
