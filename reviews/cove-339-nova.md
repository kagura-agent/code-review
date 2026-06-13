# PR #339 Review — `feat: @mention with autocomplete and highlight`

Reviewer: 🌠 Nova
Repo: kagura-agent/cove
Verdict: **⚠️ Needs Changes** (one real bug in send-time wire conversion; everything else is non-blocking)

---

## 1. Summary

Re-open of reverted #337, single-commit. Adds end-to-end `@mention` support:

- **Parser** (`chat-markdown.ts`): new `mention` token from `<@digits>`.
- **Client UI**: `MentionAutocomplete` popover + cursor-tracked `MessageInput`; pill rendering in `ChatMarkdown`; gold left-border highlight in `MessageItem` when current user is mentioned; red mention-count badge in `Sidebar`.
- **Server**: `MessagesRepo.resolveMentions` populates `Message.mentions` with a single guild-scoped batched query (closes the #337 info-leak); `mention_count` column via `v11` migration; routes increment on create/update and reset on ack.
- **Gateway**: pre-fetches members on READY (autocomplete fuel); MESSAGE_UPDATE now carries mentions and bumps badge for newly mentioned users with de-dup via `mentionedMessageIds` set.

Architecture and SQL discipline are clean. One client send-path bug needs to be fixed before merge.

---

## 2. Critical Issues (must fix)

### 🔴 C1 — Send-time substring replacement can corrupt unrelated text
`MessageInput.handleSubmit`:
```ts
for (const [username, userId] of entries) {
  text = text.replaceAll(`@${username}`, `<@${userId}>`);
}
```
This is a literal substring `replaceAll`, not a boundary-aware replacement. Concrete failure:

- User autocompletes `@alice` (map: `alice→id`).
- Later types `@aliceWonderland` literally (no autocomplete; just text).
- On submit, the substring `@alice` inside `@aliceWonderland` is replaced, producing `<@id>Wonderland` on the wire — a mention the user never made.

It also fires for any literal `@alice` that was typed manually after a real autocomplete, silently converting plain text into a ping.

Fix: track mention insertions as `{userId, startPos, length}` (or store as `(start,end)` ranges that are slid as the user edits) and apply replacements by index, not by substring match. Alternatively, after each `@username ` is inserted, immediately commit it to the wire form `<@id>` and keep a parallel display map for rendering — but that requires a custom editor. The simplest minimal fix: require a word-boundary, e.g. replace only `(^|\s)@username(\s|$|[.,!?])` and walk the map once with a single regex pass.

This is the only blocker.

---

## 3. Product Impact

- Self-mentions render the yellow “you’re mentioned” bar on **your own** message. Probably not intended; Discord does not do this. Easy guard: `isMentioned = mentions.some(u => u.id === self) && message.author.id !== self`.
- Mention count badge has **no overflow cap** (`{mentionCount}` printed raw). A user away for a while gets a `1234` badge that breaks the row layout. Use `count > 99 ? "99+" : count`.
- Mention pills have `cursor: "pointer"` but no `onClick` — affordance lies to the user.
- Autocomplete trigger regex `/@\w*$/` fires even when `@` is preceded by a word char, e.g. typing `email@gmail` opens the popover at `gmail`. Pin trigger to start-of-text/whitespace: `/(^|\s)@\w*$/`.
- `\w` excludes Unicode letters; non-ASCII usernames (Chinese, accented Latin) can’t be searched via the inline filter. Members are still listed (empty query), so not a hard block, but worth noting given Kagura’s user base.
- Backspacing a mention deletes one character at a time, leaving `@alic`, `@ali`… and the `mentionMapRef` entry stays stale. Map is cleared on submit so no wire-format leak, but partial display strings end up sent as plain text. Mostly cosmetic.

---

## 4. Suggestions (non-blocking)

**Client**

- `MessageItem` constructs `new Map()` for `mentionUsers` every render. If `ChatMarkdown` is memoized (the `Inner` suffix suggests so), prop identity churns kill the memo. Wrap with `useMemo(() => new Map(...), [message.mentions])`.
- `MentionAutocomplete` lacks a11y bindings — no `role="listbox"`, no `aria-activedescendant`, the textarea has no `aria-expanded` / `aria-controls`. Screen-reader users get nothing.
- `MentionAutocomplete` adds a `window` `keydown` listener with `capture=true`. The redundant guard in `MessageInput.handleKeyDown` (using `mentionHasResults` ref) is belt-and-suspenders; consider removing one or the other to avoid two sources of truth.
- `mentionMapRef` is not cleared when the user switches channel inside the same `MessageInput` instance. If the parent does not remount (verify), a mention from channel A could re-fire in channel B. Add a `useEffect(() => { mentionMapRef.current.clear() }, [channelId])`.
- `MESSAGE_UPDATE` mention de-dup uses an in-memory `mentionedMessageIds` `Set` with no eviction. Long-lived sessions leak a small string per message ever updated. Trivial, but a cap (e.g. an LRU of last 10k) or scope-by-channel-on-clear would be tidy. Cleared on `teardownGatewaySubscriptions` — good.

**Server**

- `resolveMentions` assumes “all messages in a batch are the same channel” (taken from `[...channelIds][0]`). True today (caller paths are per-channel) but the assumption is implicit. A `console.assert` or grouping by `channel_id` would future-proof.
- `Message.mentions: User[]` is now a required field in `shared/types.ts`, but `resolveMentions` early-returns when `allIds.size === 0` and leaves `msg.mentions` `undefined`. The client tolerates it with optional chaining, but the type contract is broken. Either default-assign `msg.mentions = []` at the top of the loop, or change the field to optional.
- Mentions that point to users who are not guild members are silently dropped (`.filter((u): u is User => u !== undefined)`). The chip renders “Unknown User” on the client. That’s actually the right call (privacy), but the index-mapping means a hand-crafted `<@bad><@good>` ends up with one element, and the client can’t tell which `<@id>` was kept. If you ever want to render “@Unknown User” for unknown IDs, you need to keep a placeholder. Not urgent.
- `parseMentionIds` is called twice per message in `resolveMentions` (once for the global set, once in the final assignment). Negligible, but cache it.

**Migration**

- `v11` is a pure additive `ALTER TABLE ... ADD COLUMN ... DEFAULT 0`. Safe and idempotent (column-existence guard present). Good.

**Tests**

- Only the migration version constants were bumped. No new tests for:
  - `resolveMentions` (guild scoping, unknown user, batched query)
  - `readStates.incrementMentionCount` + ack reset
  - Mention parser token (`<@123>`) and mixed-with-other-formatting cases (e.g. `**hi <@123>**` — need to verify the `bold` rule consumes children correctly and the mention token is emitted inside `bold.children`).
  - Substring corruption in `MessageInput` (C1).

  Strongly recommend at least one server-side test and one parser test before merge.

---

## 5. Positive Notes

- ✅ SQL is parameterized everywhere — no injection surface. The guild-scoped JOIN closes the #337 info-leak cleanly.
- ✅ `<@(\d+)>` is digit-bounded → no ReDoS risk.
- ✅ Atomic `INSERT … ON CONFLICT … mention_count = mention_count + 1` handles concurrent writes correctly at the DB level.
- ✅ Ack path resets `mention_count` to 0 in the same `UPSERT` — no separate write needed.
- ✅ MESSAGE_UPDATE de-dup via `mentionedMessageIds` is the right shape for the draft-streaming use case described in the PR body.
- ✅ Server only increments for mentioned users **other than the sender** — correct.
- ✅ React rendering of `@{username}` is auto-escaped — no XSS via mention text.
- ✅ `stopImmediatePropagation` on Enter inside autocomplete + the `onHasResults` gate in `MessageInput.handleKeyDown` together correctly fix the “Enter sent the message while picking” bug from #337.
- ✅ Pre-fetching members on READY is the pragmatic choice; lazy fetch would race the first `@` trigger.
- ✅ `replaceAll` entries sorted by descending username length — good instinct, partially mitigates (but does not solve) the substring-collision class. See C1 for the remaining hole.

---

## TL;DR

Solid PR overall, clean server architecture, security posture is sound. **Fix C1** (substring-based wire conversion) before merge; the rest are quality-of-life follow-ups. Recommend a server test for `resolveMentions` guild-scoping while you’re in there.
