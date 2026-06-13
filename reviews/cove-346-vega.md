# Code Review: PR #346 (cove) - NEW separator line and unread banner

**Reviewer:** Vega 💫
**Verdict:** ⚠️ Needs Changes

## 1. Summary
This PR implements Discord-style unread message indicators, including a frozen "NEW" separator line, a top unread banner, and a bottom pill for real-time messages. The core design correctly separates entry indicators (frozen snapshot) from real-time indicators (live updates). However, there are a few critical bugs regarding batch message handling, partial data loading, and potential race conditions that need to be addressed before merging.

## 2. Critical Issues (Must Fix)

- **Batch Message Pill Counter Bug:** 
  When new messages arrive while the user is scrolled up, `setNewMessagesBelowCount((c) => c + 1)` only increments the pill counter by 1. If multiple messages arrive in a single React batch (e.g., `messages.length` jumps by 3), the counter will be inaccurate.
  *Fix:* Increment by the actual delta: `setNewMessagesBelowCount((c) => c + (messages.length - prevCountRef.current))`.

- **NEW Line Missing on Partial Load:**
  If a channel has many unread messages and `lastReadId` is older than the currently loaded `messages` chunk (i.e., `lastReadIdx === -1`), the `isFirstUnread` condition (`prev.id === lastReadId`) will never be true. The NEW line fails to render entirely.
  *Fix:* If `lastReadIdx === -1`, the NEW line should render at the very top of the visible message list.

- **Frozen Incorrect Unread Count:**
  In the same scenario where `lastReadIdx === -1`, `entryUnreadCount` defaults to `messages.length` and the computation is permanently locked (`unreadComputedForRef.current = channelId`). When the user scrolls up and loads older messages, the top banner will still display the initial partial count (e.g., "50 new messages" instead of 100).
  *Fix:* Do not lock `unreadComputedForRef` if `lastReadIdx === -1`, or explicitly update `entryUnreadCount` when older messages are prepended and the last read cursor is still not found.

- **Race Condition on Channel Switch:**
  The `useEffect` computing the initial unread count triggers when `channelId` or `messages` changes. If the `messages` array doesn't update completely synchronously with `channelId` (e.g., during a React transition or query caching), the effect might compute the unread count using the *new* `channelId` snapshot against the *old* channel's `messages`, freezing a completely corrupted state.
  *Fix:* Verify that the `messages` array belongs to the current `channelId` before computing and locking the ref.

## 3. Product Impact

- **Banner Action Discrepancy:**
  The PR description states that clicking the top banner "Jump ↑" scrolls to the NEW separator. However, the code and spec implement a "Mark as Read" action that calls `scrollToBottom()`. Jumping to the oldest unread message vs. jumping to the bottom are very different UX flows. Please clarify the intended behavior and align the PR description, spec, and code.
- **Immediate Banner Dismissal:**
  If the `MessageList` component natively auto-scrolls to the bottom on initial load, the `onScroll` handler will immediately detect `atBottom === true` and dismiss the Top Banner before the user can even see it. Ensure initial auto-scroll logic correctly accounts for unread state (usually by scrolling to the NEW line instead of the bottom).

## 4. Suggestions (Non-blocking)

- **`isOwnMessage` Detection:** 
  Checking `lastMsg.id.startsWith("pending-")` works well for optimistic UI. However, if the user sends a message from another session/device, it won't start with `pending-` and might trigger the bottom pill instead of clearing the NEW line. Consider also checking if `lastMsg.authorId === currentUserId`.
- **Throttling State Updates in `onScroll`:**
  Currently, `setShowTopBanner(false)` and `setNewMessagesBelowCount(0)` are called continuously while the user is at the bottom of the list. While React 18 batches this well, it's safer to wrap them in conditions (`if (showTopBanner) ...`) to avoid unnecessary dispatch calls during high-frequency scroll events.

## 5. Positive Notes

- **Excellent State Separation:** The architectural choice to freeze `lastReadIdSnapshotRef` on entry correctly prevents the NEW line from jumping around wildly as users read messages.
- **Clear Spec:** The accompanying `unread-spec.md` is incredibly well-written and leaves no ambiguity about how the state rules should function. Great documentation!
