# Consolidated Review: PR #322 — fix: underscore italic at word boundaries

**Reviewers:** 🌟 Stella ⚠️ | 🌠 Nova ✅ | 💫 Vega ⏱️ failed

---

## Divergence on closing delimiter

### Stella (⚠️): Closing underscore also needs boundary check
- `_PRIVATE_CHANNEL` → `PRIVATE` becomes italic, `CHANNEL` left as text
- `_hello_world` → `hello` becomes italic, `world` left as text
- Same class of bug as `VIEW_CHANNEL` — internal underscores treated as formatting

### Nova (✅): Fix is sufficient for the targeted case
- The guard correctly prevents `VIEW_CHANNEL` from italicizing
- `_hello_`, `say _hello_ world`, `(_hello_)` all work correctly
- Discord's own behavior is inconsistent with non-ASCII chars too

**Assessment:** Stella's examples are valid edge cases, but the PR correctly fixes the reported issue (#319: `VIEW_CHANNEL` rendering). The closing-delimiter question is a deeper markdown parser issue. The PR description says "underscore italic only at word boundaries" which implies both boundaries, but the fix only guards the opening. Whether this blocks depends on the intended scope.

---

## Suggestions (non-blocking)

1. **`consumed` grows O(n²)** — only last char is ever read; track `lastConsumed` instead (Nova)
2. **Test file excluded from Vitest** — `chat-markdown.test.ts` excluded in vite.config.ts, only runs via `tsx` directly (Stella)
3. **Add post-punctuation test** — `(_hello_)` or `a, _hello_.` (Nova)
4. **Add JSDoc on `guard` contract** — documents it's preceding-char check, scoped to current parseInline recursion (Nova)

---

## Positive Notes (consensus)

- `guard` hook is a clean extension point — declarative, opt-in, doesn't bloat core loop
- Tests cover primary regression cases: `_hello_`, `VIEW_CHANNEL`, multiple mid-word underscores
- Properly atomic: one behavioral change, one mechanism, one test file
- Fixes the reported issue cleanly

---

## Overall Verdict: ✅ Ready (with caveat)

Nova approves. Stella's closing-delimiter concern is valid but represents a deeper parser issue beyond the scope of this bug fix. The PR correctly fixes `VIEW_CHANNEL` (#319). Recommend merging as-is and filing a follow-up for full word-boundary checking on both delimiters if needed.
