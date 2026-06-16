# 🌠 Nova — Round 2 Re-review: PR #379

**PR:** feat(client): channel mention autocomplete (#377)
**Repo:** kagura-agent/cove
**Round:** 2 (re-review)
**Verdict:** ✅ **Ready** (with minor nits worth knowing about)

---

## Round 1 Bug Verification: `#unknown-channel`

**Status: ✅ Fixed.**

`MessageItem.tsx` now:
1. Imports `useChannelStore` and `useMemo`.
2. Reads `channelsByGuildId` from the store.
3. Builds a flat `Map<channelId, channelName>` across **all** guilds via `useMemo` (deps: `channelsByGuildId`).
4. Passes the map to `ChatMarkdown` via the new `mentionChannels` prop in **both** render branches (reply layout + standard layout).

`ChatMarkdown.tsx` consumes it inside the `channelMention` case (`mentionChannels?.get(token.channelId) ?? "unknown-channel"`). The threading of `mentionChannels` through `renderTokens` for `bold`/`italic`/`strikethrough`/`blockquote`/`spoiler` recursive calls is consistent — no missed branches.

Cross-guild rendering also works because the map flattens every guild's channel list, so a `<#id>` referencing a channel in another joined guild still resolves. The `unknown-channel` fallback now only fires for genuinely unknown IDs (deleted, not joined, stale) — acceptable graceful behavior.

---

## Fresh Review of New Code

### ✅ Looks good

- **Wire format symmetry.** Display `#name` ↔ wire `<#id>` mirrors the `@user` flow exactly. `channelMentionMapRef` is cleared on channel switch and on send, so stale entries can't leak across messages or channels.
- **Word-boundary replacement** uses `(?!\w)` lookahead with the same escape-regex helper — protects against `#general` matching inside `#general-channel` correctly (hyphen is not `\w`, so the boundary holds).
- **Threads filtered** (`c.type !== 11`) for autocomplete suggestions — matches Discord-ish UX.
- **Key-intercept gating** (`channelMentionHasResults.current`) prevents arrow/Tab/Enter hijacking when the popup is showing but empty. Mirrors mention behavior; both gates can coexist without conflict because only one popup is shown at a time per cursor position (different trigger char).
- **`useMemo` deps** on `channelsByGuildId` are correct — store updates trigger rebuild, otherwise stable reference keeps `ChatMarkdown`'s `memo` effective.
- **`onClick` to switch channels** on rendered mention is a nice touch and uses `getState()` instead of subscribing — avoids re-render churn.

### ⚠️ Minor nits (not blocking for personal/small-team)

1. **Hyphenated channel names break the autocomplete trigger.**
   Both `MessageInput` (`/#\w*$/`) and `ChannelMentionAutocomplete` (`/#(\w*)$/`) use `\w*`, which does **not** match `-`. So typing `#gen` shows suggestions, but typing `#general-` immediately closes the popup — yet `general-chat` is exactly the kind of name people will mention. The user has to either keep typing only the prefix before the hyphen or pick from the list early. The display + wire conversion paths handle hyphens fine (escape + `(?!\w)` boundary works), so this is purely a trigger-regex limitation. Suggested fix: `/#([\w-]*)$/` in both places. (Same nit would apply to usernames if they contained hyphens, but channel names in the wild much more frequently do.)

2. **Per-message `mentionChannels` map duplication.**
   Every `MessageItem` builds its own identical map. In a virtualized list of 50+ messages this is 50+ Map allocations on each `channelsByGuildId` change. For personal/small-team scale it's fine, but a cheap win would be to lift the map to a shared selector (e.g., `useChannelStore` selector with `useMemo` at the message list level, or a derived store) and pass down. Not blocking.

3. **`activeIndex` reset effect depends only on `filtered.length`.**
   If the user types and the filtered set changes content but keeps the same length, `activeIndex` may now point at a different channel than what the user was about to confirm. Edge case; tolerable.

4. **`# heading` markdown collision.**
   `/#\w*$/` matches the `#` at line start when followed by word chars without a space (`#Heading`). With a space (`# Heading`) it does not, so the common Markdown heading form is safe. Minor — Discord has the same quirk.

5. **`onSelect` listener re-registration each render.**
   `handleKeyDown` depends on `filtered` (new array reference each render), so the keydown listener is re-attached on every render while the popup is open. Negligible cost, mirrors the user-mention component, fine to leave.

6. **No telemetry/aria.** `role="listbox"` / `aria-activedescendant` aren't set on the popup. Out of scope for this PR but worth tracking.

---

## Summary

The Round 1 regression is genuinely fixed and the fix is the right shape (centralize the lookup at render time, source of truth = `useChannelStore`). New surface area is small, symmetric with the existing user-mention plumbing, and behaves correctly for the common cases including cross-guild references.

Recommend ✅ **Ready to merge**. The hyphen-trigger nit (#1) is the only one I'd actually file as a follow-up — it will bite real users on real channel names. Everything else is quality-of-life.

— 🌠 Nova
