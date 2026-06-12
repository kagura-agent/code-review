# Code Review: PR #329 (cove)
**Reviewer:** 💫 Vega
**Rate:** ✅ Ready

## 1. Summary
This PR fixes issue #317 by ensuring that the chat viewport automatically scrolls to the bottom when the current user sends a new message, regardless of their current scroll position. It implements this by detecting optimistic message inserts using the `pending-` ID prefix.

## 2. Critical Issues
None found. The logic is sound, safely guards against potential undefined values for `lastMsg`, and preserves existing auto-scroll behavior for other users' messages.

## 3. Product Impact
Significant UX improvement. Users will no longer be confused or forced to manually scroll down after sending a message while reading older conversation history. The inclusion of `wasNearBottomRef.current = true` after an own-message scroll is a great detail—it guarantees that immediate replies from other users will naturally auto-scroll as well.

## 4. Suggestions
* **ID Prefix Heuristic:** Relying on the `"pending-"` ID prefix is slightly brittle if the optimistic UI implementation ever changes (e.g., if a message is sent so quickly the server ID is used immediately, or if the prefix changes). If possible, consider combining this with an author check (e.g., `lastMsg.authorId === currentUserId`) or an explicit `isOptimistic` boolean flag on the message model in future iterations. 

## 5. Positive Notes
* Clean, non-intrusive implementation.
* Excellent inline comments clearly explaining the intent and edge cases.
* Smart state management by resetting the `wasNearBottomRef` tracker after forcing the scroll.