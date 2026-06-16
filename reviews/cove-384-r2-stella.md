# PR #384 Round 2 Re-review — Stella

**Rating: ⚠️ Needs Changes**

## Summary

Round 1 items are mostly addressed structurally: the trigger logic is now centralized in `detectMentionTrigger`, the autocomplete components both use it, `role="listbox"`/`role="option"`/`aria-selected` were added, and the trigger tests cover the important `email@gmail` / `issue#123` boundary cases. The targeted trigger tests pass locally, and the client builds after building `@cove/shared` first.

However, I still see two issues that should be fixed before merge, mainly around test quality and the accessibility wiring.

## Findings

### 1. Set cap test does not exercise production code

`packages/client/src/lib/mention-set-cap.test.ts` duplicates the pruning algorithm in the test instead of driving `gateway-subscriptions.ts` through `MESSAGE_CREATE` / `MESSAGE_UPDATE` and asserting the actual behavior.

This means the test would still pass if the production cap were removed, changed, or accidentally only applied on one event path. Since the cap is a new behavior change, it needs real coverage against the production subscription flow.

Suggested fix: add/extend a `gateway-subscriptions` test that:

- sets up mocked stores including `setMentioned`
- emits >1000 off-channel messages mentioning `self`
- verifies mention handling still works after pruning
- ideally covers both create-path and update-path cap behavior, or extracts the pruning helper and tests that helper directly while production calls it

### 2. `aria-activedescendant` is attached to an element that does not receive focus

Both autocomplete components now put `aria-activedescendant` on the suggestions `<div>` (`MentionAutocomplete.tsx` and `ChannelMentionAutocomplete.tsx`). But keyboard focus remains on the textarea in `MessageInput.tsx`, and the listbox is not focusable. In that setup, screen readers generally will not get useful active-descendant updates from the non-focused listbox.

Suggested fix: wire the active option to the focused control instead, e.g. make the textarea/combobox carry `aria-controls`, `aria-expanded`, `aria-autocomplete`, and `aria-activedescendant`, or intentionally move/manage focus on the listbox. The current change improves roles, but the specific `aria-activedescendant` fix is incomplete.

## Verification

- ✅ Fetched PR diff with `gh pr diff 384 --repo kagura-agent/cove`
- ✅ Verified shared `detectMentionTrigger` is used by `MessageInput`, `MentionAutocomplete`, and `ChannelMentionAutocomplete`
- ✅ Verified 9 trigger tests exist and cover the requested word-boundary cases
- ✅ Verified one Set-cap test exists, but it is not production coverage
- ✅ Ran targeted client tests: passed (`mention-trigger`, `mention-set-cap`, plus existing lib tests selected by Vitest)
- ✅ Ran `pnpm -F @cove/shared build && pnpm -F @cove/client build`: passed, with only the existing chunk-size warning
- ⚠️ Ran client lint: failed on pre-existing `MessageList.tsx` React compiler/ref errors; also noted a new/related hook warning in `MentionAutocomplete.tsx` about `members` changing `useMemo` dependencies every render

## Notes

The shared trigger helper itself looks reasonable for the intended behavior and the word-boundary cases are much better than the original regexes. I would re-review as Ready once the Set cap is covered through production code and the active-descendant relationship is made accessible from the actually focused element.
