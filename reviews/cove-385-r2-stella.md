# 🌟 Stella Round 2 Re-review — PR #385

**PR:** kagura-agent/cove#385 — feat(client): message actions — reply, edit (#300)  
**Verdict:** ❌ Major Issues

## Summary

The PR addresses some Round 1 feedback, and the client test/build gates pass locally:

- `pnpm -F @cove/client test` — pass, 10 tests
- `pnpm -F @cove/client build` — pass, with existing bundle-size warning

However, one Round 1 blocker is still not fixed, and another fix is only partial. Because this is Round 2 and the author reported all blockers fixed, I would not merge yet.

## Round 1 blocker verification

| Round 1 blocker | Status | Notes |
|---|---:|---|
| Reply uses real `Message` | ✅ Fixed | `MessageList` now passes `contextMenu.message` into `MessageContextMenu`, and `handleReply()` stores that real object instead of constructing an empty-author fake. |
| Edit cross-channel leak | ❌ Not fixed | `MessageInput` stops edit mode on `channelId` change, but it does **not** clear the textarea content. The edited text still remains visible as normal compose text in the destination channel. |
| Edit ignores files | ✅ Mostly fixed | Edit mode clears pending files on entry; paste/drop handlers skip file collection during edit mode; previews are hidden while editing. |
| Escape precedence | ⚠️ Partially fixed | Escape no longer cancels edit while an autocomplete trigger is active, but the implementation keys off `showMention/showChannelMention`, not whether the autocomplete is actually open with results. With `@noresults` / `#no-results`, Escape now does nothing instead of canceling edit. |
| 4 `useEditStore` tests added | ✅ Added, but insufficient | The 4 store tests are present and pass. They do not cover the behavior fixes that were blockers: channel switch, paste/drop in edit mode, or Escape precedence. |

## Blocking issues

### 1. Editing text still leaks into the next channel after navigation

In `MessageInput.tsx`, the channel-change effect calls `stopEditing()` but does not clear or isolate the local `content` state.

Repro from the current code:

1. Start editing message `A` in channel `ch1`.
2. The edit effect copies `A.content` into local `content`.
3. Switch to channel `ch2`.
4. On the next render, `isEditing` is false because the edit store still points at `ch1`, so the edit banner disappears.
5. The textarea still contains `A.content`; the channel-change effect only calls `stopEditing()`, leaving `content` intact.
6. Press Enter / send and the old edit text is posted as a new message in `ch2`.

This is the same user-visible leak from Round 1, so it remains a blocker.

Suggested fix: on channel change, if the active edit belongs to a different channel, clear `content` together with `stopEditing()`, or move to per-channel draft/edit state so edit text cannot become a normal draft in another channel.

### 2. Escape handling is now too broad when autocomplete has no results

The intended fix was: if autocomplete is open, Escape should close autocomplete rather than cancel edit. The current guard checks only `showMention` / `showChannelMention` before the autocomplete result gate.

That creates this behavior:

1. Start editing.
2. Type a mention/channel trigger with no results, e.g. `@zzzz`.
3. No autocomplete list is rendered, but `showMention` remains true.
4. Press Escape.
5. Edit is not canceled, and no autocomplete handles Escape because there are no results/listener.

So Escape gets swallowed into a no-op for no-result mention states. The edit-cancel guard should probably be based on “autocomplete is actually visible/open with results” rather than the raw trigger booleans, or the no-result state should clear the trigger flag.

This also needs a behavior test; it is exactly the kind of precedence regression Round 1 called out.

## Test coverage concern

The added `useEditStore` tests are good, but they only verify simple Zustand state transitions. The PR still lacks tests for the behaviors that were changed in this round:

- channel switch while editing does not expose edit text as a normal draft;
- Escape cancels edit unless an autocomplete list is actually handling Escape;
- paste/drop cannot queue files in edit mode;
- context-menu reply stores the full message object.

Given these were the Round 1 blockers, I think at least the channel-switch and Escape cases need coverage before merge.

## Positive notes

- The context-menu reply path now uses the real message object.
- Own-message gating for edit remains present in both context menu and hover action bar.
- The edit store is small and easy to reason about.
- Local tests and client build pass.

## Final rating

❌ **Major Issues** — previous blocker still reproducible in the current code; needs another revision before merge.
