# PR #329 Review — Stella

## Summary
This PR updates `MessageList` auto-scroll behavior so newly inserted optimistic messages (`pending-*` ids) always scroll the current user to the bottom, even if they had scrolled up. Other messages continue to respect the existing `wasNearBottomRef` guard. The change is small, localized, and aligned with the reported issue.

**Rating: ✅ Ready**

## Critical Issues
None found.

## Product Impact
- Fixes the main user-facing annoyance: after sending a message from a scrolled-up position, the user should immediately see their own pending message.
- Existing behavior for other users' incoming messages is preserved: if the user is reading older content, unrelated incoming messages should not pull them to the bottom.
- Minor edge case: this identifies own sends by optimistic `pending-*` ids only. Messages sent by the same account from another client/session, or server-originated own messages without an optimistic pending insert, will still follow the normal near-bottom rule. That seems acceptable for this PR's stated scope.

## Suggestions
- Consider adding a small component/store test around the intended behavior if this area already has test infrastructure: scrolled up + `addPendingMessage` should invoke scroll, while scrolled up + normal `addMessage` should not.
- Longer term, detecting own messages via author/current-user metadata would be more semantically robust than relying on the temporary id prefix. For the current optimistic-send flow, the prefix is consistent with surrounding code.
- If multiple messages can be appended in one batched update, only checking the final message could miss a pending own message that is not last. This is likely rare with the current store methods, but worth keeping in mind if batching behavior changes.

## Positive Notes
- The change is minimal and contained to the existing new-message scroll effect.
- It preserves the prior behavior for non-own messages instead of broadening auto-scroll too much.
- Hook dependencies and cleanup patterns remain consistent with the surrounding code; no new stale-closure or floating-promise issue was introduced.
