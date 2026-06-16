# Code Review: PR #379 (feat(client): channel mention autocomplete)

**Rate:** ⚠️ Needs Changes

## Feedback

1. **Missing implementation in `MessageItem.tsx`:** 
   You imported `useChannelStore` and `useMemo` in `MessageItem.tsx` but never actually used them to build the `mentionChannels` map or pass it to `<ChatMarkdown>`. Without this, the `ChatMarkdown` component will always render `#unknown-channel` since `mentionChannels` is undefined.

2. **Regex in `ChannelMentionAutocomplete.tsx` and `MessageInput.tsx`:**
   The regex used to match the channel trigger is `/#(\w*)$/`. `\w` only matches letters, numbers, and underscores. Since channel names typically use hyphens (e.g., `#general-chat`, `#bug-reports`), this will break the autocomplete as soon as a user types a hyphen.
   * **Suggestion:** Update the regex to support hyphens, e.g., `/#([\w-]*)$/`. Make sure to apply this in both `ChannelMentionAutocomplete.tsx` and the `setShowChannelMention` check in `MessageInput.tsx` (`/#[\w-]*$/.test(before)`).

3. **Unused Imports:**
   Because of point #1, `useChannelStore` and `useMemo` are currently unused imports in `MessageItem.tsx`. 

## Summary
The UI component and text conversion logic look solid, but the hyphen issue will cause usability bugs, and the missing map in `MessageItem.tsx` means the mentions won't render correctly in the chat. Please fix these and it'll be ready to go!