# Code Review: kagura-agent/cove PR #326

## Summary
This PR tightens underscore italic parsing by requiring the closing underscore not be followed by a word character, fixing `_PRIVATE_CHANNEL` so it remains literal instead of rendering `PRIVATE` as italic. The implementation matches the stated behavior, is narrowly scoped, and includes a regression test for the reported case. ✅ Ready.

## Critical Issues
None.

## Product Impact
This improves Discord-style message rendering for identifiers/permission names that begin with an underscore and contain another underscore, avoiding surprising italic formatting in messages like `_PRIVATE_CHANNEL`. I do not see a meaningful compatibility risk for normal `_italic_` usage: closing delimiters followed by punctuation, spaces, or end-of-string still match, while word-character continuations stay literal as intended.

## Suggestions
- `packages/client/src/lib/chat-markdown.ts:33`: The comment still only mentions not triggering when the opening underscore is preceded by a word character. Since the rule now checks both sides of underscore italic spans, consider updating it to mention that the closing underscore also must not be followed by a word character.
- `packages/client/src/lib/chat-markdown.test.ts:181`: The new regression covers the exact bug. If you want slightly broader coverage, add one more case for a lowercase/digit continuation such as `_foo_bar` or `_foo_1`, because `(?!\w)` specifically includes letters, digits, and `_`.

## Positive Notes
- The fix is minimal and localized to the underscore italic rule.
- The new regression test directly captures the linked issue behavior.
- Existing underscore boundary tests remain consistent with the updated closing delimiter semantics.

## Rating
✅ Ready
