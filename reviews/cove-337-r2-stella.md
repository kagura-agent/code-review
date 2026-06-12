# 🌟 Stella — Round 2 Re-review of PR #337

**PR:** kagura-agent/cove#337 — `feat: @mention with autocomplete and highlight`  
**Verdict:** ⚠️ Needs Changes

## Summary

The author did address the main Round 1 server-side safety issues and the obvious Enter-key regression: mention resolution is now guild-scoped, edits resolve mentions, and the unrelated workflow change is gone. The branch also builds successfully with `pnpm -r build`.

However, a fresh pass found a blocking product issue in the autocomplete data flow: the new mention autocomplete reads only from `useMemberStore`, but that store is not populated on normal app startup. Members are fetched only when `MemberList`/bot management/settings paths are opened, while the READY gateway path seeds guilds/channels but not members. In a normal chat session, typing `@` will usually show no suggestions, so the headline autocomplete feature silently does not work until the user opens another UI first.

There are also a couple of correctness gaps around mention parsing/creation paths that should be fixed or explicitly scoped.

## Previous Round Findings Check

1. **Enter blocked when no autocomplete matches** — **Mostly addressed.**  
   `MessageInput` now gates Enter/Tab/arrow/Escape handoff on `mentionHasResults.current`, and `MentionAutocomplete` reports `filtered.length > 0`. This prevents the main no-results Enter swallow in normal operation.

2. **`cursorPos` stale on caret moves** — **Addressed.**  
   `onSelect` and `onClick` now call `syncCursor`, and `handleChange` updates cursor position as well.

3. **Mention resolution leaks non-guild users** — **Addressed.**  
   `resolveMentions` now joins `guild_members` using the channel guild before returning user objects.

4. **Edited messages do not refresh mentions** — **Addressed.**  
   `MessagesRepo.update()` calls `resolveMentions([msg])` before returning and dispatching the update.

5. **Unrelated workflow change** — **Addressed.**  
   The latest PR diff no longer contains the CI `sleep 120` change.

## Critical Issues

### 1. Autocomplete usually has no member data on normal startup

**Files:**
- `packages/client/src/components/MentionAutocomplete.tsx:49-61`
- `packages/client/src/App.tsx:191-217`
- `packages/client/src/lib/gateway-subscriptions.ts:109-131`
- `packages/client/src/components/MemberList.tsx:52-60`

`MentionAutocomplete` filters `useMemberStore.getMembers(activeGuildId)`, but the normal app initialization path only seeds guilds and channels from READY. It does not seed or fetch guild members. The only obvious fetch is inside `MemberList`, which is mounted only when `membersOpen` is true.

That means a user who opens Cove, selects a channel, and types `@` will get an empty filtered list and no popup, even though guild members exist. Opening the member list first can accidentally make autocomplete start working, which makes this especially confusing and hard to discover.

**Expected fix:** Ensure member data is available before/when autocomplete opens. Options:
- Fetch members for the active guild when `MentionAutocomplete` opens and the store is empty.
- Or seed members in the READY payload/subscription path.
- Or fetch members during active guild/channel initialization.

The first option is probably the smallest scoped fix.

### 2. Webhook-created messages do not resolve mentions for immediate REST/gateway responses

**File:** `packages/server/src/repos/messages.ts:196-227`

`create()` resolves mentions, but `createFromWebhook()` still returns `mentions: []` and does not call `resolveMentions`. Later `GET /messages` will resolve them, but the immediate webhook response and `MESSAGE_CREATE` gateway dispatch from `webhookExecuteRoutes` will not include mention users, so clients receiving the live event cannot render mention pills or highlight current-user mentions until a reload/refetch.

**Expected fix:** Call `this.resolveMentions([msg])` in `createFromWebhook()` before returning, matching `create()`.

## Product Impact

- The primary user-facing feature — typing `@` and seeing autocomplete — can appear completely broken in a normal session.
- Live webhook/bridge messages containing `<@id>` will not highlight or render consistently on first delivery.
- The previously serious guild-scope privacy issue appears fixed, which is good, but the feature is not reliable enough to ship yet.

## Suggestions

- **Mention ID regex is still too narrow.** Both client markdown and server parsing use `<@(\d+)>`. Most seeded/registered users are snowflakes, but `/users` can still create custom non-numeric IDs. If those users can appear in `GuildMember.user.id`, autocomplete can insert `<@custom-id>` that the renderer/server will never resolve. Either enforce numeric mentionable IDs or use a broader safe delimiter-based pattern such as `<@([^>]+)>` with validation.
- Add tests for:
  - no-results Enter submits normally;
  - autocomplete fetches/has members in a fresh app session;
  - mention resolution excludes users outside the channel guild;
  - edit response and `MESSAGE_UPDATE` include updated `mentions`;
  - webhook-created messages include `mentions` immediately.
- Add ARIA roles/attributes (`listbox`, `option`, active descendant) for the autocomplete popup.
- Consider a mention-count cap or chunked SQL queries to avoid SQLite variable limits on maliciously large mention lists.
- Consider click-outside dismissal and scrolling the active option into view.

## Positive Notes

- The R1 privacy leak was fixed correctly with a `guild_members` join.
- Edited messages now resolve mentions, closing a real consistency gap.
- The Enter interception is much safer than R1.
- `pnpm -r build` passes on the reviewed branch.
