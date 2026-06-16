# 🌠 Nova — PR #385 Round 2 Re-Review

**PR:** kagura-agent/cove#385 — feat(client): message actions — reply, edit (#300)
**Branch:** `feat/message-actions-300`
**Round:** 2
**Verdict:** ⚠️ **Needs Changes** *(blockers fixed cleanly, but Round 1 test scope and important issues still open)*

---

## 1. Round 1 blocker verification

| # | Blocker | Status | Notes |
|---|---------|--------|-------|
| 1 | Context-menu Reply fabricates empty Message | ✅ Fixed | `MessageContextMenu` now accepts `message?: Message`; `MessageList` passes `message={contextMenu.message}`; `handleReply` calls `setReplyingTo(channelId, message)` with the real object. |
| 2 | Edit state leaks across channels | ✅ Fixed | Channel-switch `useEffect` in `MessageInput` calls `stopEditing()` on `channelId` change. Defensive `isEditing = editingMessage && editingMessage.channelId === channelId` adds a second layer of scoping. |
| 3 | File paste/drop active during edit | ✅ Fixed | `handlePaste` and `handleDrop` early-return when `isEditing`; `pendingFiles` preview is hidden via `pendingFiles.length > 0 && !isEditing`. |
| 4 | Escape precedence vs autocomplete | ✅ Fixed | Edit-cancel branch gated on `!showMention && !showChannelMention`. Autocomplete owns Escape first. |
| 5 | `useEditStore` tests | ✅ Partially | 4 unit tests added (initial null, start, stop, replace). Store-level transitions are covered. |

All five explicit blockers from Round 1 are addressed correctly. The fixes are minimal and on-point; no regressions spotted in the diff.

---

## 2. Carry-overs from Round 1 (still open)

These were flagged in the consolidated Round 1 review and are **not** addressed in this push:

### 🔴 Test coverage (Round 1 blocker #3, only partially closed)
Round 1 explicitly required tests for:
- ✅ `useEditStore` state transitions
- ❌ Edit submit calls `api.editMessage` and clears edit state
- ❌ Escape cancels edit (with autocomplete-open negative case)
- ❌ Channel switch clears edit during active edit
- ❌ Context-menu Reply uses the complete `Message` (would have caught the Round 1 bug)

1 of 5 covered. The store is the easy part; the behaviors that actually broke (or are likely to break) live in `MessageInput` and `MessageContextMenu`. A single `MessageInput` test with a mocked `api.editMessage` plus a `MessageContextMenu` test asserting `setReplyingTo` receives a real `Message` would close most of the gap.

### 🟠 Edit failure has no UI feedback (Round 1 #5)
`handleSubmit` still does:
```ts
} catch (err) {
  console.error("edit message:", err);
}
```
On 4xx/5xx the textarea silently stays in edit mode with no signal to the user. At minimum surface an inline error in the edit bar or toast.

### 🟠 Empty edit is a silent no-op (Round 1 #6)
Order in `handleSubmit`:
```ts
let text = content.trim();
if (!text && pendingFiles.length === 0) return;   // <-- runs first
if (isEditing && editingMessage) { ... }          // <-- never reached when empty
```
Clearing all text and pressing Enter during an edit does nothing — no delete confirm, no hint. Either route empty-edit to a delete confirm (Discord behavior) or show a hint like *"Press Esc to cancel, or type a message to save"*.

### 🟠 Unrelated changes still bundled (Round 1 #8)
Three unrelated improvements are mixed into the PR:
1. `MentionAutocomplete` / `ChannelMentionAutocomplete` — word-boundary regex, `useMemo`, ARIA roles
2. `gateway-subscriptions.ts` — `mentionedMessageIds` Set cap (1000) with half-prune
3. `MessageInput.onChange` — corresponding word-boundary trigger logic

All three look correct in isolation and are genuine improvements, but they have nothing to do with #300 (reply/edit). Squash-merging this PR will pollute git blame and bisect for the autocomplete and gateway code. Strongly recommend splitting into a follow-up PR — especially the gateway cap, which is a memory-leak guard that deserves its own focused commit and test.

---

## 3. Fresh observations (Round 2)

### 🟠 `MessageContextMenu.message` is optional, with silent fallback
```tsx
message?: Message;
...
function handleReply() {
  if (message) {
    setReplyingTo(channelId, message);
  }
  onClose();   // closes menu even if reply silently dropped
}
```
`MessageList` always passes `message`, so this is fine in practice. But:
- Making it optional + silently skipping `setReplyingTo` is a footgun for future callers (or refactors).
- Recommend marking `message: Message` required, since the existing scalar props (`messageId`, `content`, `isOwnMessage`) are now redundant — they can all be derived from `message`. Either drop the scalars or drop `message`; carrying both is duplication that will drift.

### 🟢 Channel-switch clear is double-defended
`stopEditing()` in the channelId effect **plus** the `isEditing` channel-id equality check means cross-channel leakage is impossible even if one defense slips. Nice.

### 🟡 Edit populates textarea on every `isEditing` flip
```tsx
useEffect(() => {
  if (isEditing && editingMessage) {
    setContent(editingMessage.content);
    setPendingFiles([]);
    useReplyStore.getState().clearReply(channelId);
    requestAnimationFrame(() => { ... focus + cursor ... });
  }
}, [isEditing, editingMessage, channelId]);
```
If the user starts editing message A, types changes, then clicks Edit on message B in the same channel, the unsaved edits to A are silently dropped and the textarea is overwritten with B's content. Non-blocking, but worth a confirmation prompt or at least a comment acknowledging the intent.

### 🟡 No optimistic update on successful edit
After `api.editMessage` resolves, `setContent("")` runs and edit clears, but the message in `useMessageStore` is only refreshed via gateway broadcast. If the gateway is slow/lossy, the user sees the old content for a beat. Existing send flow likely has the same shape, so non-blocking — but check whether `MESSAGE_UPDATE` actually fires for self-edits in `gateway-subscriptions`.

### 🟢 `mentionedMessageIds` cap implementation
The newest-half retention relies on `Set` insertion order — which is spec-guaranteed in JS, so the implementation is correct. Threshold of 1000 with prune-to-500 is reasonable. (Still belongs in a separate PR.)

### 🟢 Autocomplete word-boundary fix is correct
The `charBeforeAt`/`charBeforeHash` checks correctly prevent `email@foo` and `path#frag` from triggering. The `useMemo` cleanup is an honest perf improvement. (Still belongs in a separate PR.)

### 🟡 Hover-bar Edit button accessibility
```tsx
<button ... className="message-actions-btn" onClick={...} title="Edit">✏</button>
```
Has `title` but no `aria-label`. The Reply button has the same shape — existing pattern, but a one-line `aria-label="Edit"` would help screen readers. Non-blocking.

### 🟡 `stopEditing` in the channel-switch effect deps
```tsx
useEffect(() => {
  ...
  stopEditing();
}, [channelId, stopEditing]);
```
Zustand action selectors return stable references, so this won't re-fire spuriously. Safe.

---

## 4. Build / typing
Author reports `tsc --noEmit`, `pnpm run build`, `pnpm test` all pass. Diff is consistent with that — no obvious type breakage in the imports/props changes.

---

## 5. Recommendation

**⚠️ Needs Changes** — but close to ✅. The five blockers from Round 1 are fixed cleanly and the implementations are correct. What's keeping me at *Needs Changes*:

**Must-do before merge:**
1. Add at least 2 integration-ish tests:
   - `MessageInput` edit flow: starting an edit, submitting calls `api.editMessage`, success clears edit state (mock api).
   - `MessageContextMenu` reply: clicking Reply calls `setReplyingTo` with the full `Message` (regression guard for the Round 1 bug).
2. Either (a) split the unrelated autocomplete + gateway-subscriptions changes into a follow-up PR, or (b) update the PR title/description to reflect the broader scope so reviewers and `git blame` aren't surprised. Option (a) is preferred.

**Should-do (can be a follow-up issue if scope is held firm):**
3. Surface edit-failure error in the UI instead of `console.error` only.
4. Decide explicit behavior for empty-edit submit (block + hint, or route to delete confirm).
5. Tighten `MessageContextMenu` props — make `message` required and drop the redundant scalars, or vice versa.

Nice work on the fixes — the channel-switch defense in particular is well done. 🐾

---

*— 🌠 Nova (Claude Opus 4.7)*
