# Code Review: kagura-agent/cove PR #346

## Summary

This PR adds the Discord-style unread UX in `MessageList.tsx`: an entry-time NEW separator, an entry-time top unread banner, and a real-time bottom "new messages" pill, plus a spec document. The implementation is close and the client build passes, but I found one correctness bug in common unread edge cases that should be fixed before merge.

**Rating: ⚠️ Needs Changes**

## Critical Issues

1. **NEW line / entry banner fail when there is no read cursor, and NEW line fails when the cursor is outside the loaded page.**
   - `MessageList.tsx:208-216` treats `!lastReadId` as "no unread indicators". However `useReadStateStore.initReadStates` marks a channel unread when `last_message_id` exists and `last_read_message_id` is null, which is the normal state for a never-read channel or new user. In that case, all loaded messages should be unread and the banner should show.
   - `MessageList.tsx:219-224` sets `showNewLine(true)` when `lastReadId` is not in the loaded messages, but render logic at `MessageList.tsx:610-612` can only place the separator when `prev.id === lastReadId`. If the cursor is older than the loaded window, the NEW line never renders even though `showNewLine` is true.
   - User impact: entering a never-read channel can show no unread indicators, and entering a channel with more unread messages than the loaded page can show an incorrect/missing NEW line. This violates the frozen entry snapshot behavior and the documented edge cases.
   - Suggested fix: represent the separator position explicitly, e.g. `firstUnreadMessageId` or `separatorBeforeMessageId`. For `!lastReadId` or `lastReadIdx === -1`, set it to `messages[0].id` and count all loaded messages (or fetch/compute the true count if available). Render the separator before `separatorBeforeMessageId`, including index 0.

## Product Impact

- The happy path where `lastReadId` is present in the loaded messages works: count is frozen on entry, the NEW separator stays fixed, and new messages at bottom do not re-trigger entry indicators.
- The current bug affects first-time/never-read channels and high-unread-count channels, which are exactly the scenarios where users most need reliable unread positioning.
- The bottom pill behavior is reasonably separated from entry indicators and should only increment when the user is scrolled up and appended messages arrive.

## Suggestions

- Add targeted tests for: no read cursor with existing messages; `lastReadId` older than the loaded window; one unread; zero unread; channel switch with cached messages.
- Consider clearing `newMessagesBelowCount` immediately in the top banner `Mark as Read` handler as well as via the eventual scroll event, so smooth-scroll timing cannot leave the bottom pill visible briefly.
- Inline styles are acceptable for this small feature, but extracting shared banner/pill/separator styles would make future UX tweaks less risky.

## Positive Notes

- The PR correctly separates entry indicators from real-time indicators, which is the right product model.
- State is reset on channel switch, and the unread count is intentionally computed once per channel entry to avoid flashes while chatting.
- Existing scroll restoration and prepend behavior were mostly preserved.
- Verification: `pnpm -F @cove/client build` passes.
