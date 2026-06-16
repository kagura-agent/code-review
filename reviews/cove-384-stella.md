# 🌟 Stella Review — kagura-agent/cove PR #384

## 1. Summary

This PR addresses the mention follow-ups from #341/#339 across mention autocomplete accessibility, trigger boundary handling, memoized filtering, channel-name regex support, and a bounded `mentionedMessageIds` Set.

The implementation is small and mostly aligned with the stated goals, but I would not mark it ready yet because it changes multiple user-visible behaviors without adding or updating tests. I also see one likely behavior mismatch in the trigger boundary logic: the stated requirement says mentions should trigger only after whitespace or start-of-string, but the implementation allows triggers after any non-word punctuation.

**Rating: ⚠️ Needs Changes**

## 2. Critical Issues

### Missing test coverage for behavior changes

The PR changes several behaviors:

- `@` autocomplete trigger suppression in email-like text.
- `#` autocomplete trigger suppression and hyphenated channel-name matching.
- keyboard/a11y semantics for autocomplete options.
- duplicate mention tracking retention via Set pruning.

However, the PR modifies only implementation files and does not add or update any test files. The PR body says tests were run, but there is no regression coverage for the new behavior. Given the explicit review standard that behavior changes require tests, this should be addressed before merge.

Suggested coverage:

- `email@gmail` does not show user mention autocomplete.
- start-of-string and whitespace-prefixed `@alice` still show autocomplete.
- `#cove-dev` triggers channel autocomplete and filters hyphenated channel names.
- non-trigger cases for channel/user mentions.
- `mentionedMessageIds` cap keeps the Set bounded and still prevents duplicate mention increments.

### Trigger boundary logic does not match the stated requirement

The stated context says `@` and `#` should only trigger when preceded by whitespace or start-of-string. The code currently checks only that the previous character is not a word character (`! /\w/.test(charBeforeTrigger)`). That means punctuation-prefixed cases such as `hello.@alice`, `(@alice`, `foo-#cove-dev`, or `/#general` can still open autocomplete.

If punctuation-triggering is intentional, the PR description/context should be clarified and tests should lock that behavior. If not, the condition should be tightened to start-of-string or whitespace, e.g. previous char absent or `/\s/.test(previousChar)`.

## 3. Product Impact

- Positive: users should no longer get mention popups while typing normal email-like strings, and hyphenated channel names become usable in autocomplete.
- Risk: without tests, future refactors can easily regress the exact mention trigger rules again.
- Risk: punctuation-triggered popups may still appear in places users do not expect if the intended rule is truly whitespace/start only.
- Accessibility improves structurally with listbox/option roles and `aria-selected`, though it remains a partial combobox pattern because the textarea is not connected via `aria-controls`/`aria-activedescendant`.

## 4. Suggestions

1. Add regression tests for the mention trigger parser behavior, ideally by extracting the trigger detection into a small pure helper used by `MessageInput`, `MentionAutocomplete`, and `ChannelMentionAutocomplete`. That would also remove the duplicated boundary logic.
2. Decide whether punctuation before `@`/`#` should trigger. My recommendation: match the stated requirement strictly — only start-of-string or whitespace.
3. Consider extracting the Set cap/prune logic into a helper so it can be unit-tested directly and reused in both `MESSAGE_CREATE` and `MESSAGE_UPDATE` paths.
4. For a11y polish, consider connecting the textarea to the active option with `aria-controls` and `aria-activedescendant`, and use a distinct label/id prefix for channel suggestions versus user suggestions.

## 5. Positive Notes

- Good targeted follow-up: the PR directly addresses the review items and keeps the diff compact.
- `useMemo` is applied in the right place for filtered members/channels and keeps render work predictable.
- The Set cap is a sensible defensive fix for long-running sessions.
- Hyphenated channel support fixes a real-world naming pattern and is handled consistently in `MessageInput` and `ChannelMentionAutocomplete`.
