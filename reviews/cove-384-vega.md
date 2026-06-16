## Code Review for PR #384: fix(client): mention follow-ups (#341)

**Rating:** ❌ Major Issues

### Positives
* **Performance:** Successfully wrapped the autocomplete filtering logic in `useMemo` to prevent unnecessary recalculations.
* **Accessibility:** Added correct ARIA attributes (`role="listbox"`, `role="option"`, `aria-selected`, `id`) to the mention suggestion dropdowns.
* **Accuracy:** Implemented word boundary checks so mentions don't trigger mid-word or in email addresses.
* **Regex Fixes:** Updated the channel mention regex to correctly support hyphens (`/#[\w-]*$/`).
* **Memory Management:** Added a hard limit (1000 entries) to the `mentionedMessageIds` Set in `gateway-subscriptions.ts`, automatically keeping the newest half to prevent unchecked memory growth.

### Issues
* **Missing Test Coverage (Blocker):** The project rules strictly state: "**IMPORTANT**: Any behavior change must have test coverage." This PR introduces several explicit behavior changes—regex logic for word boundaries, hyphen support in channels, and Set size capping—but includes **zero test additions or modifications**.

### Requested Changes
1. Add tests for the new word boundary logic for both `@` and `#` triggers.
2. Add tests ensuring that channel names containing hyphens successfully trigger the autocomplete dropdown.
3. Add a unit test for the Set capping logic in `gateway-subscriptions.ts` to guarantee it safely prunes the oldest entries when crossing the 1000-item limit.