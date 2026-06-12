# 🌟 Stella — Round 2 Re-review of kagura-agent/cove PR #335

**PR:** feat: message reply/quote — Discord-style (closes #297)  
**Verdict:** ✅ Ready

## Summary

I re-reviewed the latest diff against all Round 1 findings and did a fresh pass over the new server/client code. The three previously blocking issues appear to be addressed:

1. Deleted referenced messages no longer keep stale quote content in already-loaded messages.
2. Failed-message retry now preserves `message_reference` and sends it back to the server.
3. Active reply state is cleared when the referenced message is deleted via single or bulk delete gateway events.

I also ran validation locally:

- `pnpm -r build` ✅
- `pnpm -F @cove/server exec vitest run --reporter=dot --silent` ✅ — 12 files / 223 tests passed
- `pnpm -F @cove/client test -- --reporter=dot --silent` ✅ — 2 files / 6 tests passed

## Critical Issues

None found in Round 2.

### R1 Follow-up Checklist

#### C1: Deleted referenced messages remain visible in quotes

**Status:** Fixed.

`useMessageStore.removeMessage()` now filters out the deleted message and maps remaining messages whose `message_reference.message_id` matches the deleted ID to `{ ...m, referenced_message: null }`. This makes `MessageReplyQuote` render “Original message was deleted” instead of stale content.

Server-side fetch behavior is also consistent: `referenced_message_id` remains on the reply, but `referenced_message` resolves to `null` if the referenced row no longer exists.

#### C2: Retry sends non-reply

**Status:** Fixed.

`PendingIndicator` now accepts `messageReference` / `referencedMessage`, includes them in the newly-created retry pending message, and passes `{ message_id: messageReference.message_id }` into `api.sendMessage(...)`. The retry path should preserve reply semantics.

#### C3: Reply state not cleared on message delete

**Status:** Fixed.

`gateway-subscriptions.ts` calls `useReplyStore.getState().clearReplyForDeletedMessage(...)` on both `MESSAGE_DELETE` and each ID in `MESSAGE_DELETE_BULK`. The `ReplyBar` should no longer stay attached to a deleted source message.

## Product Impact

The Discord-style reply flow now covers the important user-facing lifecycle cases:

- Replies optimistically display a quote immediately.
- Server-created messages persist a reference and return populated `referenced_message` where possible.
- Deleted referenced messages degrade gracefully to a deleted-message placeholder.
- Failed replies retry as replies rather than plain messages.
- Reply composer state is cleaned up when the target message disappears.

This is good enough to ship from my review perspective.

## Suggestions

Non-blocking improvements I would consider after merge:

1. **Add direct regression tests for reply behavior.** Existing build/tests pass, but this PR has no focused tests for `message_reference` creation, fetch population, delete degradation, or retry preservation. These are exactly the cases that regressed in R1.
2. **Consider jump-to-message behavior for unloaded referenced messages.** `MessageReplyQuote` can only scroll to messages currently mounted in the DOM. That is acceptable for this PR, but a future enhancement could fetch `around=<messageId>` or otherwise load the target before jumping.
3. **Consider making the v10 migration idempotent.** `ALTER TABLE messages ADD COLUMN referenced_message_id TEXT` is fine for normal migrations, but using the existing `addColumnIfMissing` helper would make recovery from partially-applied/manual schemas safer.

## Positive Notes

- The R1 fixes are targeted and easy to reason about.
- The pending-message retry fix preserves both UI state and API payload, which avoids a subtle optimistic/retry mismatch.
- `ReplyBar` close is now a real button with `type="button"` and `aria-label`, which is a nice accessibility cleanup.
- Server validation ensures replies only reference existing messages in the same channel.
