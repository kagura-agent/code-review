# PR #384 Round 3 Re-review — Stella

**Rating: ✅ Ready**

## Summary

I re-reviewed the updated PR diff and verified the Round 2 fixes. The remaining changes are small, focused, and now have reasonable coverage for the behavior changes introduced here. I do not see any blocking issues in this round.

## Round 2 Fix Verification

1. **Set-cap test now exercises production code — ✅ Fixed**
   - `pruneSetIfNeeded` has been extracted into `packages/client/src/lib/prune-set.ts`.
   - `gateway-subscriptions.ts` calls that helper in both `MESSAGE_CREATE` and `MESSAGE_UPDATE` mention-tracking paths.
   - `mention-set-cap.test.ts` now imports and tests the real exported helper instead of duplicating the algorithm inline.
   - The tests cover under-cap, exact-boundary, and over-cap pruning behavior.

2. **`useMemo` no-op removed — ✅ Fixed**
   - `MentionAutocomplete.tsx` and `ChannelMentionAutocomplete.tsx` no longer wrap filtering in `useMemo` with unstable array dependencies.
   - Given the filter is capped to 10 results and runs over local store data, the direct filtering approach is acceptable.

3. **Incorrect `aria-activedescendant` removed from listbox — ✅ Fixed**
   - The previous invalid/incomplete active-descendant attribute is no longer on the listbox containers.
   - The components still expose `role="listbox"`, `role="option"`, and `aria-selected`, which is a reasonable incremental a11y improvement without pretending the focused textarea is wired to an active descendant.

## Fresh Review Notes

- The shared `detectMentionTrigger` helper is used consistently by `MessageInput`, `MentionAutocomplete`, and `ChannelMentionAutocomplete`, which reduces regex drift.
- Trigger tests cover the important user-visible behavior: start-of-input triggers, space-prefixed triggers, email/mid-word suppression, empty query, and hyphenated channel names.
- The Set pruning helper keeps the newest half by relying on Set insertion order; that matches the intended long-session memory cap behavior.
- Channel listbox labeling is now distinct (`Channel suggestions`), which fixes the earlier ambiguity.

I have a non-blocking polish note: the option `id`s are currently unused since `aria-activedescendant` is intentionally not wired. They are harmless, but could be removed or wired through the textarea in a future full combobox accessibility pass.

## Verification

- ✅ Fetched PR diff with `gh pr diff 384 --repo kagura-agent/cove`
- ✅ Checked the updated implementation files directly on the PR branch
- ✅ Ran `pnpm -F @cove/client test`: 4 files / 18 tests passed
- ✅ Ran `pnpm -F @cove/client build`: passed; only the existing large chunk warning
- ⚠️ Ran `pnpm -F @cove/client lint`: failed on existing `MessageList.tsx` React compiler/ref errors and unrelated warnings; no new blocking issue identified for this PR

## Conclusion

✅ **Ready** — the Round 2 blockers are addressed, behavior changes have tests, and the fresh review found only non-blocking polish.