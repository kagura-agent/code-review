# PR #337 Review — Nova 🌠

**PR:** feat: @mention with autocomplete and highlight (closes #332)
**Repo:** kagura-agent/cove
**Scope:** 7 files, +278/-12

## Verdict: ⚠️ Needs Changes

The implementation is well-structured and the core flow (parse → batch resolve → render pill → highlight) is clean. There are no critical security holes, but several correctness/UX issues should be fixed before merge, plus one unrelated change in this PR that should probably be split out.

---

## 1. Summary

Adds a Discord-compatible `<@userId>` mention syntax end-to-end:
- Server parses mention IDs from content, batch-resolves them via a single `WHERE id IN (?,?,…)` query, and populates `Message.mentions: User[]` on list/getById/create.
- Client adds a `mention` token to the chat-markdown tokenizer, renders it as an accent pill, shows an autocomplete popup on `@`, and highlights messages that mention the current user with a gold left-border tint.

Architecture is sound. Batch resolution avoids N+1, the shared type goes from `unknown[]` → `User[]`, and the tokenizer extension is minimal.

---

## 2. Critical Issues (fix before merge)

### C1. Unrelated workflow change snuck into the PR
`.github/workflows/notify-issue-close.yml` adds a `sleep 120` step. This has nothing to do with @mentions and shouldn't be in this PR — split it out so reviewers can evaluate it on its own (and so it doesn't get reverted along with a mention rollback).

### C2. `Tab` while autocomplete is open also submits the form / breaks focus flow correctly?
In `MessageInput.handleKeyDown`, `Tab` is bailed out early (`return`) only when `showMention` is true. Good. But the `MentionAutocomplete` keydown listener uses `e.preventDefault()` only when `filtered.length > 0`. If the user types `@xyz` and `xyz` matches nothing, `showMention` stays `true` (regex `/@\w*$/` still matches), the popup component returns `null` early, **no keydown listener is attached**, and Tab/Enter then fall through `MessageInput`'s early-returns and do nothing useful — Enter won't send the message, Tab won't move focus. Users will think the input is frozen.

Fix: only set `showMention=true` when the filtered list is non-empty, OR let `MessageInput` only intercept keys when the popup is actually rendered (pass `hasResults` back up, or guard on `query !== null && filtered.length > 0`).

### C3. Autocomplete `useEffect` cleanup missing in one branch
```ts
useEffect(() => {
  if (filtered.length > 0) {
    window.addEventListener("keydown", handleKeyDown, true);
    return () => window.removeEventListener("keydown", handleKeyDown, true);
  }
}, [filtered.length, handleKeyDown]);
```
The dep array includes `handleKeyDown`, which is recreated whenever `filtered`, `activeIndex`, `atStart`, or `cursorPos` changes — i.e. on every keystroke and arrow press. The listener is re-bound on every change. Functionally OK, but `filtered` is a **new array on every render** (not memoized), so `filtered.length` may be stable but `handleKeyDown`'s identity churns constantly. Wrap `filtered` in `useMemo` and the deps will settle.

### C4. `cursorPos` is updated on `onChange`, not on caret moves
Clicking inside the textarea or using arrow keys to move the caret does not update `cursorPos`. If the user types `@a`, arrows left past the `@`, then types again, `cursorPos` is stale, and `atStart`/`endPos` will be wrong → `handleMentionSelect` will replace the wrong slice of text. Add `onSelect`/`onKeyUp`/`onClick` handlers on the textarea that sync `cursorPos = e.currentTarget.selectionStart`.

### C5. Mention regex tokenizer is too narrow / inconsistent with server
- Client tokenizer: `/^<@(\d+)>/` — digits only.
- Server parser: `/<@(\d+)>/g` — digits only.
- Autocomplete inserts `<@${userId}> ` where `userId` comes from `member.user.id`.

If user IDs are ever non-numeric (UUIDs, snowflakes with letters, KSUIDs, etc.), mentions will silently fail to render/resolve. Check what `User.id` actually is in this codebase — if it can contain non-digits, both regexes should be `[A-Za-z0-9_-]+` (or similar). At minimum, add a code comment asserting "User IDs are numeric strings."

---

## 3. Product Impact

- **New UX surface:** `@` now triggers a popup. Existing messages containing a literal `@word` are unaffected (popup is input-only), but any historical message that happened to contain `<@123>` literal text will now be re-rendered as a pill / "Unknown User" if the ID doesn't resolve. Low risk but worth a thought.
- **Self-mention highlight:** gold tint + left border applies to both grouped and ungrouped message rows — consistent. Good.
- **Performance:** mention resolution runs an extra `SELECT` per call to list/getById/create even when there are zero mentions. The early `if (allIds.size === 0) return;` short-circuits the SQL, ✅.
- **Notification?** This PR resolves mentions for display but doesn't appear to do anything about notifications/unreads-on-mention. If users expect "@me pings me," that's a follow-up.

---

## 4. Suggestions (non-blocking)

### S1. `parseMentionIds` is called twice per message in `resolveMentions`
Once into `allIds`, then again per-message to preserve order. Cache it:
```ts
const perMsg = messages.map(m => parseMentionIds(m.content));
const allIds = new Set(perMsg.flat());
// ...
messages.forEach((m, i) => { m.mentions = perMsg[i].map(id => userMap.get(id)).filter(...); });
```
Saves a regex pass per message.

### S2. Mention pill `cursor: "pointer"` but no `onClick`
`mentionStyle` sets `cursor: "pointer"`, suggesting clickability, but the pill does nothing. Either remove `cursor: pointer` until a profile-open handler exists, or wire one up.

### S3. Accessibility on the autocomplete popup
The popup is a plain `<div>` with no ARIA. For screen reader users this is invisible. Add:
- `role="listbox"` on the container, `role="option"` + `aria-selected` on each item
- `aria-activedescendant` on the textarea (or `aria-controls`)
- An accessible name (e.g., `aria-label="Mention suggestions"`)

### S4. `MentionAutocomplete` ignores `getMembers` reactivity properly?
`const members = activeGuildId ? getMembers(activeGuildId) : [];` — make sure `getMembers` is a stable selector that triggers re-render when the member list changes; if it's just a method call returning a fresh array each render, fine but worth a sanity check.

### S5. `MessageItem`'s `mentionUsers` map and `isMentioned` are recomputed on every render
Wrap in `useMemo` keyed on `message.mentions`. Minor, but `MessageItem` renders a lot.

### S6. Server `User.discriminator: "0"` / `global_name: null` hardcoded
The repo's user row doesn't carry these, so they're stubbed. Fine for now, but if other code paths set real values, mention resolution will be inconsistent with the rest of the API. Worth a TODO.

### S7. No tests
Both `parseMentionIds` (regex, dedup, order) and the chat-markdown tokenizer extension (`<@123>` mixed with `**bold**`, inside blockquotes, etc.) are perfect unit-test material. Worth adding a couple of cases — at least confirm mentions tokenize correctly inside `**<@123>**` and don't break code-block escaping.

### S8. Click-outside dismissal
`MentionAutocomplete` only closes via Escape or selection. Clicking elsewhere in the page leaves it open until the next keystroke removes the `@`. Consider an outside-click handler.

### S9. Scroll active item into view
Long member lists (`maxHeight: 200`) with keyboard nav don't `scrollIntoView` the active item. After `setActiveIndex`, scroll the active row into view inside `listRef`.

### S10. `useMessageStore` cache invalidation?
After receiving new messages (websocket?), I assume the existing store re-renders. Worth verifying the gold-highlight updates live when someone @-mentions you in real time, not only after a refetch.

---

## 5. Security Notes

- **XSS via mention rendering:** Username is rendered as React text (`@{username}`), so React escapes it. ✅ No XSS.
- **SQL injection:** Uses parameterized `?` placeholders with `idList.map(() => "?")`. ✅ Safe.
- **ReDoS:** `/<@(\d+)>/g` and `/@(\w*)$/` are linear; no catastrophic backtracking. ✅
- **Mention spoofing:** Any user can type `<@otherUserId>` and ping anyone. This is by design (Discord works the same way), but if there's an allowlist/permission model (e.g., DM members only), the server currently doesn't enforce it. Worth confirming product intent.
- **No mention-count cap:** A user could put 10,000 `<@id>` in one message; `parseMentionIds` would build a huge `IN (...)` query. SQLite's variable limit (default 999) would reject it. Consider clamping to e.g. 50 mentions per message to fail gracefully.

---

## 6. Positive Notes 🎉

- Batch resolution with a single SQL query — exactly right, no N+1.
- `if (allIds.size === 0) return;` short-circuit is a nice touch.
- Tokenizer extension is minimal and composes with existing inline rules.
- `mentions: unknown[]` → `User[]` is a real type-safety win.
- Discord-compatible storage format (`<@id>`) keeps the door open for future syntaxes (`<#channel>`, `<@&role>`).
- Self-mention highlight is applied consistently across grouped/ungrouped rows.
- `onMouseDown` with `preventDefault` on autocomplete items — correct, avoids blurring the textarea before selection. 👍

---

**Recommendation:** Address C1 (split workflow change), C2 (empty-results trap), C4 (caret sync), and C5 (regex consistency). The rest can land as follow-ups. Nice work overall.
