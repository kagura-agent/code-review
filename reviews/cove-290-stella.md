# PR #290 Review — Stella

## Verdict

Approve — no blocking issues found.

The change correctly removes the artificial 120s dispatch timeout while preserving the existing superseding-message guard through `pendingDispatches` + `isCurrent()` checks. This matches the stated product goal: long-running agent turns should not silently lose their final response.

## Findings

No required changes.

## Notes by Review Area

- **Correctness:** The removed `createAbortableDispatch()` wrapper did not actually cancel the underlying agent run; it only let the Cove handler return early on timeout/abort. After this PR, long-running dispatches can complete and deliver normally. Superseded dispatches are still prevented from sending/editing messages because all delivery/progress callbacks gate on `isCurrent()`.
- **Abort behavior:** Reconnect/shutdown/superseding aborts still mark controllers as aborted and clear/replace the map entry. Old dispatches may continue in the background until their underlying runtime finishes, but this was already true for the actual agent work; the removed wrapper only detached the handler earlier.
- **Security / input validation:** No new input surface or trust boundary introduced.
- **Performance:** Removing the timeout can allow legitimately long runs. This is consistent with Discord behavior and the PR goal. No unbounded tight loop or extra polling added.
- **Readability:** Net simplification; fewer custom error classes and less race-wrapper code.
- **Testing:** Timeout-specific tests were removed appropriately. Existing abort-related tests are weaker than before because they now verify controller state rather than end-to-end dispatch cancellation, but given the implementation relies on `isCurrent()` delivery guards rather than true cancellation, I do not consider this blocking for this small fix.
- **API/interface design:** Removing the `channel.ts` re-export of timeout helpers is acceptable; it appears to have existed only for test compatibility.

## Verification

- Reviewed `gh pr diff 290 --repo kagura-agent/cove`.
- Fetched and inspected `origin/pr-290` affected files.
- Checked PR CI with `gh pr checks 290 --repo kagura-agent/cove`: `test` and `deploy` were passing at review time.
