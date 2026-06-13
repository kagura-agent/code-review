# 🌟 Stella Review — kagura-agent/cove PR #339

## Summary

This PR adds Discord-style user mentions end-to-end: client autocomplete and display conversion, markdown mention chips, self-mention highlighting, server-side mention resolution, `mention_count` persistence, and sidebar badges. The broad shape is solid and the security-sensitive rendering/SQL pieces are mostly handled safely, but I found several real correctness bugs that should be fixed before merge.

**Verdict: ⚠️ Needs Changes**

Validation run locally:
- `pnpm -F @cove/server test -- --runInBand` ✅ 223 passed
- `pnpm -F @cove/client test` ✅ 6 passed
- `pnpm -r build` ✅ passed (existing large chunk warning)

## Critical Issues

1. **Webhook-created messages never resolve or count mentions**
   - `MessagesRepo.createFromWebhook()` returns `mentions: []` and does not call `resolveMentions()` (`packages/server/src/repos/messages.ts:196-227`).
   - `routes/webhooks.ts` dispatches that message directly and never increments `mention_count` (`packages/server/src/routes/webhooks.ts:187-197`).
   - Impact: webhook/agent messages containing `<@userId>` will not render as mention chips, will not highlight the mentioned user, and will not update mention badges. This is especially risky because Cove agents/draft-style integrations often send through non-human channels.
   - Fix: resolve mentions for webhook messages the same way as normal messages, and increment mention counts for resolved mentioned users except the webhook/author identity as appropriate.

2. **Client mention conversion is username-based and can corrupt messages / target the wrong user**
   - Selection stores `displayName → userId` in `mentionMapRef` (`MessageInput.tsx:152-158`), then submit does a global `replaceAll(@username, <@id>)` (`MessageInput.tsx:83-92`).
   - `users.username` is not unique in the schema, so duplicate usernames are possible. Selecting two users with the same username overwrites the map key, and every `@sameName` in the message is converted to the last selected user.
   - It also converts manually typed `@username` text if that username was selected once anywhere in the draft, even when the user did not intend a mention.
   - Fix: track mention ranges/tokens by inserted occurrence, or keep the wire format in an internal model while rendering/displaying `@username`; do not globally replace by username string.

3. **MESSAGE_UPDATE mention counts can remain unread for users viewing the active channel**
   - On edit, the server increments `mention_count` for newly mentioned users (`routes/messages.ts:156-164`) before dispatching `MESSAGE_UPDATE`.
   - The client intentionally does not call `ackMessage` on `MESSAGE_UPDATE` when the edited message is in the active channel; only `MESSAGE_CREATE` has auto-ack behavior.
   - Impact: draft streaming/edit flows that add a mention while the user is actively reading the channel can leave a persisted mention badge until another ack happens/reload behavior catches up. This is a count accuracy bug in one of the PR’s key flows.
   - Fix options: have active-channel clients ack the updated message when it mentions them, or make the server increment conditional on the user’s read cursor being behind the edited message / active-session state if available.

## Product Impact

- Users can see mention chips/highlights for normal REST-created messages, but webhook/agent messages will silently miss the feature.
- Autocomplete UX can send unintended mentions in messages with repeated names or duplicate usernames.
- Mention badges can become inaccurate around streaming edits and active readers.
- Existing pre-migration unread mentions are not backfilled into `mention_count`; that may be acceptable, but it should be an intentional product decision.

## Suggestions

- Add focused tests for:
  - webhook message with `<@userId>` resolves `mentions` and increments `mention_count`;
  - duplicate usernames / repeated `@username` occurrences in `MessageInput`;
  - `MESSAGE_UPDATE` adding a mention while active vs inactive;
  - markdown parsing of mentions adjacent to bold/links/code.
- Improve autocomplete accessibility: use `role="listbox"` / `role="option"`, expose active option via ARIA, and make mouse/keyboard behavior screen-reader friendly.
- Cap or compact sidebar badge display (`99+`) to avoid layout issues with large counts.
- Consider supporting Discord’s `<@!id>` mention variant if any bridge/plugin may emit it.
- Consider showing unresolved mentions as the original `<@id>` or a neutral unresolved chip rather than `@Unknown User`, depending on desired transparency.

## Positive Notes

- Mention resolution uses parameterized SQL and guild membership joins, which avoids the obvious injection and cross-guild user enumeration pitfalls.
- React rendering escapes usernames, so the mention chip path does not appear XSS-prone.
- Mention parsing is simple and bounded by content validation; I did not see a ReDoS concern.
- Batch resolution for normal message lists avoids per-message user lookups.
- The PR keeps the migration small and idempotent, and the repo builds/tests pass locally.
