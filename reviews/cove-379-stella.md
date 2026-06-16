# Review: PR #379 — feat(client): channel mention autocomplete (#377)

## 1. Summary

The PR adds the expected end-to-end client path for `#channel` mentions: autocomplete from `MessageInput`, wire-format conversion to `<#channelId>`, markdown parsing, rendering, and click navigation. The implementation follows the existing `@user` autocomplete structure closely, and the build/test smoke gates pass locally.

Rating: ⚠️ Needs Changes

## 2. Critical Issues

### Channel mentions render as `#unknown-channel` in messages

`ChatMarkdown` now supports a `mentionChannels` map, but `MessageItem` still renders both message bodies as:

- `<ChatMarkdown content={message.content} mentionUsers={mentionUsers} />`

No `mentionChannels` map is constructed or passed. As a result, parsed `<#channelId>` tokens fall back to `unknown-channel`, so sent channel mentions display as `#unknown-channel` instead of the selected channel name.

This appears to be an incomplete integration: `MessageItem.tsx` imports `useChannelStore` and `useMemo`, but neither is used in the final rendering path.

Suggested fix: build a `Map<channelId, channelName>` from the active guild/channel store (or from a server-provided mention payload if one is planned) and pass it to every `ChatMarkdown` instance used for messages.

## 3. Product Impact

- Users can select a channel and the outgoing message can still contain the correct `<#id>` wire format.
- However, recipients will see `#unknown-channel`, which makes the feature feel broken and removes the main value of readable channel mentions.
- Click navigation may still work because the ID is preserved in the token, but the displayed label is incorrect and confusing.

## 4. Suggestions

- Add focused tests for the new behavior:
  - `parseChatMarkdown("<#123>")` returns a `channelMention` token.
  - `ChatMarkdown` renders `<#123>` as `#general` when given a `mentionChannels` map.
  - `MessageInput` converts a selected `#channel-name` into `<#id>` on send.
- Consider guarding channel mention clicks when the ID is not known in the current guild/store. At minimum, avoid navigating to an arbitrary missing channel silently.
- Consider using a trigger regex that supports common Cove channel names while typing, especially hyphenated names. Selection currently works if the user types a prefix before the hyphen, but `#new-` closes the autocomplete because `/ #\w*$/`-style matching does not include `-`.
- If thread mentions are intentionally excluded from autocomplete, that is fine; if not, type `11` filtering should be revisited or documented.

## 5. Positive Notes

- The autocomplete component is small and consistent with the existing `MentionAutocomplete` pattern.
- The markdown parser extension is minimal and safe: `<#id>` is parsed separately from normal text/link handling.
- Keyboard handling mirrors the existing user mention behavior and avoids hijacking Enter/Tab unless results are visible.
- Local verification passed:
  - `pnpm -F @cove/client build` ✅
  - `pnpm -F @cove/client test` ✅
