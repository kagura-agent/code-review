# 🌠 Nova Review — cove PR #378

**PR:** fix(client): avatar letter uses global_name instead of username (#373)
**Scope:** 5 files, +6/-6
**Verdict:** ✅ Ready

---

## 1. Summary

Surgical fix that swaps the avatar initial letter from `username` to `global_name || username` across all five affected client components, exactly matching the diagnosis and fix prescription in issue #373. `pickAvatarColor` deliberately remains on `username` so a user's avatar background stays stable when they change their display name — only the letter follows the display name. The diff is the smallest possible expression of the fix; no incidental refactors, no scope creep.

## 2. Critical Issues

None. The change is correct in every site:

- `MessageItem.tsx` — `message.author.global_name || message.author.username`, color still keyed on `username`. ✓
- `UserBar.tsx` — `global_name` was already destructured from `useUserStore()` (used for `displayName` on the next line), so no extra plumbing needed. ✓
- `MemberList.tsx` — uses `user.global_name || user.username` consistent with how the row's display name is rendered elsewhere. ✓
- `MentionAutocomplete.tsx` — letter now matches the `<span>` next to it which already used `global_name || username`. Resolves a visible inconsistency where the avatar letter and the visible name could disagree. ✓
- `SettingsPanel.tsx` — adds `global_name` to the destructure from `useUserStore()` and applies the same fallback. The guard `username ? ... : "?"` is preserved, so the empty-store case still falls back to `"?"`. ✓

Falsy semantics check: when `global_name` is `null`, `undefined`, or `""`, the `||` falls through to `username` — which is the desired behavior (the issue calls out users with no display name set). ✓

## 3. Product Impact

- **User-facing:** Closes the actual UX bug from #373 — display name "Luna" with username "yueying" now shows "L" everywhere instead of "Y". Avatar color stays the same across the rename, so users won't experience a visual identity shift.
- **Risk surface:** Read-only string access on already-rendered fields; no new network calls, no store shape changes, no migration. Reverting is a 6-line revert if anything goes sideways.
- **Coverage:** All five sites flagged in the issue are addressed. A quick mental grep for other `username.charAt(0)` / `username[0]` patterns in client components is worth a 30-second confirmation, but the issue's audit looked exhaustive.

## 4. Suggestions (non-blocking)

1. **Tiny consistency nit:** `SettingsPanel` uses `(global_name || username)[0]` while the other four sites use `.charAt(0)`. Pre-existing inconsistency, not introduced by this PR — leave it or align in a follow-up.
2. **Future DRY opportunity:** The `(global_name || username)` pattern now appears alongside `pickAvatarColor(username)` and `displayName` derivations in many components. A shared `getInitial(user)` / `getDisplayName(user)` helper in `lib/avatar-palette.ts` (or a new `lib/user-display.ts`) would prevent the next site from drifting again. Out of scope for this fix.
3. **Test gap (not a blocker):** PR description confirms 376 tests pass, but I don't see a new test pinning the `global_name` precedence. A 3-line snapshot/unit test on `MessageItem` with a user where `global_name !== username` would lock the contract. Optional given the change is mechanical.
4. **Whitespace edge case:** If `global_name` is set to `"   "` (whitespace), `.charAt(0)` renders a blank avatar. Vanishingly rare and not regression-introduced — flagging only for awareness.

## 5. Positive Notes

- 🎯 Minimal, focused, exactly five lines of behavior change for five sites — textbook bug fix.
- 🎨 Correctly preserves `pickAvatarColor(username)` so avatar identity is stable across rename. This is the subtle right call and the PR description explicitly highlights it.
- 🧪 Build, typecheck, and full test suite all green.
- 📋 PR description includes a clear manual test plan with concrete expected values (`L` not `Y`).
- 🔗 Properly closes the linked issue and the diff matches the issue's prescription line-for-line.

---

**Recommendation:** ✅ Ready to merge. Optional polish (shared helper, dedicated test) belongs in a follow-up.
