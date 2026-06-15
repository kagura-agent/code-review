# Code Review: PR #357 (Discord-style message threads)

## 1. Summary
This PR implements public message threads (channel type 11) by introducing a new `parent_id` hierarchy in the `channels` table, along with thread membership tracking. The frontend adds a resizable thread panel, thread creation context menus, and inline thread indicators on parent messages. Overall, the architecture aligns well with the Discord API shape.

## 2. Critical Issues
- **Input Validation (`routes/threads.ts`)**: `body.auto_archive_duration` is accepted in `POST /channels/:channelId/messages/:messageId/threads` and `POST /channels/:channelId/threads` without validation. According to the input validation standard, integer/number fields must use `validateFiniteNumber` (or equivalent) to prevent injection, `NaN`, or out-of-bounds values.
- **Input Validation (`routes/channels.ts`)**: The new `archived` and `locked` fields introduced in `PATCH /channels/:id` do not have strict boolean type validation.
- **Missing Tests**: The PR adds entirely new API endpoints (`routes/threads.ts`) handling business logic and auth (creating threads, joining/leaving threads) but includes no backend tests for them. The project standard strictly mandates: "Security/auth paths without tests = Critical".

## 3. Product Impact
- **Permission Gap for Thread Owners**: The `PATCH /channels/:id` route handles archiving, locking, and renaming threads. If this endpoint remains guarded by the global `MANAGE_CHANNELS` permission (standard for base channels), regular users will not be able to rename or archive the threads they create.

## 4. Suggestions
- **Performance (`repos/threads.ts`)**: The queries in `listActiveByChannel` and `listActiveByGuild` rely on `json_extract(thread_metadata, '$.archived') = 0`. This forces SQLite to parse the JSON string for every row during filtering. If thread volume grows, consider extracting `archived` to a standard indexed boolean column.
- **Missing Moderator Action**: The PR includes `PUT /channels/:threadId/thread-members/:userId` for adding users to a thread, but omits the corresponding `DELETE /channels/:threadId/thread-members/:userId`, preventing moderators from removing users from threads.

## 5. Positive Notes
- Database migrations are safely handled and well-covered in `migration.test.ts`.
- The frontend excellently reuses the existing `MessageList` and `MessageInput` components within the new `ThreadPanel`, maintaining DRY principles.
- The thread panel resizing UX (without bringing in heavy external libraries) is a nice touch.

## Verdict
⚠️ Needs Changes