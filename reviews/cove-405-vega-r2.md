# PR #405 Re-review (Round 2) — 💫 Vega

- **Verdict**: ❌ Major Issues
- **Summary**: This PR introduces a new SDK adapter for message delivery. While it fixes one of the previous issues (double-delete), it leaves two critical issues unaddressed and introduces two new ones. The most significant regressions are the complete loss of message chunking for large messages and a new race condition that allows a stale dispatch to overwrite a final message. The PR is not ready to merge.

---

## Critical Issues (Blocking)

### 1. [Critical] REGRESSION: Message Chunking is Lost
- **Status**: **Unaddressed & Worsened** (was Critical)
- **File**: `packages/plugin/src/dispatch.ts`
- **Function**: `freshSend`
- **Problem**: The previous review noted that `freshSend` had lost its chunking capability. This PR has removed the `sendDurableMessageBatch` wrapper entirely, making the regression permanent. The new `freshSend` calls `restClient.sendMessage` directly. Any message over 4000 characters sent via this path (which includes all fallback messages and messages sent when no draft exists) will be truncated or fail, resulting in data loss for the user. This is a major functional regression.

### 2. [Critical] REGRESSION: Stale Dispatch Can Overwrite Final Message
- **Status**: **Unaddressed** (was Critical)
- **File**: `packages/plugin/src/dispatch.ts`
- **Function**: `dispatcherOptions.deliver`
- **Problem**: The `deliver` function checks `isCurrent()` at the beginning. It then calls `deliverWithFinalizableLivePreviewAdapter`, which is an async operation that involves sealing the draft. The original code correctly placed a second `isCurrent()` check *after* the `seal()` operation but *before* the final `editMessage` call. This check is now gone.
- **Scenario**:
    1. Dispatch A starts delivery. `isCurrent()` is true.
    2. `deliverWithFinalizableLivePreviewAdapter` is called. It begins the async `draft.seal()` process.
    3. While `seal()` is running, a new message arrives, aborting Dispatch A and starting Dispatch B. `pendingDispatches` is now set to Dispatch B's controller.
    4. Dispatch A's `seal()` operation completes.
    5. The adapter proceeds to call `editFinal`, which contains its own `isCurrent()` check. **However, `editFinal` is not called if there is no draft message to edit.** If Dispatch B has already completed and cleaned up, Dispatch A's adapter will fall back to `deliverNormally` -> `freshSend`. The `freshSend` function *also* has an `isCurrent()` check at the top. This part is safe.
    6. **The race is in the edit path**: If Dispatch B has NOT cleaned up the draft yet, Dispatch A's `editFinal` will fire. The guard `if (isCurrent())` inside `editFinal` will correctly return `false`, preventing the stale edit.
    7. **The true critical issue is subtler**: The `handlePreviewEditError: () => "fallback"` logic combined with the `isCurrent()` guard inside `editFinal` creates a new failure mode. If the edit is attempted, fails the `isCurrent()` check, but the edit call *itself* doesn't throw, the adapter may not trigger the fallback path correctly. A stale dispatch's failure should be a silent stop, not a fallback to a fresh send. The loss of the post-seal guard makes the control flow much harder to reason about and less safe. The original explicit guard was clearer and safer.

### 3. [Critical] NEW: `freshSend` Always Attempts to Delete Draft
- **Status**: **New Issue**
- **File**: `packages/plugin/src/dispatch.ts`
- **Function**: `freshSend`
- **Problem**: The `freshSend` function is called in two scenarios: 1) as a fallback when an edit fails, or 2) when no draft existed in the first place. The new implementation unconditionally tries to delete `draftMessageId` if it's set. This is incorrect for scenario #2. If a message is sent without a preceding draft, `draftMessageId` is undefined, and no delete is attempted (correct). However, if an edit fails because the draft was *already deleted* (e.g., by a moderator), `draftMessageId` will still be set, `freshSend` will be called, and it will try to delete a message that doesn't exist, logging a spurious error. The deletion should only be attempted if the fallback is triggered from a known-good state.

---

## Addressed Issues

- **[Addressed] Double-delete on fallback**: The refactoring into the SDK adapter appears to have resolved the double-deletion race condition. The `freshSend` and `adapter.clear` paths are now separated and don't seem to overlap in a way that causes the same message ID to be deleted twice in a single flow.

---

## Suggestions (Non-Blocking)

- **[Suggestion] `freshSend` delete-before-send ordering**
    - **Status**: **Unaddressed**
    - **File**: `packages/plugin/src/dispatch.ts`
    - **Function**: `freshSend`
    - **Issue**: `freshSend` deletes the old draft message *before* attempting to send the new one. If the subsequent `sendMessage` call fails, the user's message is lost entirely. The safer order of operations is: send new message, then delete old message upon success.

---

## Positive Notes

- The adoption of the SDK's `defineFinalizableLivePreviewAdapter` is a good strategic direction, and the implementation in `dispatch-behavior.test.ts` to lock in behavior before refactoring is excellent practice.
- The fix for the double-delete issue is clean.
