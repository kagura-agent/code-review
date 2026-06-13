# Code Review: PR #343 — feat: right-click context menu with delete message

## Summary

This PR adds a frontend right-click message context menu with Copy Text, Copy Message ID, and a two-step Delete Message action for the current user's own messages. The UI implementation is small and mostly straightforward, with viewport clamping and listener cleanup.

**Verdict: ⚠️ Needs Changes**

The frontend hides deletion for other users' messages, but the existing backend `DELETE /channels/:id/messages/:msgId` endpoint still allows any guild member with channel access to delete any message. Because this PR exposes that endpoint through normal UI, the ownership/permission guarantee must be enforced server-side before merge.

## Critical Issues

1. **Server-side authorization does not enforce “only own messages deletable.”**
   - `MessageContextMenu` only shows Delete when `isOwnMessage` is true, but client-side hiding is not authorization.
   - The server route currently gets the target message and then deletes it without checking `existing.author.id === user.id` or a manage-messages permission.
   - Relevant existing route: `packages/server/src/routes/messages.ts:183-191` explicitly says any guild member can delete any message in channels they can access.
   - A user can craft a direct `DELETE /channels/:id/messages/:msgId` request for another user's message and delete it.
   - Fix: update the server endpoint to allow deletion only by the message author and/or users with the future/current manage-messages permission, and add tests proving another normal member receives 403.

## Product Impact

- Users now have a discoverable delete affordance, which is good, but the feature currently creates a mismatch between UI promise and backend reality: “only my messages can be deleted” is not actually true.
- Delete state is driven by the existing `MESSAGE_DELETE` websocket path, so successful deletes should remove the message for all clients.
- Failed deletes currently only log to console and close the menu. Users receive no feedback if the request fails.

## Suggestions

- Add accessibility semantics and keyboard support:
  - `role="menu"` on the container.
  - `role="menuitem"` on actions.
  - Focus the menu when opened.
  - Support Arrow Up/Down, Enter/Space, and Escape.
- Consider closing the context menu when `channelId` changes so a stale menu cannot attempt to delete/copy an old message while viewing another channel.
- Consider disabling the delete item while the delete request is in flight to avoid duplicate requests.
- Surface delete/copy failures with a lightweight toast or inline feedback instead of silently swallowing clipboard errors and only logging delete errors.
- Add component tests for viewport clamping, outside click/Escape cleanup, pending-message suppression, and own-vs-other delete visibility.

## Positive Notes

- The menu rendering does not use `dangerouslySetInnerHTML`; copying message content to the clipboard does not introduce an obvious XSS vector.
- Event listeners for outside click and Escape are cleaned up correctly in the effect cleanup.
- Pending/failed local messages are excluded from context menu actions via `pendingStatus[message.id]`.
- The two-step confirm flow reduces accidental deletes.
- Viewport edge clamping handles the common bottom/right overflow cases.