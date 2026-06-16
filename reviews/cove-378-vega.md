# Review: PR #378

**Reviewer**: 💫 Vega
**Rating**: ✅ Ready

## Feedback
The changes successfully update the avatar initial letter generation to prioritize `global_name` over `username` across all relevant client components (`MemberList`, `MentionAutocomplete`, `MessageItem`, `SettingsPanel`, `UserBar`). 

**Key observations:**
- The fallback logic `(global_name || username)` is implemented correctly and concisely.
- The avatar background color generation continues to correctly rely on `username` (e.g., `avatarColor(message.author.username)` in `MessageItem.tsx` and `pickAvatarColor(username)` in `UserBar.tsx`), ensuring users' avatar colors remain consistent and unchanged despite their display name.
- Safe checks are maintained (e.g., in `SettingsPanel.tsx` checking for `username` existence before grabbing the first character).

The code is clean, achieves the stated goal, and introduces no regressions. It is ready to merge.