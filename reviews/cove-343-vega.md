# Code Review: PR #343 - feat: right-click context menu with delete message

## 1. Summary
This PR implements a custom right-click context menu for messages, allowing users to copy message text, copy message ID, and delete their own messages. It utilizes existing API endpoints and WebSocket events for state updates. Overall, the logic is sound and the viewport positioning/memory edge cases are handled well, but the component is currently lacking required accessibility attributes.

## 2. Critical Issues
- **Missing Accessibility (a11y) Attributes & Keyboard Nav:** The `MessageContextMenu` lacks required ARIA roles (`role="menu"` on the container and `role="menuitem"` on the actionable items). It also does not implement focus management or keyboard navigation (e.g., navigating items via Arrow keys, or selecting via Enter). This violates the core a11y requirements for custom interactive menus.

## 3. Product Impact
- Introduces an expected, Discord-style interaction pattern for message management.
- **Security Check Required:** The frontend correctly hides the "Delete" option if `isOwnMessage` is false. However, as this relies on an existing `DELETE /channels/:id/messages/:id` endpoint, please ensure the backend *independently enforces* that the requesting user is the message author before applying the deletion.

## 4. Suggestions
- **Error Handling on Delete:** In `handleDelete()`, if `api.deleteMessage()` fails, the error is caught and logged, but `onClose()` is still called immediately, closing the menu without providing error feedback to the user. Consider showing a toast notification or retaining the menu on error.
- **Hover/Confirm UX:** Once "Delete Message" is clicked and changes to "Confirm Delete", the user's only way to back out is to close the entire menu (Escape or click outside). This is acceptable, but consider a clearer visual cue or cancellation mechanism if the user reconsiders.

## 5. Positive Notes
- **Viewport Adjustments:** The position adjustment logic in `useEffect` cleanly guarantees the menu won't be clipped by window edges.
- **Resource Cleanup:** The global `mousedown` and `keydown` event listeners for the click-outside/Escape interactions are appropriately cleaned up to prevent memory leaks.
- **Clean State Flow:** Triggering the API call and relying on the pre-existing `MESSAGE_DELETE` WebSocket event to remove the message from the UI avoids duplicating state logic and race conditions.

## Rating
⚠️ Needs Changes
