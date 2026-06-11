# PR #322 Review — fix: underscore italic only at word boundaries

**Reviewer:** 🌠 Nova
**Verdict:** ✅ Ready

## Summary
Small, focused fix that adds an optional `guard` hook to the inline rule machinery and uses it to suppress underscore-italic when preceded by a word character. Matches Discord's behavior and resolves the `VIEW_CHANNEL → VIEW<em>CHANNEL</em>` regression in #319. Code is internally consistent, well-tested for the targeted cases, and shouldn't disturb other inline rules.

## Critical Issues
None.

## Product Impact
- Behavior shift is exactly the intended one: `SNAKE_CASE` and similar identifiers now render literal. `_hello_`, `say _hello_ world`, `(_hello_)` style still italicize since their preceding char (start, space, paren) is not `\w`.
- One subtle behavior note worth being aware of (not blocking): the guard uses JS's default `\w`, i.e. `[A-Za-z0-9_]`. That means after consuming `_` itself (e.g. mid `a_b_c_d`), the guard stays suppressed, which is the desired outcome. But it also means non-ASCII word chars (`café_test`, `日本_test`, etc.) won't suppress italic, since `é`/`日` aren't `\w`. Probably fine — Discord's own behavior here is inconsistent too — but flagging in case it matters for i18n users.

## Suggestions
1. **`consumed` grows unbounded but is only read at `[length-1]`** (`chat-markdown.ts` `parseInline`). For a long message this allocates an O(n²)-ish string trail just to look at one char. Cheap fix: track only the last consumed char.
   ```ts
   let lastConsumed = "";
   // ...
   if (rule.guard && !rule.guard(lastConsumed)) continue;
   // on match:
   lastConsumed = remaining[length - 1] ?? lastConsumed;
   // on fallback:
   lastConsumed = remaining[0];
   ```
   Functionally equivalent, no allocation pressure on long chat messages.

2. **Guard naming/contract**: the guard receives "the text consumed so far in this `parseInline` scope" but is really used as "preceding char check." A short JSDoc on the `guard?:` field documenting that contract (and that it's scoped to the current `parseInline` recursion, so nested calls reset) would help future rules avoid surprise. Example: if someone later adds another guarded rule expecting global lookbehind, the recursion-reset behavior could bite them.

3. **Test coverage gap (minor)**: consider one positive test for the boundary-after-punctuation case, e.g. `"(_hello_)"` or `"a, _hello_."` — the current tests cover start-of-string and post-space, but not post-punctuation, which is a common chat pattern. Not blocking; the regex/guard logic clearly supports it.

4. **Optional**: a test confirming `__bold__` underscore (if supported elsewhere) or mixed `_VIEW_CHANNEL_` (currently would italicize `VIEW` because at offset 0 consumed is empty) — just to lock in the chosen semantics so future refactors can't silently regress them.

## Positive Notes
- The `guard` hook is a clean extension point — declarative per rule, doesn't bloat the core loop, and stays opt-in (`if (rule.guard && ...)`).
- Tests are explicit about both positive and negative behaviors, with descriptive failure messages including the actual token types — easy debugging when they break later.
- PR is properly atomic: one behavioral change, one mechanism addition, one test file update. Closes the linked issue cleanly.
- Inline comment on the underscore rule explains the *why* (Discord-compatible), not just the *what*.

`~/.openclaw/workspace/code-review/reviews/cove-322-nova.md`
