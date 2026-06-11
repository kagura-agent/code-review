# Review: kagura-agent/cove PR #322

## Summary
This PR adds a guard so underscore italics do not open after a word character, which fixes the advertised `VIEW_CHANNEL` case and preserves simple `_hello_` formatting. The implementation is small and the added focused tests pass, but it only checks the opening delimiter boundary; a closing underscore can still be taken from the middle of a word. That leaves Discord-incompatible false italics for leading-underscore / embedded-underscore words, so I would not merge as-is.

**Rating: ⚠️ Needs Changes**

## Critical Issues

1. **Underscore italic still closes on mid-word underscores** — `packages/client/src/lib/chat-markdown.ts:35-41`
   - The new guard checks only the character before the opening `_`. The regex still accepts the first later underscore as the closing delimiter regardless of the following character.
   - Examples with the current PR behavior:
     - `_PRIVATE_CHANNEL` parses `PRIVATE` as italic and leaves `CHANNEL` as text.
     - `say _hello_world ok` parses `hello` as italic and leaves `world ok` as text.
     - `_hello_world_` parses only `hello` as italic and leaves `world_` as text.
   - These are the same class of bug as `VIEW_CHANNEL`: underscores inside a word are being treated as formatting delimiters. For “underscore italic only at word boundaries” / Discord-compatible behavior, the closing delimiter also needs a boundary check, likely by ensuring the character after the matched closing `_` is absent or non-word. If Discord should support underscores inside emphasized text, the matcher also needs to avoid using internal word underscores as the closing delimiter.
   - Please add tests for at least a leading-underscore snake-case token and an emphasized phrase containing an internal underscore, depending on the intended Discord behavior.

## Product Impact
Users will see incorrect italics for identifiers or permission-like names that start with `_` or appear after punctuation/space and contain another underscore. This is less common than `VIEW_CHANNEL`, but it is still a realistic chat/permission/debug-token case and means the PR does not fully close the word-boundary rendering issue.

## Suggestions
- `packages/client/vite.config.ts` excludes `src/lib/chat-markdown.test.ts`, so `pnpm -F @cove/client test -- chat-markdown` does not actually run the modified test file; it ran unrelated gateway tests. The direct command `pnpm exec tsx packages/client/src/lib/chat-markdown.test.ts` does run these tests successfully. Consider either documenting that convention or moving these parser tests into Vitest so future changes are covered by the normal test command.
- Consider replacing the generic `consumed` string guard with delimiter-context checks at match time. That would make it easier to validate both left and right boundaries without relying on parser state alone.

## Positive Notes
- The fix is narrowly scoped to inline underscore italics and does not change unrelated markdown rules.
- Existing adjacent text coalescing still works, and `consumed` is updated for both matched tokens and literal fallback paths.
- The new tests cover the primary regression cases from the PR description: `_hello_`, italics after a space, `VIEW_CHANNEL`, multiple mid-word underscores, and a permission name in a sentence.

## Verification
- `gh pr view 322 --repo kagura-agent/cove --json title,body,state,additions,deletions,files`
- `gh pr diff 322 --repo kagura-agent/cove`
- `pnpm -F @cove/client test -- chat-markdown` — passed, but did not include `chat-markdown.test.ts` because it is excluded in Vite config.
- `pnpm exec tsx packages/client/src/lib/chat-markdown.test.ts` — passed.
