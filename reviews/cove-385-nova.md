# PR #385 Review — feat(client): message actions — reply, edit

**Reviewer:** 🌠 Nova
**Branch:** `feat/message-actions-300` → `main`
**Scope:** 8 files changed, +220/-22 (PR description says 5 files / +156/-1 — actual diff is larger; description is stale).

---

## Verdict

**Request changes.** The feature itself is straightforward and the implementation is mostly clean, but there are correctness bugs in the edit flow, two security/UX concerns around the reply path, and a complete absence of automated tests for any of the new behavior. PR description also undersells the change footprint (8 files, including unrelated mention-autocomplete + read-state refactors that should arguably ship as their own PRs).

---

## 🔴 Blockers

### 1. `MessageContextMenu.handleReply` fabricates a `Message` with empty author info

`MessageContextMenu.tsx` builds a synthetic `Message` to pass to `setReplyingTo`:

```ts
const message: Message = {
  id: messageId,
  channel_id: channelId,
  content,
  author: { id: "", username: "", bot: false, avatar: null, discriminator: "0", global_name: null },
  ...
};
setReplyingTo(channelId, message);
```

`ReplyBar.tsx` reads `replyingTo.author.username` and renders it as the reply target name. The hover-bar Reply button (`MessageItem.tsx` line 85) passes the real `Message`, so this divergence means **two different code paths produce two different ReplyBar UIs** for the same action:

- Hover-bar reply → "Replying to **alice**: hello"
- Context-menu reply → "Replying to **(empty)**: hello"

Even worse, when `handleSubmit` later picks up the reply (`replyMsg.id`), the `referenced_message` attached to the optimistic pending message uses this fake author, so the optimistic reply quote will render with an empty username until the server response reconciles.

**Fix:** Pass the real `Message` through `MessageContextMenu` props (the parent already has it — `MessageList.tsx:721` is constructing the menu from `contextMenu.message`). Either widen the props to accept the full `Message`, or call `onReply(message)` via a callback prop instead of reaching into the reply store from inside the menu.

### 2. Edit submit drops attachments without warning

`handleSubmit` short-circuits into the edit branch with only `text`:

```ts
if (isEditing && editingMessage) {
  try {
    await api.editMessage(editingMessage.channelId, editingMessage.messageId, text);
    stopEditing();
    setContent("");
  } catch (err) { console.error("edit message:", err); }
  return;
}
```

But the early guard above it is `if (!text && pendingFiles.length === 0) return;` — meaning if a user enters edit mode (which clears `pendingFiles` in the effect) and then drags/pastes a new image before submitting, the submit will succeed with **only the text**, silently discarding the pasted/dropped attachments. The user gets no feedback that the file was dropped.

This is compounded by the fact that the drag/drop and paste handlers remain active during edit mode. Either:
- Disable file paste/drop while `isEditing`, or
- Surface a clear "attachments can't be edited" hint and discard on entry, not on submit.

### 3. Edit failure leaves user stranded with no UI feedback

On `api.editMessage` rejection the code only does `console.error("edit message:", err)`. The user remains in edit mode with their text intact (good), but:

- No toast / inline error.
- The original message in the list is unchanged, so the user has no indication anything went wrong unless they have devtools open.

For the reply path the codebase already has `markFailed` semantics on pending messages. Edit needs an equivalent affordance — at minimum a temporary error string rendered in the "Editing message" bar.

### 4. Empty content on edit silently creates an empty message (or 400)

The early guard treats empty-text-with-no-files as a no-op (returns silently). In **edit** mode this is wrong: the user may have intentionally cleared the textarea expecting "submit empty == delete" (Discord semantics) or at least an error. Currently pressing Enter on an empty edit textarea just does nothing — they have to hit Escape and figure out the inconsistency.

Recommend either:
- Block empty submits with a visible "Message cannot be empty — use Delete to remove it" hint, or
- Mirror Discord and prompt for delete confirmation.

Either way, the silent no-op is a UX trap.

---

## 🟡 Important

### 5. Zero test coverage for any of this

The PR description claims `pnpm test` passes — but the test suite contains **no tests covering this PR's behaviors**. Looking at `packages/client/src/lib/`:

```
gateway-dispatcher.test.ts
gateway-subscriptions.test.ts
chat-markdown.test.ts
```

The new `useEditStore`, the edit-mode population effect, the Escape-cancels-edit branch, the `editMessage` API helper, the mentioned-message-id cap (see issue #8), and the context-menu Reply/Edit handlers all ship without unit tests. AGENTS-level policy on this repo (and the task brief: "Any behavior change must have test coverage") explicitly calls for tests.

Minimum I'd expect:
- `useEditStore.test.ts` — start/stop transitions.
- A `MessageInput` test that mounts with an active edit, asserts textarea is populated, that Escape clears edit state, and that submit calls `api.editMessage` (mocked) with the right args.
- `gateway-subscriptions.test.ts` extension covering the 1000-cap behavior (currently zero coverage of that branch).

### 6. `gateway-subscriptions.ts` cap is in two places, duplicated, and uses "newest half" loosely

```ts
if (mentionedMessageIds.size > 1000) {
  const entries = [...mentionedMessageIds];
  mentionedMessageIds.clear();
  for (let i = Math.floor(entries.length / 2); i < entries.length; i++) {
    mentionedMessageIds.add(entries[i]);
  }
}
```

- "Newest half" assumes `Set` insertion-order iteration corresponds to message recency. That holds for the immediate insertion path, but **`MESSAGE_CREATE` and `MESSAGE_CREATE_BULK` paths both write**, and across reconnections/replays the order may not be strictly recency-ordered (e.g. bulk replay of older messages after a stream resume).
- The cap logic is **duplicated** in two listeners — extract to a helper `recordMention(msg)` to keep both paths in sync.
- Why 1000 + half-eviction rather than a proper LRU? It's fine, but please add a comment explaining the rationale, and consider `Array.prototype.slice(-500)` which is clearer than the half-index loop.

### 7. Unrelated changes piggy-backing on this PR

The PR title says "message actions — reply, edit", but the diff also includes:

- `MentionAutocomplete.tsx` and `ChannelMentionAutocomplete.tsx`: word-boundary fix, `useMemo` wrapping, ARIA `role=listbox`/`role=option` additions. These are good changes! But they're functionally unrelated to reply/edit and should be a separate PR for clean history and easier review/revert.
- `gateway-subscriptions.ts`: mentioned-id cap. Also unrelated.
- `MessageInput.tsx`: the same word-boundary regex change is duplicated here (lines 110-119), which is inconsistent — `MentionAutocomplete` already does this check internally. If `MessageInput` already gates rendering on `setShowMention(false)`, the inner component will still re-check; if the inner check is authoritative, the outer regex copy is unnecessary duplication of policy.

Pick one location for the word-boundary policy. Don't duplicate.

### 8. `useEditStore` is not channel-scoped, but `useReplyStore` is

```ts
editingMessage: { channelId: string; messageId: string; content: string } | null;
```

`useReplyStore` keys by channel (`Record<string, Message | null>`), so each channel maintains its own draft reply state. `useEditStore` is a single global slot. Consequences:

- Start editing in #general → switch to #random → start editing there → switch back to #general → your previous edit-in-progress is gone, replaced by the second channel's edit (or you see the second channel's content in the #general input).
- Worse: `isEditing = editingMessage && editingMessage.channelId === channelId` means the **wrong channel's MessageInput** will show "Editing message" if the user navigates back, because `editingMessage.channelId` still matches if they return.

Most chat clients let users maintain a draft per channel. At minimum, document the intentional global behavior, and `useEffect`-clear `editingMessage` on channel switch if that's the intent. As written this will produce confusing cross-channel state leaks.

### 9. Race: clicking Edit on message A then message B

`startEditing` overwrites with no transition. If A's content is loaded into the textarea, then user clicks Edit on B, the textarea is repopulated with B — but if A's text had unsaved changes (the user typed something), those are silently destroyed. Consider prompting or at least logging that they've discarded an edit-in-progress.

---

## 🟢 Nits / Polish

- **`MessageContextMenu.tsx`**: `id: 'mention-option-' + ch.id` — prefer template literals for consistency with the rest of the codebase.
- **`MessageInput.tsx`**: the "Editing" bar uses inline styles. The codebase already has `MessageInput.css` — these styles belong there for theming consistency.
- **`MessageInput.tsx` line 156**: `if (e.key === "Escape" && isEditing)` is checked before the autocomplete-active gates. That's correct (edit cancel takes priority), but a comment would help future readers understand the ordering.
- **`MessageItem.tsx`**: the pencil button has `title="Edit"` but no `aria-label`. The reply button (line 82-86 from context) has the same issue — accessibility-wise, hover-bar buttons should expose accessible names.
- **`api.editMessage`**: no error type narrowing. The `api<Message>` wrapper presumably throws on non-2xx — confirm 400 (empty content) vs 403 (not author) errors surface cleanly for whatever UI is added per blocker #3.
- **Escape during mention autocomplete + edit**: there's an ordering question — if the mention autocomplete is open while editing, Escape currently closes the autocomplete (handled inside `MentionAutocomplete`) **and** cancels the edit (because `handleKeyDown` returns early before the autocomplete gate sees it). Verify which precedence is intended; my read is the current code cancels the edit even when the user just meant to dismiss the autocomplete. Probably want to gate edit-cancel on `!showMention && !showChannelMention`.
- **Mentioned-set cap**: in addition to the issues in #6, the cap doesn't clear the `setMentioned(msg.channel_id)` read-state side effect — only the Set is pruned. If you re-receive a pruned mention later it'll be re-added and re-marked, which is benign but worth a comment.

---

## Positives

- `useEditStore` is dead-simple and easy to reason about (modulo the channel-scoping issue above).
- Edit-mode entry correctly clears reply state and pending files — good attention to state interactions.
- Autoplacing the cursor at end of content via `requestAnimationFrame` is the right pattern.
- ARIA additions to mention autocompletes are a nice incidental win.
- Word-boundary fix for mention triggers (`@alice` not firing inside `email@alice.com`) is a real bug fix and well-implemented.

---

## Required Before Merge

1. Fix blocker #1 (real `Message` for context-menu reply).
2. Fix blocker #2 (edit + attachments interaction).
3. Add minimum test coverage: `useEditStore`, MessageInput edit submit path, the mentioned-id cap.
4. Either fix #8 (per-channel edit state) or document the global-slot decision in a comment with a TODO.
5. Split the mention-autocomplete and gateway-subscriptions changes into a separate PR, or justify why they belong here.

Once 1–4 land I'd lean toward an approve with the polish items as follow-ups.

— 🌠 Nova
