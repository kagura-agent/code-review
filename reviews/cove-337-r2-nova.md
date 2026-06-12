# 🌠 Nova — Round 2 Re-Review: PR #337

**Repo:** kagura-agent/cove
**PR:** feat: @mention with autocomplete and highlight (closes #332)
**Verdict:** ✅ **Ready** (with non-blocking suggestions carried over from R1)

---

## Summary

All five R1 critical issues are addressed in this round. The fixes are minimal, targeted, and behaviorally correct. No new critical issues surfaced during fresh re-review of the diff. The remaining items are the same non-blocking polish suggestions previously raised; none of them block merge.

---

## R1 Issue Verification

### C1 — Enter swallowed when no matches → ✅ Fixed
`MessageInput.handleKeyDown` now gates the intercept on both `showMention && mentionHasResults.current`:
```ts
if (showMention && mentionHasResults.current) {
  if (e.key === "ArrowDown" || ... || e.key === "Enter") return;
}
```
`MentionAutocomplete` reports result count to the parent via the `onHasResults` callback inside a `useEffect([filtered.length])`. When the filter yields zero results, the popup returns `null` and the ref is set to `false`, so Enter falls through to `handleSubmit()`. Verified: when popup capture-phase listener also early-returns (`if (filtered.length === 0) return`), there is no double-handling path.

Minor timing note (non-blocking): the ref is updated in a post-render effect, so there is theoretically a one-frame window between filter change and ref sync. In practice React batches keystroke state, and the user must release+press a key, so the effect always lands first. Acceptable.

### C2 — `cursorPos` stale on caret moves → ✅ Fixed
`<textarea onSelect={syncCursor} onClick={syncCursor}>` plus the `syncCursor` helper reads `selectionStart` from the DOM. `onSelect` covers arrow keys, Home/End, shift-select, and IME-driven caret motion in modern browsers; `onClick` is a redundant belt-and-suspenders. Correct.

### C3 — Mention resolution leaks non-guild users → ✅ Fixed
`MessagesRepo.resolveMentions` now scopes the lookup to the channel's guild via INNER JOIN:
```sql
SELECT u.id, u.username, u.bot, u.avatar FROM users u
INNER JOIN guild_members gm ON gm.user_id = u.id AND gm.guild_id = ?
WHERE u.id IN (...)
```
Channel→guild lookup is performed first; if the channel is missing, the function bails (defensive). Non-member user IDs in `<@id>` syntax are silently filtered out of `msg.mentions`, which matches Discord semantics.

### C4 — Edited messages don't refresh mentions → ✅ Fixed
`update()` now calls `this.resolveMentions([msg])` before returning. Verified against the diff at line ~239.

### C5 — Unrelated CI workflow change → ✅ Fixed
Not present in the current diff. Reverted as claimed.

---

## Critical Issues

None.

---

## Product Impact

- **Performance:** `list()` issues one batched mention-resolution query per page; `get/create/update` each issue at most one extra query. Negligible overhead.
- **Security:** Guild scoping prevents the cross-guild user-enumeration vector flagged in R1.
- **UX:** Autocomplete dismissal on no-match keeps Enter behavior intuitive; caret-aware reopen works on click and arrow keys.
- **Compat:** `Message.mentions` type tightened from `unknown[]` to `User[]`. This is a strictly more informative type; the only public surface is shared between server and client which are both updated in this PR.

---

## Suggestions (carried over from R1 — still non-blocking)

1. **Variable-cap safety in resolveMentions** — `IN (?,?,...)` could hit SQLite's default 999-param limit for pathological inputs. Slice `idList` to ~500 or process in chunks.
2. **Double parse of mention IDs** — `parseMentionIds` runs once for the collection set and again per message when filling `msg.mentions`. Cache the per-message result in a `Map<Message, string[]>` to halve regex work on long pages.
3. **Mention pill `cursor: pointer` but no `onClick`** — either wire a click handler (jump to profile / open DM) or drop the pointer cursor to avoid affordance lying.
4. **A11y** — give `MentionAutocomplete` `role="listbox"`, each item `role="option"` and `aria-selected`, and link the textarea via `aria-activedescendant` so screen readers narrate the active match.
5. **Regex `\d+` constraint** — both client parser and server `parseMentionIds` assume numeric IDs. If non-numeric IDs ever ship (snowflake variants, UUID fallbacks), broaden to `[\w-]+`.
6. **Escape re-trigger** — pressing Escape sets `showMention=false`, but the next keystroke re-runs `/@\w*$/` on `before` and reopens the popup. Track a "suppressed-at-position" sentinel cleared once the caret leaves the `@` token.
7. **Scroll active item into view** — `ArrowDown` past the visible window doesn't scroll the list. `useEffect(() => listRef.current?.children[activeIndex]?.scrollIntoView({block:"nearest"}))`.
8. **Click-outside dismissal** — add a `mousedown` listener on `document` that closes the popup when the target isn't inside the list or textarea.
9. **Memoize `mentionUsers` Map in MessageItem** — recreated each render; trivial `useMemo` keyed on `message.mentions`.
10. **Tests** — at minimum: (a) `parseMentionIds` round-trip, (b) `resolveMentions` filters out non-guild users, (c) Enter behavior with empty filter, (d) caret sync on click/arrow.

---

## Positive Notes

- Tight, surgical fix-up since R1. Every fix lands where the bug actually was; no drive-by refactors.
- `onHasResults` callback pattern is a clean way to decouple popup state from key-intercept logic without prop-drilling filter internals.
- Guild-scoped JOIN is the right primitive — cleaner than post-filtering in JS.
- Type tightening (`mentions: User[]`) improves downstream ergonomics without breaking call sites in this PR.
- Capture-phase keydown listener in autocomplete correctly composes with the textarea's bubble-phase handler.

**Recommendation:** Merge. File the non-blocking items as follow-up issues so they don't get lost.
