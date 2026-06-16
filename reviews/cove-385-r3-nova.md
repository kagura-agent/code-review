# 🌠 Nova — Round 3 Re-Review: PR #385

**Repo:** kagura-agent/cove
**PR:** feat(client): message actions — reply, edit (#300)
**Verdict:** ✅ **Ready** (with minor follow-ups, none blocking)

---

## R2 Fix Verification

### 1. ✅ Edit text leak on channel switch — **Fixed correctly**
`packages/client/src/components/MessageInput.tsx:62-69` — the channel-switch
`useEffect` now invokes `stopEditing()` and `setContent("")` alongside the existing
mention-map reset. Because `stopEditing` is included in the dependency list and
the same effect runs at mount, switching *to* a channel where a leaked edit
state was sitting in the global `useEditStore` is also defensively reset. Good.

### 2. ✅ Edit failure → red error in edit bar with 3s auto-dismiss — **Fixed correctly**
- New `editError` state (line 50).
- `handleSubmit` catches the API error, sets `setEditError("Failed to save edit")`,
  and schedules `setTimeout(() => setEditError(null), 3000)` (lines 180–184).
- Edit-bar span (line 336) renders the error in `var(--status-danger, #ed4245)`
  with a safe fallback color, and still keeps the `(Esc to cancel)` affordance.

### 3. ✅ Escape only short-circuits when autocomplete has *results* — **Fixed correctly**
Line 154:
```ts
if (e.key === "Escape" && isEditing &&
    !(showMention && mentionHasResults.current) &&
    !(showChannelMention && channelMentionHasResults.current)) { ... }
```
This is the right gate — the same `hasResults` ref that the autocomplete
components feed via `onHasResults` is also what controls the `return` further
down (lines 161–167), so the two behaviors are consistent. Escape on an empty
autocomplete will correctly cancel the edit instead of being swallowed.

---

## New observations on this revision

### Minor — `editError` not cleared on manual cancel / channel switch
`editError` is only cleared in two places: success path and the 3s timeout.
- Clicking the ✕ button or hitting Escape calls `stopEditing()` + `setContent("")`
  but **leaves `editError` alone**. If the user fails an edit, cancels, then
  starts a new edit within 3s, the new edit bar will momentarily show the stale
  red error.
- The channel-switch effect (lines 62–69) likewise doesn't reset it.
- Also, repeated failures within 3s leak `setTimeout` handles — the new one
  doesn't clear the previous, so the first timer can null the second error
  early.

**Suggested fix:** `setEditError(null)` in the cancel handlers and in the
channel-switch effect; track the timeout in a ref and clear before re-arming.
Not blocking — purely cosmetic.

### Minor — Editing renders raw wire-format mentions in the textarea
`startEditing(channelId, message.id, message.content)` passes the **wire**
content. `chat-markdown.ts` matches `<@(\d+)>`, confirming the server stores
mentions as `<@123>` / `<#456>`. The edit textarea will show those raw tokens
to the user. Re-saving without touching them is fine (they pass through
unchanged because `mentionMapRef` only contains entries the user typed during
this session), but it's a UX wart for anyone who wants to delete or move a
mention.

This pre-dated R2 and isn't a regression, so it's reasonable to land it and
follow up with a separate display-name resolver. Worth filing.

### Nit — accessibility wiring is half-finished
The autocomplete lists gained `role="listbox"` / `role="option"` /
`aria-selected` / `id="mention-option-..."` (good!), but the `<textarea>` in
`MessageInput` is not wired with `aria-controls` / `aria-activedescendant`,
so screen readers can't follow the selection. The `id`s are now ready —
adding the two attrs is a small follow-up.

Also: both `MentionAutocomplete` and `ChannelMentionAutocomplete` use the same
`mention-option-` id prefix. Channel and user IDs are globally unique
snowflakes today, but if that ever changes the DOM ids would collide. Cheap
hardening: `'mention-user-' + id` vs `'mention-channel-' + id`.

### Nit — `mentionedMessageIds` cap duplicated
The cap-at-1000 / keep-newest-500 block is duplicated in both `messageCreate`
handlers in `gateway-subscriptions.ts`. Logic is correct (Set insertion order
preserved, trim runs after add so the new id is retained), but extracting a
tiny `recordMentioned(msg)` helper would prevent future drift.

### Nit — Edit submit with empty text silently no-ops
`handleSubmit` returns early when `!text && pendingFiles.length === 0`. Since
edit clears pendingFiles, an empty edit just fails to submit with no feedback.
Most clients either disable the send button or surface "Message cannot be
empty" / convert to a delete prompt. Acceptable for v1; flag for #300 follow-up.

---

## Things I explicitly verified

- `api.editMessage` → server `PATCH /channels/:id/messages/:msgId`
  (`packages/server/src/routes/messages.ts:253`) — author-only check, 4000-char
  validation, `messageUpdate` dispatch, mention-count increment on newly added
  mentions. Repo `update` writes `edited_timestamp` and re-resolves mentions.
  Edit path is sound end-to-end.
- `useEditStore` has unit tests for start/stop/replace.
- `isEditing = editingMessage && editingMessage.channelId === channelId`
  correctly scopes the edit bar to the right `MessageInput` instance (main
  channel vs ThreadPanel), so opening a thread for a different channel won't
  accidentally inherit edit mode.
- `handlePaste` / `handleDrop` early-return when `isEditing` — prevents
  accidentally attaching images mid-edit. Pairs with the
  `pendingFiles.length > 0 && !isEditing` render guard.
- `useMemo` on `filtered` in both autocompletes uses the right deps
  (`[textChannels, query]` / `[members, query]`). No stale-closure risk.

---

## Verdict

R2 issues are all properly resolved. The remaining items are polish (stale
error display, raw mention rendering in edit, a11y wiring, helper extraction)
and can ship as a follow-up issue against #300. **Ready to merge.**

— 🌠 Nova
