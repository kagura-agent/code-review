# Stella Review — PR #339 Round 2

**Rating: ⚠️ Needs Changes**

## Summary

The Round 1 fixes landed for several UI issues: the autocomplete now closes on blur, badges are capped at `99+`, webhook messages resolve mentions, self-authored mentions no longer highlight, and the original `@alice` → `@aliceWonderland` substring collision is mitigated.

However, I found two correctness problems that should block merge:

1. Mention parsing only accepts numeric IDs, but Cove still creates/accepts non-numeric user IDs for bots/custom users, so many autocomplete-inserted mentions will not resolve or render.
2. The previous MESSAGE_UPDATE mention-count bug is still not fixed for active-channel users; edits that add a mention persist a server-side badge count without acknowledging/clearing it.

`pnpm -r build` passes.

## Previous Issues Status

### Critical / blocking from Round 1

- ✅ **C1: `replaceAll` substring collision corrupts messages** — Replaced with escaped regex and `(?!\w)`, plus entries are sorted by username length and `mentionMapRef` is cleared on channel switch/send. This fixes the reported `@alice` / `@aliceWonderland` case.
  - Note: see new issue N3 for remaining display-name/global-replacement edge cases.

- ✅ **Stella-1: Webhook messages never resolve mentions** — Fixed. `createFromWebhook()` now calls `resolveMentions()`, and webhook execution increments `mention_count` for mentioned users.

- ❌ **Stella-2: MESSAGE_UPDATE mention counts for active-channel users** — Not fixed; escalated.
  - Server increments `mention_count` when an edit adds a new mention (`packages/server/src/routes/messages.ts:156-162`).
  - Client only applies local update badges for non-active channels (`packages/client/src/lib/gateway-subscriptions.ts:68`).
  - There is no ack/clear path for “message in my active channel was edited to mention me”, so the persisted server `mention_count` remains non-zero until some later unrelated ack. This can resurface as a stale mention badge after reload or after switching channels.

- ✅ **Vega-1: No onBlur → dangling autocomplete steals global keys** — Fixed with textarea `onBlur` delayed close.

### Non-blocking suggestions from Round 1

- ❌ **S1: Autocomplete lacks a11y bindings** — Still open. The list has no combobox/listbox roles, `aria-activedescendant`, option roles, or live status.
- ✅ **S2: Badge overflow / no cap** — Fixed with `99+` cap.
- ⚠️ **S3: Autocomplete trigger regex too broad** — Partially addressed, but the trigger is now ASCII-word-only (`/@(\w*)$/`), which still triggers in cases like email-like text and excludes non-ASCII/hyphenated/space-containing names while filtering supports arbitrary usernames.
- ✅ **Nova: `mentionMapRef` not cleared on channel switch** — Fixed.
- ❌ **Nova: `MessageItem` creates new `Map()` every render** — Still open. `mentionUsers` is rebuilt on every render.
- ✅ **Nova: `Message.mentions` type contract broken** — Fixed in shared type to `User[]`, and repo paths initialize/resolve arrays.
- ❌ **Nova: No new tests** — Still no tests for mention parsing, webhook mention counts, edit mention counts, or autocomplete replacement.
- ❌ **Vega: `mentionedMessageIds` Set grows indefinitely** — Still open. It is cleared only on gateway teardown, not bounded during long sessions.

## New Issues

### N1 — Non-numeric user IDs cannot be mentioned or rendered (blocking)

`parseMentionIds()` and the client markdown parser only match `<@(\d+)>`:

- `packages/server/src/repos/messages.ts:82-89`
- `packages/client/src/lib/chat-markdown.ts` mention rule uses the same numeric-only pattern

But Cove still supports non-numeric user IDs:

- `packages/server/src/routes/agents.ts` derives bot/user IDs from username slugs when no explicit ID is provided.
- `UsersRepo.create()` also uses the provided ID or username slug.
- Existing migration tests still cover legacy/non-snowflake IDs, and route inputs can provide custom IDs.

Autocomplete inserts `<@${userId}>`; if that `userId` is `luna`, `my-bot`, or any custom non-numeric ID, the server will not resolve it into `message.mentions`, mention counts will not increment, and the client will render raw `<@my-bot>` instead of a mention pill.

**Suggested fix:** allow the project’s actual user ID grammar in both parsers, e.g. parse `<@([^>\s]+)>` or another validated ID pattern shared between client/server. Add tests with numeric and non-numeric IDs.

### N2 — Active-channel edit mentions still leave stale persisted mention counts (blocking; R1 escalation)

As noted above, the server increments `mention_count` on edit, but active clients do not ack/clear MESSAGE_UPDATE mentions. This leaves unread mention state persisted for a message the user has already seen in the open channel.

**Suggested fix options:**

- If an edited message mentions a user currently viewing the channel, dispatch/perform an ack or avoid incrementing for currently-active sessions; or
- Have the client ack the edited message when `MESSAGE_UPDATE` arrives for the active channel; and
- Add a server/client test covering “other user edits active-channel message to mention me; mention_count remains 0/cleared”.

### N3 — Mention replacement is still spanless and username-keyed (correctness edge case)

`mentionMapRef` maps `username → userId`, and submit converts every matching `@username` occurrence globally (`packages/client/src/components/MessageInput.tsx:94-99`). This can still mention the wrong user when:

- Two guild members share the same username/display name.
- The user selects one `@sam`, then later types literal `@sam` text that was not selected from autocomplete.
- A selected username is a prefix before punctuation/hyphen (`(?!\w)` does not protect `@alice-bot`, `@alice.example`, or non-ASCII word continuations).

This is less severe than N1/N2, but the robust fix is to keep selected mention spans/tokens or insert hidden wire-format IDs rather than doing global display-name replacement at send time.

## Remaining Suggestions

- Add focused tests for:
  - numeric and non-numeric mention IDs,
  - webhook mention resolution/counts,
  - create vs edit mention-count behavior,
  - active-channel edit mention ack/clear,
  - replacement collision cases.
- Add autocomplete ARIA roles/keyboard semantics.
- Bound or otherwise prune `mentionedMessageIds` during long-running sessions.
- Memoize `mentionUsers` in `MessageItem` if render cost becomes noticeable.

## Positive Notes

- The guild-scoped SQL join in `resolveMentions()` preserves the intended privacy boundary.
- Webhook mention resolution is now wired through create + dispatch paths.
- The blur fix and `stopImmediatePropagation()` handling make the autocomplete interaction much safer.
- Build passes cleanly with the current diff.
