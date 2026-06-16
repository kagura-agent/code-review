## Review for PR #385: feat(client): message actions — reply, edit (#300)

**Rate:** ⚠️ Needs Changes

### Feedback
1. **Missing Test Coverage:** The PR introduces significant behavior changes including context menu actions for reply/edit, hover bar actions, and edit mode handling in the `MessageInput` component. However, no tests are included in the diff. As per the project guidelines, *any behavior change must have test coverage*. Please add appropriate unit and/or integration tests for:
   - `MessageContextMenu` (reply and edit actions)
   - `MessageItem` (edit button visibility and click behavior)
   - `MessageInput` (edit state management, Escape to cancel, patching the message)
   - `useEditStore`

2. **Unrelated Changes Bundled:** The PR includes changes to `gateway-subscriptions.ts` (capping `mentionedMessageIds` set at 1000 entries to prevent memory leaks) and fixes to mention regex logic in `ChannelMentionAutocomplete.tsx` and `MentionAutocomplete.tsx`. These are good fixes but are unrelated to "message actions — reply, edit". Consider moving them to a separate PR, or at the very least, they also require test coverage.

Please add the missing tests and I will be happy to review again!