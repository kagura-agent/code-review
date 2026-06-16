# Review: PR #378 — fix(client): avatar letter uses global_name instead of username (#373)

## 1. Summary
This PR consistently updates fallback avatar initials to use the same display-name source already shown in the UI: `global_name || username`. It covers the expected avatar surfaces: message authors, member list, mention autocomplete, settings panel, and user bar. Avatar background color remains based on `username`, preserving stable colors when users edit their display name.

## 2. Critical Issues
None found. The change is small, localized, and follows the existing null/empty fallback pattern already used for display labels and mention search.

## 3. Product Impact
Positive: users with a global display name will now see avatar initials that match their visible name, reducing the mismatch where a profile shows one name but an unrelated username initial. Keeping colors tied to `username` avoids visual churn when display names change.

Risk appears low. If `global_name` is empty or null, behavior falls back to the previous username initial.

## 4. Suggestions
- Optional: consider extracting a small helper such as `getAvatarInitial(user)` / `displayNameForUser(user)` later, since this expression now appears in several places and could drift again.
- Optional: if the app wants initials to match the member-list label exactly, `MemberList` could eventually consider `member.nick` before `global_name`; that is outside this PR's stated scope and not a blocker.

## 5. Positive Notes
- Nice consistency pass across all visible avatar locations.
- Good call preserving username-based avatar color stability while changing only the displayed letter.
- The implementation is minimal and easy to verify.

## Rating
✅ Ready
