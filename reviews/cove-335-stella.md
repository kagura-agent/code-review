# PR #335 Review — feat: message reply/quote — Discord-style

**Reviewer:** Stella  
**Repo:** kagura-agent/cove  
**Rating:** ⚠️ Needs Changes

## Summary

This PR adds Discord-style message replies end-to-end: a `referenced_message_id` column, REST validation/storage, populated `referenced_message` responses, reply selection state, reply bar, inline quote display, optimistic reply sends, and click-to-jump highlighting.

The architecture is generally solid and the server-side reference validation is appropriately scoped to the current channel. SQL uses bound parameters, and list population avoids a per-message N+1 query. However, there are a couple of client consistency gaps around deletion/retry flows that affect core reply behavior, so I would not merge as-is.

## Critical Issues

1. **Deleted referenced messages remain visible in already-loaded reply quotes**
   - `MESSAGE_DELETE` currently only removes the deleted message from the channel store (`packages/client/src/lib/gateway-subscriptions.ts`, `packages/client/src/stores/useMessageStore.ts:79-83`). It does not clear `referenced_message` on other loaded messages that replied to the deleted message.
   - Result: if message A is deleted after message B replied to it, B can continue rendering A's author/content indefinitely in the current client session, instead of showing “Original message was deleted”. This contradicts the PR test plan and can preserve deleted content client-side until a refetch.
   - Suggested fix: when removing a message, also map the channel’s remaining messages and set `referenced_message: null` for any message whose `message_reference.message_id` or `referenced_message.id` matches the deleted id. Consider doing the same for bulk delete.

2. **Retrying a failed reply sends a non-reply message**
   - Initial optimistic send correctly captures `replyMsg` and sends `message_reference` (`MessageInput.tsx:73-116`). But the failed-message retry path rebuilds a pending message without `message_reference`/`referenced_message` and calls `api.sendMessage(channelId, content, nonce)` with no reference (`MessageItem.tsx:157-181`).
   - Result: a user can click reply, experience a transient send failure, click Retry, and produce a plain message instead of a reply.
   - Suggested fix: pass the full failed `message` (or at least its `message_reference` and `referenced_message`) into `PendingIndicator`, preserve those fields on the new pending message, and pass the reference to `api.sendMessage` on retry.

## Product Impact

- Reply creation, rendering, and quote jumping should work for the happy path.
- Deleted-original behavior is inconsistent: server refetches can show “Original message was deleted”, but live clients retain stale quoted content after delete events.
- Failed-send retry can silently change the user’s intended reply into a normal message.
- Click-to-jump only works when the referenced message is currently rendered/loaded; otherwise it silently does nothing. That may be acceptable for v1, but it is a visible edge case for replies to older messages.

## Suggestions

- Use `CSS.escape(messageId)` or an equivalent safe selector helper in `MessageList.tsx:189`. Message IDs are currently expected to be snowflakes/UUIDs, but escaping makes the jump code robust against legacy/imported IDs and avoids selector syntax exceptions.
- Consider updating nested reply previews when the referenced message is edited. `updateMessage` currently updates only the edited top-level message content (`useMessageStore.ts:73-78`), so existing reply quotes can show stale referenced content until refetch.
- Add targeted tests for:
  - deleting a referenced message clears loaded reply quotes;
  - retrying a failed reply preserves `message_reference`;
  - server rejects cross-channel/nonexistent references;
  - list population returns `referenced_message: null` for deleted originals.
- Server validation is good, but consider rejecting empty `message_reference.message_id` explicitly for clearer 400s.

## Positive Notes

- Server-side reference validation is permission/channel scoped via existing channel membership and `getById(channelId, message_id)` checks.
- SQL construction for reference population uses placeholders for IDs, avoiding injection risk.
- Batch population in `MessagesRepo.list` avoids the obvious N+1 query problem and reuses messages already in the current page.
- The UI addition is cleanly componentized (`ReplyBar`, `MessageReplyQuote`, `useReplyStore`) and the optimistic path includes the quote preview for the initial send.
- Existing CI reported success for the PR.
