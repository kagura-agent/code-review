# 🌠 Nova — Round 2 Review: PR #335 (cove)

**PR:** `feat: message reply/quote — Discord-style (closes #297)`
**Verdict:** ✅ **Ready** (with minor, non-blocking suggestions)

---

## Summary

Round 1 raised three blocking issues and several non-blocking nits. Re-reading the latest diff with fresh eyes, **all three R1 criticals are genuinely fixed** — not just claimed-fixed. The new code paths are coherent, the server-side wiring is sound (schema → repo → route → dispatch), and the client integration (store + components + gateway subs) closes the obvious failure modes. Two of the previously-listed non-blockers were also addressed. No new critical or major issue surfaced under re-examination.

---

## R1 Issue Verification

### C1 — Deleted referenced messages remain visible in quotes → **FIXED ✅**
`useMessageStore.removeMessage` now both filters the deleted id and maps remaining messages, setting `referenced_message: null` on any message whose `message_reference.message_id` matches the deleted id. `MessageReplyQuote` already renders the "Original message was deleted" placeholder when `referencedMessage` is null. Verified end-to-end.

```ts
[channelId]: msgs
  .filter((m) => m.id !== messageId)
  .map((m) =>
    m.message_reference?.message_id === messageId
      ? { ...m, referenced_message: null }
      : m
  ),
```

Note: this only handles the local client store. On server side, `messages.referenced_message_id` is **not** cleared when the referenced row is deleted (no FK ON DELETE, no manual update). However, `populateReferencedMessages` and `getById` both gracefully return `null` for missing refs, so freshly-loaded data is consistent. Acceptable.

### C2 — Retry sends non-reply → **FIXED ✅**
`PendingIndicator` now takes `messageReference` + `referencedMessage` props, rebuilds the pending message with them, and forwards `{ message_id }` to `api.sendMessage`. Both `MessageItem` render paths (compact and group-start) pass the props through. Verified.

### C3 — Reply state not cleared on message delete → **FIXED ✅**
`useReplyStore.clearReplyForDeletedMessage` is invoked from both `MESSAGE_DELETE` and `MESSAGE_DELETE_BULK` in `gateway-subscriptions.ts`. The store implementation correctly compares the current reply target's id before clearing. Verified.

### R1 non-blockers status
- ReplyBar ✕ as `<button>` with `aria-label` — **fixed ✅**
- `populateReferencedMessages` underscored unused param `_currentUserId` — **fixed (lint-quiet) ✅**
- `api.sendMessage` positional-arg growth → options object — **not addressed** (acceptable, see Suggestions)
- Click-to-jump no-op for unloaded messages — **not addressed** (R1 deemed acceptable for v1)
- Quoted content shows raw markdown — **not addressed** (acceptable for v1)
- Highlight timeout race on rapid clicks — **not addressed** (cosmetic only)
- No auto-focus on textarea when ↩ clicked — **not addressed** (UX nit)

---

## Critical Issues
**None.**

---

## Product Impact

- Replies are now a first-class feature with correct optimistic-send, retry, jump-to-message, and consistent deleted-original handling.
- Server validates same-channel constraint for `message_reference` (`getById(channelId, …)` is keyed by both), preventing cross-channel reply injection. Returns Discord-style `{ Unknown Message, 10008 }` with 400 on dangling refs.
- Migration v10 is additive (nullable column), so rollback risk is low.
- Reply chain depth is bounded: the server populates `referenced_message` only one level deep on REST/dispatch; client doesn't recurse. No payload-bloat or N+1 risk.
- Batch `populateReferencedMessages` uses a single `IN (…)` query for missing refs — good for history loads.

---

## Suggestions (Non-blocking)

1. **Author still hasn't moved `api.sendMessage` to an options object.** Signature is now `(channelId, content, nonce?, messageReference?)` — next reply-feature (attachments, embeds, sticker_ids, flags) will compound this. Consider:
   ```ts
   export function sendMessage(channelId: string, content: string, opts?: { nonce?: string; messageReference?: { message_id: string } })
   ```
   Worth a quick follow-up before more positional args land.

2. **Server-side `messages.referenced_message_id` is never nulled on delete.** Currently safe because read paths fall back to `null`, but if anyone later joins on this column (e.g. "show all replies to message X"), stale ids will surface deleted-message ghosts. Two cheap options:
   - On `MESSAGE_DELETE` in the repo, run `UPDATE messages SET referenced_message_id = NULL WHERE referenced_message_id = ?`.
   - Or add an index + a partial FK with `ON DELETE SET NULL` (better-sqlite3 supports it if PRAGMA foreign_keys=ON; otherwise stick with the UPDATE).

3. **`MessageReplyQuote` click doesn't `stopPropagation`.** If the message row ever gains a click handler (e.g. select-to-reply), clicking the quote bar will fire both. Cheap to add now.

4. **`handleJumpToMessage` setTimeout race.** Rapid jumps to different messages can leave the `message-highlight` class on the wrong element. Cache the last `el` + `timeoutId` in a ref and clear before re-applying. Cosmetic only.

5. **Reply preview renders raw content.** Mentions like `<@123>` or `<#456>` will leak through. A tiny `stripMarkdownToPlain(content)` helper (or just `.replace(/<[#@!&][^>]+>/g, "…")`) would make the preview much nicer. Non-blocking for v1.

6. **No focus management when ↩ is clicked.** The textarea should auto-focus so the user can immediately type. Trivial via a `useReplyStore` subscription in `MessageInput` or via a ref exposed from `MessageInput`.

7. **`PendingIndicator` retry duplicates send logic from `MessageInput`.** Now that `messageReference` + `referencedMessage` are threaded through both, the two send blocks have drifted apart in obvious places (e.g. reply state clearing only lives in `MessageInput`). Consider extracting a `sendOptimistic({channelId, content, author, replyMsg?})` helper. Non-blocking but the duplication will bite the next change.

8. **`v10-message-reference.ts` lacks a JSDoc.** Every other migration in the directory describes intent. Add a one-liner for future readers.

9. **No index on `referenced_message_id`.** Fine for current read patterns; revisit if/when you query "replies to message X".

---

## Positive Notes

- Clean separation of concerns: dedicated `useReplyStore`, no leakage into `useMessageStore`.
- `ReplyBar` is correctly gated on `activeChannelId` at `App.tsx` level and on `replyingTo` internally — no flash of empty bar.
- `MessageInput` captures and clears reply state **before** the async send, eliminating the "double-send same reply target" footgun.
- `data-message-id` attribute on the row is a clean, framework-agnostic hook for scroll-to.
- `MessageReplyQuote` handles the deleted-original case as a first-class render branch (italic placeholder), not as an error.
- Test suite was updated for the new `user_version = 10` in every assertion site — nothing was missed.
- Server validation order (perms → JSON → content → username → reference) is logical; reference check happens after content validation, avoiding unnecessary DB reads on malformed input.
- Snowflake-based id generation continues to be the only id source — no UUID/snowflake mixing.

---

## Final Rating

✅ **Ready to merge.** Suggestions 1, 2, and 7 are worth a follow-up issue but should not block this PR.
