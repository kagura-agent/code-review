# PR #385 Round 3 Re-review — Stella

**Rating: ⚠️ Needs Changes**

## Summary

The claimed Round 3 fixes are mostly present in code, and the client tests/build pass. However, I do **not** think the edit-leak blocker is fully closed yet, and the behavior-level fixes are still not covered by tests.

## Verification notes

- ✅ **Fake reply Message fixed:** context-menu reply now receives and stores the real `Message` from `MessageList`, instead of constructing a partial/fake object.
- ✅ **File paste/drop while editing remains blocked:** paste/drop handlers return during edit mode, and previews are hidden while editing.
- ✅ **Edit failure feedback added:** failed `api.editMessage` sets `Failed to save edit` in the edit bar and schedules a 3s clear.
- ✅ **Escape handling narrowed:** edit cancellation now checks autocomplete visibility *and* result flags before swallowing Escape.
- ⚠️ **Edit text leak is still not robustly fixed:** on channel change, `MessageInput` still renders once with the old `content` state for the new `channelId`; the cleanup happens in a passive `useEffect` after commit/paint (`MessageInput.tsx:61-69`). That means edited text can still briefly appear in the newly selected channel before the effect clears it. For a privacy/content leak, clearing after paint is too late. This should be prevented synchronously, e.g. key/remount the input by `channelId`, use a layout-effect reset before paint, or keep drafts/edit content keyed by channel so a different channel never renders the old value.

## Issues

### 1. Edit content can still flash in another channel before the passive effect clears it

`MessageInput` retains local `content` across prop changes. When `channelId` changes, React commits the new render before the `useEffect` at `MessageInput.tsx:61-69` runs. During that render, `isEditing` is false for the new channel, the edit bar disappears, but the textarea value is still the previous edited message text until the effect sets `content` to `""`.

This is the same class of leak from the earlier rounds, just reduced to a post-commit/post-paint window. Since this was the recurring blocker, I would not mark it fixed without a synchronous/no-paint guarantee and a regression test.

Suggested fixes:
- render `<MessageInput key={activeChannelId} channelId={activeChannelId} />` for channel inputs, or
- move the channel-change reset to `useLayoutEffect`, or
- store input/edit drafts by channel and derive the textarea value from the active channel only.

### 2. Behavior fixes still lack regression tests

The added test file only covers `useEditStore` state transitions. It does not exercise the user-facing behavior changed in this PR/round:

- editing text is cleared before/when switching channels and does not appear in the next channel,
- Escape cancels edit when autocomplete has no actual results,
- Escape is left to autocomplete when autocomplete has actual results,
- edit API failure shows `Failed to save edit` and dismisses it after 3s,
- paste/drop files are ignored while editing.

Given the review rule “Behavior changes need tests,” this still needs component/integration coverage around `MessageInput` and autocomplete state. The edit-leak test should specifically catch the channel-switch regression that survived Round 2.

## Gates run

- `pnpm --filter @cove/client test` ✅ — 3 files / 10 tests passed.
- `pnpm --filter @cove/client build` ✅ — production build succeeded.
- `pnpm --filter @cove/client lint` ❌ — fails on existing-looking `MessageList.tsx` React compiler/ref errors plus warnings; not obviously introduced by this PR, but the gate is not green.

## Final recommendation

⚠️ **Needs Changes** — fix the channel-switch edit leak without a paint window and add behavior-level regression tests for the Round 3 fixes before merge.
