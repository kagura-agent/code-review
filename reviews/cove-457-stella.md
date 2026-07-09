**Summary**: The PR is a narrow diagnostics-only change in `packages/plugin/src/dispatch.ts` that adds useful warning/info logs around abort and delivery failure points without altering the main delivery control flow. I did not find correctness, security, performance, API, or schema issues that should block merge. The main gap is test coverage for the new diagnostic behavior, but given the scope, that is non-blocking.

**Critical Issues**: None.

**Product Impact**: User-facing behavior should remain unchanged. Operators will get clearer logs for aborted dispatches, empty final payloads, send failures, and orphaned draft cleanup. The only minor risk is increased log noise for legitimate empty-text/tool-only turns at `packages/plugin/src/dispatch.ts:173-175`, but it is logged at info level and seems intentional.

**Suggestions**:
- `packages/plugin/src/dispatch.ts:110-124`: Consider including `message.id` in the `freshSend sendText failed` warning too, for consistency with the other diagnostic logs and the PR goal of correlating loss points by message.
- `packages/plugin/src/dispatch.ts:167-179`: Add a focused unit test that simulates abort before and after text extraction and asserts the diagnostic warning includes `channelId` and `message.id`. This would prevent future regressions in the observability fix.
- `packages/plugin/src/dispatch.ts:340-343`: If orphan deletion failure diagnostics are used for issue #419 follow-up, consider including `message.id` in the deletion failure warning as well, not only the cleanup-start warning.

**Positive Notes**:
- The once-per-dispatch guard for stream-update abort logs at `packages/plugin/src/dispatch.ts:48-55` prevents log spam during repeated buffered updates.
- The added logs preserve existing abort behavior and rethrow send failures after logging at `packages/plugin/src/dispatch.ts:121-126`, avoiding silent swallowing.
- The cleanup log at `packages/plugin/src/dispatch.ts:339-340` now includes abort state and source message correlation, which should materially improve incident diagnosis.

Rating: ✅ Ready
