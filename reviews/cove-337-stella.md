# PR #337 Review — feat: @mention with autocomplete and highlight

## Summary
This PR adds Discord-style `<@userId>` mentions end-to-end: server-side mention extraction/resolution, shared typing, Markdown tokenization/rendering, autocomplete insertion, and self-mention message highlighting.

Overall the direction is good, and the implementation avoids the obvious XSS/SQL-injection/ReDoS pitfalls. However, I do not think it is ready to merge yet because mention resolution is not permission/guild scoped, and the autocomplete can trap Enter when no suggestion is visible.

**Rating: ⚠️ Needs Changes**

## Critical Issues

1. **Mention resolution leaks users outside the current guild/channel**
   - `packages/server/src/repos/messages.ts` resolves all parsed IDs with `SELECT ... FROM users WHERE id IN (...)`.
   - That means any client can send raw content like `<@someKnownUserId>` and make the API return that user's username/bot/avatar even if the user is not a member of the message's guild/channel.
   - This is a privacy/authorization bug and also makes `mentions` semantically incorrect.
   - Suggested fix: scope the lookup through the message channel's guild, e.g. join `channels -> guild_members -> users`, or pass the guild id into `resolveMentions` and only return users who are guild members and visible in that context.

2. **Autocomplete blocks sending when `@...` has no matches**
   - `MessageInput` sets `showMention` when the text before the cursor matches `/@\w*$/` and then suppresses Enter/Tab/Escape/arrow handling while `showMention` is true.
   - `MentionAutocomplete` returns `null` and does not install its key handler when `filtered.length === 0`.
   - Result: typing something like `@zzzz` with no matching member leaves no popup visible, but pressing Enter is still swallowed by `MessageInput`, so the message cannot be sent until the user edits/dismisses in a way that changes `showMention`.
   - Suggested fix: have the autocomplete report whether it is actually open/has options, or allow Enter to submit when there are no suggestions. Escape should also be able to clear the mention state even with zero matches.

3. **Edited messages do not get refreshed mention metadata**
   - `list`, `getById`, and `create` resolve mentions, but `update()` still returns `toMessage(row)` without `resolveMentions`.
   - If a user edits a message to add/remove a mention, the REST response and `MESSAGE_UPDATE` payload will have stale/empty `mentions`, so mention pills render as `Unknown User` and self-mention highlighting is wrong until a later reload/list fetch.
   - Suggested fix: call `resolveMentions([updated])` in `MessagesRepo.update()` and ensure the client store applies updated `mentions`, not only `content`/`edited_timestamp`.

## Product Impact

- Users may be unable to send ordinary messages ending in an unmatched `@query` because Enter is intercepted while no autocomplete is visible.
- Raw API clients can mention arbitrary known user IDs; recipients will see resolved identities even when those users are not part of the guild/channel.
- Mentions created by editing messages will not behave consistently with mentions created in new messages.
- The UI currently renders unresolved mentions as `@Unknown User`, which is understandable but can be confusing if metadata is missing because of an update path or member-scope filtering.

## Suggestions

- **Accessibility:** add combobox/listbox semantics to the autocomplete: `aria-expanded`, `aria-controls`, `aria-activedescendant` on the textarea, `role="listbox"`, `role="option"`, and selected state on options. This will make keyboard navigation understandable to screen readers.
- **Cursor/state handling:** `cursorPos` is updated on `onChange` only. Clicking or arrowing to a different cursor position can leave mention detection stale. Consider updating on `onSelect`, `onKeyUp`, `onClick`, and/or textarea `onSelectionChange`-style handling.
- **Keyboard handler scope:** the autocomplete attaches a capturing `window` keydown listener. Prefer handling keys on the textarea or a scoped root element to avoid surprising global interception.
- **Scroll active option into view:** with up/down navigation and a capped list height, call `scrollIntoView({ block: "nearest" })` for the active option.
- **Parser coverage:** consider whether Cove should also support Discord's `<@!userId>` form. If not, tests should document that only `<@userId>` is supported.
- **Tests:** add server tests for batched mention resolution, duplicate mentions, unknown IDs, cross-guild IDs, create/update responses, and client/parser tests for mentions mixed with bold/code/links.
- **Workflow change:** the added `sleep 120` in `.github/workflows/notify-issue-close.yml` is unrelated to mentions. It may be fine, but it should ideally be split out or explained in the PR because it slows all issue-close notifications.

## Positive Notes

- Good choice to store canonical `<@userId>` in content and render from resolved metadata; this keeps the message format Discord-compatible.
- SQL lookup uses parameter placeholders and batches all IDs, so it avoids SQL injection and N+1 queries in the normal list path.
- Mention rendering uses React text nodes for usernames, so usernames are escaped and do not introduce XSS.
- The mention regexes are simple, anchored where appropriate, and not ReDoS-prone.
- The UI covers the expected baseline keyboard controls: up/down, Enter, Tab, and Escape.
