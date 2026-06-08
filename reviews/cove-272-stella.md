# R2 Review — kagura-agent/cove#272 — feat: emoji reactions

Reviewer: 🌟 Stella  
Verdict: ⚠️ Needs Changes

## Summary

R2 fixes several R1 server-side correctness gaps: emoji length validation is now present, the extra URL decode is gone, reaction repo/route tests were added, and `reactionNotifications: "own"` now has a REST fallback for pre-restart bot messages.

However, multiple R1 issues remain unaddressed and must be escalated per R2 rules. The most important one is still the client-side reaction count model: the store still mutates aggregate counts from delta WS events and only deduplicates the current user's own reaction state. Duplicate/replayed events for other users can still drift counts.

## R1 Issue Status

### 🔴 Must Fix

1. ✅ Fixed — Emoji path param length validation
   - `packages/server/src/routes/reactions.ts:16`, `:41`, `:66` now reject missing/`>64` emoji values.
   - There is also a route test for the too-long case at `packages/server/src/__tests__/reactions.test.ts:142`.

2. ✅ Fixed — Double URL decode
   - `packages/server/src/routes/reactions.ts:14`, `:39`, `:64` use `c.req.param("emoji")` directly; no extra `decodeURIComponent` remains.

3. ❌ Unaddressed → escalated — Client reaction count math is still delta-based and non-idempotent for other users
   - `packages/client/src/stores/useMessageStore.ts:90-112` increments `count + 1` on every `MESSAGE_REACTION_ADD` unless `me && reactions[idx].me`.
   - `packages/client/src/stores/useMessageStore.ts:113-136` decrements/removes on every `MESSAGE_REACTION_REMOVE` unless `me && !reactions[idx].me`.
   - This only deduplicates duplicate events for the logged-in user's own reaction. Duplicate/replayed add/remove events from another user still drift the aggregate count because the client has no per-user membership set and the server events at `packages/server/src/ws/dispatcher.ts:198-216` still do not include an absolute count.
   - Required fix: either have the server send authoritative reaction summaries/absolute counts after mutation, or maintain per-message/per-emoji user membership on the client using event `user_id`.

4. ✅ Mostly fixed — Tests are no longer zero
   - New repo/route coverage exists in `packages/server/src/__tests__/reactions.test.ts`.
   - Remaining gap: dispatcher/client WS idempotency is not covered; see fresh issue below.

### 🟡 Should Fix

5. ✅ Fixed — `SentMessageTracker` lost on restart
   - `packages/plugin/src/channel.ts:205-211` now falls back to `restClient.getMessage(...)` in `reactionNotifications: "own"` mode and caches the message if the author is the bot.

6. ❌ Unaddressed → escalated — `getUsersForReaction` remains unbounded + N+1
   - `packages/server/src/repos/reactions.ts:76-80` still returns every user id for the emoji with no `limit/after` pagination.
   - `packages/server/src/routes/reactions.ts:77-88` still calls `repos.users.getById(uid)` once per reactor.
   - Required fix: add Discord-style pagination/limit and return users via a joined query or batch lookup.

7. ❌ Unaddressed → escalated — LRU eviction bug remains
   - `packages/plugin/src/channel.ts:30-36` still evicts the oldest item before checking whether the incoming id already exists.
   - Re-adding an existing id while the set is full still unnecessarily evicts another tracked message and also does not refresh recency correctly.
   - Required fix: if `ids.has(id)`, delete it first and then re-add it; only evict after that if size exceeds max.

8. ❌ Unaddressed → escalated — React key still uses `emoji.name` only
   - `packages/client/src/components/MessageItem.tsx:87-90` still uses `key={r.emoji.name}`.
   - Current server only emits `id: null`, but the shared type supports `{ id, name }`. This will collide for custom emoji with the same name or when ids are later populated.
   - Required fix: use a stable compound key such as `${r.emoji.id ?? "unicode"}:${r.emoji.name}`.

## Fresh Findings

### 🔴 Must Fix — Add WS/store tests for duplicate reaction events

The exact R1 count-drift bug survived because the new tests only cover server repo/route behavior. There is no test that dispatches duplicate `MESSAGE_REACTION_ADD` / `MESSAGE_REACTION_REMOVE` events through `gateway-subscriptions` or directly against `useMessageStore` for `me=false`.

Suggested minimal test cases:
- Start with one message and one reaction `{ emoji: "👍", count: 1, me: false }`; apply the same non-self add event twice; count must not become 3.
- Start with count 2; apply the same non-self remove event twice; count must not remove two users' reactions.
- Verify dispatcher reaction payload shape if the chosen fix sends absolute counts.

### 🟡 Should Fix — `getUsersForReaction` tests do not cover scale or batching

`packages/server/src/__tests__/reactions.test.ts:130-140` only verifies a single reactor. That would not catch the unbounded/N+1 issue above. Add a multi-user test that asserts bounded output and ideally exercises the joined/batched lookup path.

## Positive Notes

- Server-side persistence is idempotent via the `(message_id, user_id, emoji)` primary key and `INSERT OR IGNORE` (`packages/server/src/repos/reactions.ts:17-21`).
- Message list hydration uses `getForMessages(...)`, avoiding a per-message reaction query when loading channel history (`packages/server/src/repos/messages.ts:79-83`).
- Route-level channel/message existence checks correctly prevent reacting to a message through the wrong channel (`packages/server/src/routes/reactions.ts:21-25`, `:46-50`, `:71-75`).

## Final Rating

⚠️ Needs Changes — several R1 items are fixed, but unaddressed R1 issues #3, #6, #7, and #8 must be escalated and resolved before merge.
