# Code Review: PR #357 (Round 3)

## R2 Issues Status (Blockers)

1. **Nested thread creation not blocked** — ✅ Fixed. Added `channel.type === 11` check in both create routes.
2. **N+1 active-threads fetch on READY** — ✅ Fixed. Client now uses a single `fetchGuildActiveThreads` call in gateway subscriptions.
3. **`threadDelete` dead code** — ✅ Fixed. `dispatcher.threadDelete` is now properly called in `channels.ts` when a thread is deleted.

## R2 Non-blocking Issues Status (Escalated to Blockers)

⚠️ **Author ignored all 9 non-blocking issues from Round 2. Due to the escalation rule, these are now considered blocking.**

* ❌ **Guild active-threads endpoint leaks threads**: `listActiveByGuild` still does not filter out threads from parent channels the user doesn't have `VIEW_CHANNEL_BIT` for.
* ❌ **Archived/locked threads still accept message writes**: No checks added to `POST /channels/:channelId/messages`.
* ❌ **Bulk delete/clear-all don't update thread message_count**: Still not addressed.
* ❌ **Leave route missing guild-membership guard**: `DELETE /channels/:threadId/thread-members/@me` still lacks the `repos.members.exists` check (unlike the join route).
* ❌ **No negative permission tests**: Still missing from `threads.test.ts`.
* ❌ **Drag handler listener leak**: `App.tsx` resize handler still leaks listeners if unmounted while dragging.
* ❌ **Emoji corruption on thread auto-naming**: `MessageContextMenu.tsx` still uses `content.slice(0, 40)`.
* ❌ **Missing moderator removal route**: `PUT /channels/:threadId/thread-members/:userId` was added, but no corresponding `DELETE` route.
* ❌ **Unused channelId prop**: `ThreadIndicator` still defines `channelId` in `Props` without using it.

## New Issues

* ❌ **Emoji corruption risk in `ThreadPanel.tsx`**: The truncation logic `activeThread.name.slice(0, 40) + "\u2026"` has the same surrogate pair breaking issue as the auto-naming logic. Use `Array.from()` or `Intl.Segmenter` for safe string truncation.

## Summary + Verdict

**Verdict:** ⚠️ Needs Changes

The specific blockers from Round 2 were resolved, but the author completely ignored the remaining 9 feedback items. Following our escalation rule, these ignored issues must be addressed before this PR can proceed. Furthermore, the string truncation bug was replicated into new code (`ThreadPanel.tsx`). Please address the outstanding R2 issues and the new truncation bug.
