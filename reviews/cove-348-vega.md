**Summary**
This PR adds comprehensive support for `global_name`, bringing Cove's display logic closer to Discord's model. It covers the backend schema updates, client-side rendering fallbacks (`nick > global_name > username`), state management, and the settings UI. The end-to-end data flow from the database to the client UI is generally very solid.

**Critical Issues**
1. **OAuth Overwriting Cleared Names (`auth.ts` lines 85-86)**:
   In the OAuth callback for existing users, the query runs: `UPDATE users SET ... global_name = COALESCE(global_name, ?)`.
   If a user explicitly clears their Display Name in Settings (which saves it as `null` in the DB), the `COALESCE` function will evaluate `COALESCE(null, googleUser.given_name)` and overwrite their `null` value back to their Google given name upon their next login. This completely reverts their choice to clear the field.
   *Fix*: Remove `global_name = COALESCE(global_name, ?)` from the `UPDATE` query. The display name should only be pre-filled during initial registration (which is already handled correctly in the `pending_registrations` INSERT).

2. **Null Validation Risk (`agents.ts` lines 85-86)**:
   In `PATCH /users/@me`, you added: `const gnErr = validateString(body.global_name, "global_name", { maxLength: 80 });`
   Since the client explicitly sends `{ global_name: null }` when the user clears the name, if `validateString` does not explicitly permit `null`, users will get a validation error (HTTP 400) and be unable to clear their display name.
   *Fix*: Ensure `validateString` allows `null`, or guard it: `if (body.global_name !== null) { ... validateString ... }`.

**Product Impact**
- **Expected Behavior**: Users will start seeing their Google `given_name` by default, overriding the raw `username` which improves the cozy/human feel of the app.
- **Risk**: If the OAuth bug above isn't fixed, users will be confused when their cleared display names magically revert after their session expires and they log back in.

**Suggestions**
1. **Missing Tests**: No automated tests were added for the new `global_name` update logic in `PATCH /users/@me` or the `users.update` repository method. Consider adding a quick route test to verify that `null` is handled correctly.
2. **MentionAutocomplete.tsx**: Setting `slice(0, 10)` after filtering is efficient enough for small lists, but calculating `.toLowerCase()` twice per member in the `.filter` loop could be slightly optimized. This is completely fine for an MVP, though.

**Positive Notes**
- Excellent and consistent fallback chain (`member.nick || user.global_name || user.username`) across `MemberList`, `MessageItem`, `UserBar`, and `MentionAutocomplete`.
- The database migrations are clean, correctly increment the `user_version` to 13, and properly cover both `users` and `pending_registrations` tables.
- The UX in the Settings panel is great—dirty state tracking (`hasChanged`) and positive visual feedback (`✓ Saved`) make it feel polished.

Rate: ⚠️ Needs Changes