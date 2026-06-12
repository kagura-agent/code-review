# Cove PR #335 Review — 🌠 Nova

**PR:** feat: message reply/quote — Discord-style (closes #297)
**Author:** kagura-agent · **+305 / -25**, 15 files

---

## 1. Summary

A clean, end-to-end implementation of Discord-style message replies. The slice is well-factored: a single new column at the DB layer, a focused server change (input validation + batched referenced-message hydration), a small zustand store, and two new components (ReplyBar, MessageReplyQuote) that compose into the existing message UI. The Discord API shape (`message_reference` + `referenced_message`) is respected, which is good for compatibility.

**Verdict:** ⚠️ **Needs Changes** — no showstoppers, but two correctness issues should be tightened before merge (batch hydration is channel-scoped in a way that hides cross-channel replies; reply-state lifecycle on channel delete / message delete is unmanaged). All other findings are non-blocking polish.

---

## 2. Critical Issues (please address before merge)

### C1. Batch hydration filters by `channel_id`, but stored references are not constrained to the same channel
`repos/messages.ts` (`populateReferencedMessages` and `getById`) only joins referenced rows with `AND m.channel_id = ?`. The DB column `referenced_message_id` has no FK and no same-channel constraint, and the route validates the referenced message via `getById(channelId, …)` (good), so today the invariant holds — but a single bug elsewhere that inserts a cross-channel reference would silently render every reply in that channel as “Original message was deleted.” Two cheap fixes, pick one:
- Drop the `AND m.channel_id = ?` filter in hydration and just look up by id (the route already gates inserts), **or**
- Make the invariant explicit by adding a CHECK or a comment + an index. At minimum, log/throw if a stored reference resolves to a different channel.

### C2. No reply-route or repo test coverage
Only `migration.test.ts` was touched. A regression suite for the new behavior is missing:
- POST with valid `message_reference` returns `referenced_message` populated.
- POST with `message_reference.message_id` pointing at a non-existent / deleted / other-channel message returns `10008`.
- `list` populates `referenced_message` for replies whose target is in the same batch (no extra query) and for replies whose target is older (one batched query).
- Reply to a deleted message returns `referenced_message: null`.

Given this is a public API contract addition, please add at least the route-level happy/sad paths.

### C3. Reply state is never cleared on channel delete / message delete / logout
`useReplyStore.replyingTo` grows monotonically per visited channel and is keyed by channel id only.
- If the user starts a reply, then the referenced message is deleted (locally or via gateway), the ReplyBar keeps a stale snapshot and the POST will 400 on send.
- If a channel is removed, its entry leaks.
- No `reset()` on logout/user switch.

Add: (a) subscribe to message-delete events and clear the reply if it matches, (b) expose a `reset()` and call it on logout / channel removal, (c) consider also clearing when switching to a channel that no longer contains the referenced id (optional).

---

## 3. Product Impact

- **New affordance:** ↩ button appears in hover toolbar on every message (including bot/webhook). Confirm this is desired for system messages too — there’s no exclusion.
- **Deleted-original UX:** “Original message was deleted” is shown only when `referenced_message` is `null`. If the referenced message exists but is paginated out, `populateReferencedMessages` will fetch it (good). But if a user **clicks** the quote to jump and the original is not yet in the DOM (older history), `handleJumpToMessage` silently no-ops. Consider either disabling the click or triggering a “load older until found” flow. As-is, users will perceive the jump as broken for older replies.
- **Optimistic send:** On send failure, `replyMsg` is already cleared from the store, so the user loses the draft reply context and has to re-click ↩. Consider restoring the reply on failure (parallel to how content is, or isn’t, restored — verify with `MessageInput` failure path).
- **Cross-guild / DM:** Route validates same-channel only; good. Confirm DM channels are exercised.
- **Mobile / focus management:** ReplyBar appears above input but there is no auto-focus on the textarea when ↩ is clicked. Small but Discord does focus the input.

---

## 4. Suggestions (non-blocking)

**Server**
- `MessagesRepo.create` does a full `getById(channelId, referencedMessageId)` after INSERT to populate `referenced_message`; this re-runs the join + reactions lookup for a message you just validated in the route. Since the route already loaded `refMsg` via `getById` to validate existence, consider passing it into `create()` (or returning it) to avoid the duplicate query on every reply.
- `MSG_SELECT` does a `LEFT JOIN users`. The new column is fine, but `SELECT m.*` plus joined columns risks future column-name collisions; consider explicit columns.
- Migration is forward-only with no `down`. Other migrations in this repo appear to share that pattern, so this is consistent — just confirm policy.
- Migration does `ALTER TABLE … ADD COLUMN`; no index. Replies are looked up by parent id in batch with `IN (…)`, which is small per page (≤50). An index on `referenced_message_id` is **not** needed for the read path, but if you ever want “show all replies to this message,” you’ll want one. Note for later.
- `populateReferencedMessages`’s second param `_currentUserId` is unused; either wire it through (so the referenced message’s reactions reflect the current user’s `me`) or drop it.
- Referenced messages in the hydrated payload do **not** include `reactions`. That’s a deliberate-looking omission and fine for a quote preview, but worth a code comment.

**Client**
- `MessageReplyQuote`: `referencedMessage.content` is rendered as plain text (good — React escapes). But if the original message had markdown / mentions, the quote shows raw `**bold**` and `<@123>`. Consider rendering a stripped-markdown preview (same as Discord) — non-blocking.
- `MessageItem`: `MessageActions` now takes the full `message` object instead of two scalars, causing the actions subtree to re-render on every message identity change. Keep `messageId` + `channelId` + a stable `onReplyClick={() => setReplyingTo(channel_id, message)}` if you want to preserve the previous referential stability.
- `ReplyBar`: the ✕ uses a `<span>` with `onClick` — should be a `<button type="button">` for a11y/keyboard.
- `MessageInput`: `borderTop: "none"` toggle when reply is active is a nice touch; verify it still looks correct in the failed-send / cleared-reply transition (no double border flash).
- `handleJumpToMessage`: 2000ms timeout is fine, but if the user clicks two different quotes in quick succession, the first timeout removes the class from the *second* element. Track per-element timeouts or use a CSS animation-end listener.
- `useReplyStore`: setter overwrites `null` rather than deleting the key. Minor — over time the object grows. `clearReply` could `delete` the key.
- `api.sendMessage`: the new positional `messageReference` param is the 4th arg after an optional 3rd (`nonce`); now every call site must remember to pass `undefined` for nonce if they want to set a reference. Future-proof by switching to an options object.
- `types.ts` (client) just re-exports `Message` — good, no drift.

**Tests / hygiene**
- The migration tests assert `expect(version).toBe(10)` across all blocks. Consider importing `LATEST_VERSION` from `migrations/index` so the test doesn’t need touching on the next bump.
- A test block comment still says `// Version should be 3` (pre-existing); the bump didn’t fix it.

---

## 5. Positive Notes

- **Batched hydration is the right call.** Checking the current page first and only fetching missing ids in one `IN (…)` query avoids the obvious N+1 trap.
- **Validation is server-side and correct.** The route checks shape, existence, and same-channel scoping before insert; no SQL injection surface (all parameterized).
- **Discord-compatible payload shape.** `message_reference` + `referenced_message: Message | null` matches the Discord schema, which keeps the door open for forwards/system-replies later.
- **Optimistic state captured before async.** `replyMsg` is read+cleared synchronously, so the ReplyBar disappears immediately on send (good UX) and reconciliation replaces the optimistic quote with the server’s authoritative copy.
- **CSS keyframe highlight is tasteful** and uses `color-mix` for theme-aware accent — no hardcoded colors.
- **Per-channel reply state** is the right model — switching channels doesn’t clobber a draft reply.
- **No XSS surface introduced.** All quoted content goes through React text nodes; `ChatMarkdown` is unchanged.

---

**Rating:** ⚠️ Needs Changes — address C1 (hydration scoping intent), C2 (add reply tests), C3 (store lifecycle); the rest can land as follow-ups.
