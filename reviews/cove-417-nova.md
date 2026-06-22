# 🌠 Nova — Review: cove#417

**PR:** `refactor(plugin): clean up typing lifecycle management (#401)`
**Repo:** kagura-agent/cove
**Diff:** `packages/plugin/src/dispatch.ts`, +6 / −3

## Summary

Small, well-scoped structural refactor that consolidates two scattered `typingCallbacks.onCleanup?.()` invocations (inner abort branch + outer catch) into a single outer `finally` block, plus keeps the existing early cleanup inside `deliver()`. The change is consistent with the SDK semantics — `createTypingCallbacks` returns an `onCleanup` (aliased to `fireStop`) that is internally idempotent via `closed`/`stopSent` flags, so the “safety net” claim in the comment is accurate. Behavior is preserved (all 111 tests pass; F3 still covers early-cleanup-on-delivery, F5 covers abort path), and the change makes the lifecycle easier to reason about. ✅ Ready to merge.

## Critical Issues

None. The refactor does what it says, doesn’t introduce floating promises, doesn’t broaden `any`, and doesn’t change observable behavior.

## Suggestions (non-blocking)

1. **Test coverage gap — outer `finally` cleanup on non-abort error.** The existing behavioral tests cover:
   - F3: cleanup called inside `deliver()` on success.
   - F5: abort path returns cleanly (but doesn’t assert `onCleanup` was called).

   Neither test directly exercises the new outer `finally` for the case the PR description sells hardest — an unexpected throw *before* `deliver()` runs (e.g. `loadInbound()` rejects, `runInboundReplyTurn` throws non-abort). Consider a one-liner test:
   ```ts
   it("F9: typing cleaned even when dispatch throws before deliver()", async () => {
     const mockCleanup = vi.fn();
     vi.mocked(createTypingCallbacks).mockReturnValue({ onReplyStart: vi.fn(async () => {}), onCleanup: mockCleanup });
     vi.mocked(runInboundReplyTurn).mockRejectedValueOnce(new Error("boom"));
     await dispatchMessage(createBaseOpts());
     expect(mockCleanup).toHaveBeenCalled();
   });
   ```
   Without this, the refactor’s primary safety claim is asserted only by inspection.

2. **Double-call in success path is fine but worth a one-line test note.** On success, `onCleanup` runs twice: once early in `deliver()`, once in the outer `finally`. The SDK’s `fireStop` is idempotent (guarded by `closed`/`stopSent`), so this is safe in production. However, F3 uses a `vi.fn()` mock that does *not* simulate idempotency — if anyone ever adds `expect(mockCleanup).toHaveBeenCalledTimes(1)` they’ll get a surprise. The comment already explains intent; consider adding `// fires twice (early + safety net); SDK fireStop is idempotent` near the `deliver()` site, or upgrade F3 to `toHaveBeenCalledTimes(2)` to lock in the contract.

3. **Comment placement nit.** The trailing comment on `try { // typing lifecycle: …` is informative but reads oddly attached to the brace. Either pull it above the `try` (more conventional) or drop it — the block comment in `finally` already explains the design and is the more important one.

4. **Inner abort branch can be tightened (out of scope but adjacent).** The inner `try/catch` now only handles abort detection + rethrow:
   ```ts
   } catch (err: any) {
     if (abortController.signal.aborted) {
       log?.info?.(`cove: dispatch aborted in [${channelId}]`);
     } else { throw err; }
   }
   ```
   With cleanup gone from this branch, the inner `try` exists solely to swallow `AbortError` and to free `pendingDispatches`. That’s legitimate, but a future PR could collapse the two nested try/catches and route abort detection through the outer catch — fewer layers, same behavior. Not for this PR; just flagging since #401 is open.

## Positive Notes

- **YAGNI-friendly.** Removes a real failure mode (missed cleanup on outer-catch path) without adding abstraction. Exactly the kind of "what should be removed?" change the spec asks for.
- **Comment is load-bearing and accurate.** The `// safety net — covers success, error, abort, supersede` comment explains *why* the structure exists, which is the right kind of comment.
- **Idempotency relied upon, not assumed.** SDK source (`typing-By1cdYk1.js`) confirms `fireStop` is guarded by `closed`/`stopSent` — the safety-net pattern is sound.
- **No floating promises introduced.** `onCleanup` is synchronous from the caller’s side (`fireStop`); fire-and-forget pattern unchanged.
- **Tiny diff, tight scope.** +6/−3, one file. Easy to review, easy to revert.

## Verdict

✅ **Ready to merge.** Suggestion (1) — adding a test for the outer-finally-on-error path — would be a nice follow-up but is not a blocker for a 9-line refactor whose 111-test suite passes.
