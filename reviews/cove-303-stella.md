# Review: kagura-agent/cove PR #303 (Round 2) — Stella

## Summary
This PR restructures the app shell from a shared 2-row grid into independent flex columns so the sidebar `UserBar` no longer stretches when the chat input grows. The claimed Round 2 fixes are mostly addressed: the mobile double-fixed sidebar positioning is removed, the PR description now matches the current approach, and the `--footer-height` change is explained. I found no functional blockers in the current diff, and the client build passes. One Round 1 cleanup item remains: stale grid-specific mobile CSS is still present even though `.app-layout` is now flex.

**Rating: ✅ Ready**

## Critical Issues
None.

## Previous Round Findings Check
- ✅ **Mobile `.sidebar-panel` double-fixed positioning**: Addressed. On mobile, `.sidebar-panel` is now static and the fixed slide-in behavior moved to `.sidebar-column` (`packages/client/src/index.css:483-507`). This avoids competing fixed/transform rules between the panel and footer.
- ✅ **PR description stale**: Addressed. The description now accurately says the layout was changed to Discord-style flex columns and notes the mobile CSS update.
- ⚠️ **Dead grid CSS rule**: Still present. `packages/client/src/index.css:479-482` still says “Grid collapses to single column” and sets `grid-template-columns` on `.app-layout`, but `.app-layout` is now `display: flex` (`packages/client/src/App.tsx:53`). Escalated from Round 1 because it was left unaddressed, but it is maintainability-only and not a merge blocker.
- ✅ **`--footer-height` 52→54 unexplained**: Addressed in the PR description with the MessageInput height calculation. The value also matches the current textarea minimum height + vertical margins + border (`packages/client/src/index.css:11`, `packages/client/src/components/MessageInput.tsx:16-27`).

## Product Impact
The main user-facing behavior should improve: expanding the message input now grows only the chat footer instead of coupling that height to the sidebar footer. Desktop member list layout still works with the flex row, and the mobile sidebar should continue sliding as one unit because `.sidebar-column` owns both the channel list and `UserBar`.

## Suggestions
1. **Remove stale mobile grid CSS** (`packages/client/src/index.css:479-482`). Since `.app-layout` is flex now, this rule is inert and the comment is misleading. Suggested cleanup:
   - remove the `.app-layout { grid-template-columns: 1fr !important; }` block, or
   - replace it with a flex-relevant mobile comment if there is an intended mobile layout rule.

## Positive Notes
- The flex-column split in `App.tsx` is a good fit for the product behavior: sidebar and chat footer heights are now independently managed while keeping the default shared `--footer-height` alignment.
- Moving the mobile slide transform to `.sidebar-column` is cleaner than separately positioning the sidebar body and footer.
- The PR description is now much clearer and explains the otherwise non-obvious `--footer-height` adjustment.
- Verification run: `pnpm -F @cove/client build` passes.