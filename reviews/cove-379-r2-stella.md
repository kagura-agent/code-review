# PR #379 Round 2 Review — Stella

**Rating: ✅ Ready**

## Summary

This PR adds client-side channel mention autocomplete, serializes selected `#channel` entries as `<#channelId>`, parses channel mention tokens, and renders them as clickable channel labels. The Round 1 `#unknown-channel` rendering bug is fixed: `MessageItem` now builds a `mentionChannels` map from the channel store and passes it into both grouped and ungrouped `ChatMarkdown` render paths. I did not find any blocking issues in the updated code.

## Critical Issues

None.

## Verification of Round 1 Fix

- **Map is correctly built and passed:** `MessageItem.tsx:228-237` subscribes to `channelsByGuildId`, builds `Map<channelId, channelName>`, and passes it to `ChatMarkdown` at `MessageItem.tsx:326` and `MessageItem.tsx:403`.
- **Map updates when channels change:** the selector subscribes to the Zustand `channelsByGuildId` object, and the channel store updates that object immutably in `setChannels`, `addChannel`, `updateChannel`, `removeChannel`, and `removeGuildChannels`. The `useMemo` dependency on `channelsByGuildId` should therefore recompute after channel create/rename/delete/guild removal events.
- **Rendering path uses the map:** `ChatMarkdown.tsx:109-110` resolves `<#id>` via `mentionChannels?.get(token.channelId)`, so known channels render as `#name` rather than `#unknown-channel` once the store has that channel.

## Product Impact

Channel mentions should now display correctly for loaded guild channels and update after channel rename/delete events. Unknown or unloaded channel IDs still render as `#unknown-channel`, which is a reasonable fallback.

One remaining UX risk: clicking a rendered channel mention still calls `setActiveChannel(token.channelId)` unconditionally (`ChatMarkdown.tsx:115-116`). If the channel is unknown, deleted, or belongs to a non-active guild, this can leave the active channel pointing somewhere the current `ChatArea` cannot render. This was already noted as non-blocking in Round 1, and I would still treat it as a follow-up rather than a merge blocker.

## Suggestions

1. **Broaden the channel trigger regex for hyphenated names.** `ChannelMentionAutocomplete.tsx:56` and `MessageInput.tsx:90` still use `#(\w*)` / `/#\w*$/`, so typing after a hyphen closes autocomplete. This matters because channel names commonly contain hyphens. Consider allowing the same character set as channel names, e.g. `[#][\w-]*` if channel names remain simple.
2. **Guard channel mention navigation.** Before `setActiveChannel`, check whether the channel ID exists in `channelsByGuildId` and ideally switch guilds when the target is in another loaded guild. Otherwise ignore the click or show a disabled/unknown state.
3. **Consider tests for the core parser/render behavior.** A small parser test for `<#123>` → `channelMention`, plus a rendering/store update test if a UI test harness exists, would make this harder to regress.
4. **Optional:** wrap `filtered` in `useMemo` in `ChannelMentionAutocomplete`; ESLint reports the same hook-dependency warning pattern as the existing user mention autocomplete.

## Positive Notes

- The fix is placed at the right layer: `MessageItem` owns message-specific mention context and now provides both user and channel mention display maps to `ChatMarkdown`.
- The channel map is derived from the central channel store rather than duplicating lookup state, so rename/delete events naturally flow into rendering.
- Build succeeds: `pnpm -F @cove/client build` completed successfully. Client tests also passed (`pnpm -F @cove/client test -- --runInBand`). Lint currently fails on pre-existing `MessageList` React hook rule errors; the new autocomplete only adds a non-blocking warning.