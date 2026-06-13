# 🌠 Nova Code Review — PR #339 (Round 2)

**Repo:** kagura-agent/cove
**PR:** feat: @mention with autocomplete and highlight (closes #332)
**Verdict:** ✅ **Ready** (with non-blocking notes)

---

## 1. Summary — What changed since R1

The author tightened the mention pipeline end-to-end:

- **Client send path** (`MessageInput.tsx`): substring `replaceAll` replaced with a per-username regex `@${escaped}(?!\w)` (right word boundary) and entries are now sorted by length-desc to neutralize prefix shadowing. `mentionMapRef` is cleared on `channelId` change.
- **Autocomplete** (`MessageInput.tsx` + `MentionAutocomplete.tsx`): `onBlur` with 150 ms delay closes the popup; key intercept is gated on `mentionHasResults.current` so Enter/Arrow/Tab pass through when there are no candidates.
- **Server resolve** (`messages.ts` repo): `createFromWebhook`, `update`, `getById`, `list` all run `resolveMentions()`; resolution joins `guild_members` so out-of-guild users are stripped (no info leak).
- **Mention counts** (server `readStates` + `messagesRoutes` + `webhookExecuteRoutes`): atomic `incrementMentionCount`; edit path only increments for newly added mentions; webhook path increments for every resolved mention.
- **Client dedupe** (`gateway-subscriptions.ts`): `mentionedMessageIds` Set prevents MESSAGE_UPDATE from double-counting after MESSAGE_CREATE; active-channel guard added.
- **Self-mention** (`MessageItem.tsx`): highlight skipped when `message.author.id === currentUserId`.
- **Badge cap** (`Sidebar.tsx`): `{count > 99 ? "99+" : count}`.
- **Type contract** (`shared/types.ts`): `mentions: User[]`.
- **DB**: new migration `v11-mention-count.ts` (idempotent `tableExists` + column check), `LATEST_VERSION` bumped to 11, migration tests updated.

All four R1 blockers are addressed. The PR is mergeable.

---

## 2. Previous Issues Status

| ID | Issue | Status | Notes |
|----|-------|--------|-------|
| **C1** | `replaceAll` substring collision | ✅ Fixed | Regex `@${escaped}(?!\w)` + sort by length desc + clear on channel switch. See minor caveat in §3.1. |
| **Stella-1** | Webhook messages skip `resolveMentions` | ✅ Fixed | `createFromWebhook` now resolves and `webhooks.ts` increments mention_count for all mentioned users. |
| **Stella-2** | MESSAGE_UPDATE mention counts in active channel | ✅ Fixed | Client: `msg.channel_id !== activeChannelId` guard + `mentionedMessageIds` dedupe. Server: only increments for IDs not in `existing.mentions`. |
| **Vega-1** | No `onBlur` → dangling autocomplete | ✅ Fixed | 150 ms delayed close, long enough for `onMouseDown` to fire first. |
| S1 | Autocomplete a11y (role=listbox, aria-activedescendant) | ❌ Not Fixed | **Escalated** — three reviewers flagged this; still no ARIA. Non-blocking but should be a follow-up issue. |
| S2 | Badge overflow / no cap | ✅ Fixed | `99+` cap implemented. |
| S3 | `@` trigger regex too broad | ❌ Not Fixed | `/@\w*$/` still fires after `email@bo…`. Non-blocking. |
| Nova-a | `mentionMapRef` not cleared on channel switch | ✅ Fixed | `useEffect([channelId])` clears the map. |
| Nova-b | `MessageItem` creates new `Map()` every render | ❌ Not Fixed | Still allocated per render; consider `useMemo([message.mentions])`. Non-blocking perf nit. |
| Nova-c | `Message.mentions` type contract (`unknown[]`) | ✅ Fixed | Now `User[]` in `shared/types.ts`. |
| Nova-d | No new tests for mentions | ❌ Not Fixed | Only `LATEST_VERSION` bumps. No coverage for `resolveMentions`, autocomplete behavior, or substring-collision regression. **Escalated** — recommend adding before next mention-touching PR. |
| Vega-b | `mentionedMessageIds` Set grows unbounded | ⚠️ Partially Fixed | Cleared in `teardownGatewaySubscriptions`, but never trimmed during a long-lived session. LRU cap of a few thousand entries would be safe. Non-blocking. |

---

## 3. New Issues introduced by R2 fixes

### 3.1 Word boundary missing on the LEFT of `@` (low severity)
`MessageInput.tsx`:
```ts
new RegExp(`@${escaped}(?!\\w)`, "g")
```
The right-side `(?!\w)` correctly blocks `@alice` matching inside `@aliceWonderland`. But there is no left-side check: a literal `bob@alice ` typed in chat would still be rewritten to `bob<@aliceId> `. Realistic only for email-like input, but easy to harden:
```ts
new RegExp(`(^|\\W)@${escaped}(?!\\w)`, "g")
```
…and prepend `m[1]` in the replacement. Non-blocking.

### 3.2 Stale `mentionMapRef` entries can rewrite literal text (low severity)
Flow: user picks `@alice` from autocomplete → deletes the inserted mention → types the string `@alice` manually elsewhere → presses Send. The map still has `alice → id`, so the literal text gets converted to `<@id>`. Cleanup ideas:
- On each `handleChange`, prune entries whose `@username` substring is no longer present.
- Or anchor mentions by inserting a sentinel token instead of `@username`.

Non-blocking; the worst case is an unintended mention, not data loss.

### 3.3 `resolveMentions` assumes all messages in batch share a channel
`messages.ts` repo:
```ts
const channelId = [...channelIds][0];
```
Comment acknowledges the assumption, and current callers (`list`, `getById`, `create`, `createFromWebhook`, `update`) each pass a single channel. Fragile if a future caller batches across channels — would silently resolve against the wrong guild. Consider iterating per-channel, or asserting `channelIds.size === 1` in dev mode.

### 3.4 "Unknown User" fallback on render
`ChatMarkdown.tsx`:
```ts
const username = mentionUsers?.get(token.userId) ?? "Unknown User";
```
If the mentions array is populated but the matching user isn't in the map (e.g., a transitional render where `MessageItem`'s map hasn't been rebuilt yet), the UI flashes "@Unknown User". Probably not reachable in practice given how `MessageItem` builds the map from the same `message.mentions` it just received, but worth flagging.

### 3.5 Client/server mention_count divergence on reconnect (informational)
Client uses an in-memory `mentionedMessageIds` Set, but server increments are persisted to DB. If the client misses a MESSAGE_CREATE event during a brief disconnect and only sees the eventual MESSAGE_UPDATE, the dedupe Set won't have the ID and the client will bump its local count, while the server may not double-count. The READY resync papers over this on full reload, but mid-session counts can briefly diverge. Acceptable.

---

## 4. Remaining Suggestions (non-blocking follow-ups)

1. **a11y**: add `role="listbox"`, `aria-activedescendant`, `id`s on items in `MentionAutocomplete`, and announce results count via `aria-live`.
2. **Trigger regex**: require start-of-input or non-word-char before `@` to suppress autocomplete inside emails / URLs.
3. **Tests**: at minimum
   - `resolveMentions` strips non-guild-members
   - regex collision test: `@alice` not replaced inside `@aliceWonderland`
   - `MentionAutocomplete` keyboard nav + Enter
   - `setMentioned` / `markRead` interaction
4. **`MessageItem`**: memoize `mentionUsers` map with `useMemo`.
5. **`mentionedMessageIds`**: cap or use an LRU.
6. **Hardening**: `(^|\W)` prefix in mention-replace regex (§3.1).

---

## 5. Positive Notes

- The migration is **idempotent and defensive**: `tableExists` check + `PRAGMA table_info` column check before `ALTER TABLE`. Good pattern.
- Mention resolution is **scoped to guild members via JOIN** — no cross-guild user info leak. This is the right security model.
- `stopImmediatePropagation` on Enter, combined with the `mentionHasResults.current` gate, cleanly fixes both the "Enter sends while selecting" and the "Enter swallowed when no results" failure modes.
- Self-mention exclusion is implemented in the right place (`MessageItem`), and the highlight uses a subtle 8% gold tint with a left border — visually consistent with chat UX conventions.
- `markRead` resets `mention_count` to 0 atomically in the same `INSERT … ON CONFLICT` statement — no race window.
- Server-side edit increment uses set diff (`existingMentionIds`) so re-editing a message that already mentioned you doesn't ding you again. Nice touch.
- Type contract upgrade `unknown[] → User[]` makes downstream code (MessageItem, gateway handlers) actually type-safe.

---

**Rating: ✅ Ready to merge.** The R1 blockers are all closed and the new code is sound. The remaining items (a11y, tests, regex/Set hardening, useMemo) are real but appropriate for follow-up issues rather than blocking this PR. Recommend filing a `mention-followups` tracking issue capturing items in §3 and §4 before merge.
