# PR #357 Review — Stella

## Summary

This PR adds the core data model, REST APIs, gateway events, and a first-pass client UI for public message threads. The implementation builds and the existing server test suite passes, but the new thread access paths are largely untested and several thread endpoints bypass the existing channel permission checks. There is also a user-visible state sync gap: parent message thread indicators are only populated on message fetch and are not updated when a thread is created or when replies are added, so the advertised “💬 N replies” workflow will be stale or absent until a reload/refetch.

## Critical Issues

1. **Thread member and guild thread endpoints bypass parent channel permissions.** `packages/server/src/routes/threads.ts:100-113` returns every active thread in a guild to any guild member without filtering by each thread’s parent channel permission. `packages/server/src/routes/threads.ts:116-184` allows joining, leaving, adding users to, and listing members of a thread after only checking guild membership; bot users do not need `VIEW_CHANNEL` on the parent channel. This leaks inaccessible thread metadata/member lists and allows membership mutation for threads under channels a bot cannot view. These routes should use `requireBotChannelPermission` against the thread’s parent channel (or a helper equivalent) and the guild-level listing should filter per parent channel, matching `channels.ts` behavior.

2. **New thread API/auth paths have no dedicated tests.** The PR adds create/list/join/leave/add/list thread routes in `packages/server/src/routes/threads.ts`, but there are no server tests covering these endpoints or their permission behavior. Per the review standard, new security/auth paths without tests are blocking. Please add tests for successful creation/listing, duplicate thread creation, invalid inputs, parent-channel permission denial, and member operations.

3. **Parent message thread indicators are not synchronized after create/reply, breaking the advertised UI flow.** The client only adds the returned thread to `useThreadStore` after creation (`packages/client/src/components/MessageContextMenu.tsx:98-104`), while `MessageItem` renders the indicator only from `message.thread` (`packages/client/src/components/MessageItem.tsx:317-320`, `372-375`). The server only enriches `message.thread` on message fetch/list (`packages/server/src/routes/messages.ts:28-35`, `55-59`) and does not dispatch/update the parent message when `createFromMessage` succeeds or when thread replies increment counts (`packages/server/src/routes/messages.ts:110-131`). Result: after creating a thread, the parent message can still show no indicator and the context menu can still offer “Create Thread” until a refetch; reply counts also stay stale. Update the message store/client state on `THREAD_CREATE`/`THREAD_UPDATE`, or dispatch a parent `MESSAGE_UPDATE` with refreshed thread info.

4. **`auto_archive_duration` accepts unvalidated arbitrary JSON values.** Both create routes accept `auto_archive_duration?: number` but never validate it (`packages/server/src/routes/threads.ts:23-27`, `66-70`), and `ThreadsRepo.createThread` stores it directly in `thread_metadata` (`packages/server/src/repos/threads.ts:124-134`). A string/object/negative/NaN-like value can be persisted despite the shared type saying number. New numeric inputs should use `validateFiniteNumber` plus integer/range checks on both create paths.

## Product Impact

Users may not see a thread indicator immediately after creating a thread, may be offered duplicate thread creation from the same message, and reply counts can appear stale. Bots with restricted channel permissions may see or manipulate threads they should not have access to, which is both a privacy and integration correctness risk.

## Suggestions

- Consider validating that threads can only be created under supported non-thread text channels (`channel.type !== 11`) to avoid nested threads or threads under unsupported channel types (`packages/server/src/routes/threads.ts:17-21`, `60-64`).
- Keep thread count updates and events consistent: `incrementMessageCount`/`decrementMessageCount` currently do not emit `THREAD_UPDATE`, so sidebars/open panels relying on thread metadata can remain stale (`packages/server/src/routes/messages.ts:110-115`, `213-216`).
- Align `thread_members.join_timestamp` storage: the schema declares `INTEGER` but `ThreadsRepo.addMember` writes an ISO string (`packages/server/src/db/schema.ts:124-127`, `packages/server/src/repos/threads.ts:61-64`). SQLite allows this, but it is confusing and easy to mishandle later.
- The READY handler fetches active threads once per channel in a loop (`packages/client/src/lib/gateway-subscriptions.ts:143-150`). For larger guilds, the guild-level active threads endpoint could avoid an N-request burst once its permission filtering is fixed.

## Positive Notes

- The migration/schema changes are straightforward and existing migration tests were updated to version 15.
- The permission inheritance helper for message/channel access to thread channels is a good direction (`packages/server/src/routes/helpers.ts:38-51`, `packages/server/src/ws/dispatcher.ts:178-190`).
- The client panel reuses the existing `MessageList`, `ReplyBar`, and `MessageInput`, which keeps behavior consistent with normal channels.
- Existing server tests pass (`pnpm -F @cove/server test -- --runInBand`) and the workspace build passes (`pnpm -r build`).

Rate: ⚠️ Needs Changes
