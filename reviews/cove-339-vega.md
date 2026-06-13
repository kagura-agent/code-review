# Code Review: PR #339 (feat: @mention with autocomplete and highlight)

**Reviewer:** 💫 Vega  
**Verdict:** ⚠️ Needs Changes

## 1. Summary
This PR successfully implements a full-stack `@mention` feature. It introduces a slick client-side autocomplete, custom markdown rendering for mention chips, server-side resolution scoping, and channel unread badge counts. It also smartly handles mentions introduced during message edits (draft streaming) and protects against global user info leakage by scoping DB resolution to guild members. However, there are significant bugs in the client-side input handling that need to be addressed before merging.

## 2. Critical Issues
* **Input Data Corruption via `replaceAll`:** 
  In `MessageInput.tsx`, display mentions are converted to wire format upon submission using a global string replacement: `.replaceAll(\`@${username}\`, \`<@${userId}>\`)`. 
  1. **No word boundaries:** If you mention `@Alice` and later legitimately type an email like `contact@Alice.com`, it will corrupt the output into `contact<@123>.com`.
  2. **Leaky Map State:** `mentionMapRef` is not cleared when a user deletes text. If a user selects `@Alice`, deletes the mention entirely, and then types `@Alice` inside a markdown code block, it will still incorrectly replace it with `<@123>` on submit.
  *Fix:* Use word boundaries in a regex replacement (e.g., `(?<=\s|^)@username(?=\s|$)`), or better yet, maintain a structured token list or rely on exact offset replacements at the time of insertion rather than sweeping the whole string on submit.
* **Global Key Interception / Dangling Autocomplete:**
  `MessageInput.tsx` lacks an `onBlur` handler to close the autocomplete. Since `MentionAutocomplete.tsx` attaches a capturing global keydown listener (`window.addEventListener("keydown", handleKeyDown, true)`), if a user types `@`, then clicks away to another part of the app, the autocomplete stays open indefinitely. It will silently steal `Enter`, `Tab`, and `Arrow` keys globally, breaking application navigation.
  *Fix:* Add `onBlur={() => setShowMention(false)}` to the `<textarea>`. Because `MentionAutocomplete` correctly uses `onMouseDown` with `e.preventDefault()`, adding `onBlur` will not break mouse selections.

## 3. Product Impact
* **Client-Side Memory Leak:** In `gateway-subscriptions.ts`, `mentionedMessageIds` is a `Set<string>` that grows indefinitely to track deduplication for `MESSAGE_UPDATE` events. For long-running tabs with high message volume, this is a memory leak.
* **Username Character Limitation:** The autocomplete trigger regex `/@(\w*)$/` only supports alphanumeric characters and underscores. If user display names or usernames can contain periods or hyphens, they won't trigger the autocomplete.

## 4. Suggestions
* **SQLite Variable Limits:** In `MessagesRepo.ts -> resolveMentions`, `u.id IN (?, ?, ...)` is used to bulk-resolve users. SQLite has a maximum parameter limit (typically 32,766 in modern versions). While highly unlikely to hit this cap with mentions, chunking the ID list would guarantee safety.
* **a11y:** The `MentionAutocomplete` popup lacks `aria-live` or `role="listbox"` properties, making it opaque to screen readers navigating the results.

## 5. Positive Notes
* Sorting `mentionMapRef` keys by length descending to prevent substring collisions (e.g., replacing `@AliceBob` before `@Alice`) is a brilliant and safe detail.
* Database migration for `mention_count` is written safely and correctly integrated with the `ON CONFLICT` logic in `readStates.set`.
* Server-side `resolveMentions` properly enforces `guild_id` scoping. Excellent security practice.
