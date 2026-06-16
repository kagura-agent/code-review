# 🌟 Stella Review — PR #372 Round 2

**PR:** kagura-agent/cove#372 — feat(client): Discord-style empty channel welcome screen (#284)  
**Round:** 2 re-review  
**Verdict:** ✅ **Ready**

## Round 1 Fix Verification

1. **`channelsByGuildId` subscription too broad** — ✅ Addressed.
   - The component no longer subscribes to the whole `channelsByGuildId` object and then derives `currentChannel` during render.
   - The lookup is now inside the `useChannelStore` selector:
     - Zustand will recompute the selector on channel-store updates, but React should only re-render `MessageList` when the selector result changes by strict equality.
     - Unrelated guild/channel updates should keep returning the same current channel object reference, so they should not re-render the message list.
   - This is a meaningful narrowing of the subscription for the hot `MessageList` path. A future indexed `channelsById` map would make lookup cheaper, but the prior re-render concern is fixed.

2. **Unused `Empty` import** — ✅ Addressed.
   - `antd` import is now `import { Spin } from "antd";`.

## Fresh Review

No new blocking issues found. The feature remains small and isolated to the empty-message branch. Existing non-empty message rendering, scroll behavior, unread indicators, and loading state are not touched by this round's diff.

The empty-channel welcome screen renders the channel name and optional topic cleanly, and the topic is guarded so empty/null topics do not leave blank UI. The fallback `channelName = "channel"` is acceptable for a transient not-yet-loaded state, though still a small polish item from Round 1.

## Remaining Non-blocking Notes

- The Round 1 polish items are still mostly unchanged: heading level, hydration fallback, topic markdown/rendering consistency, thread empty states, and i18n. I still consider these non-blocking for this PR.
- The CSS token mismatch also remains: the heading uses `var(--text-primary)`, but the theme appears to define `--header-primary`, `--text-normal`, and `--text-muted`, not `--text-primary`. Because there is no fallback, the declaration may be ignored and rely on inherited color. This is worth cleaning up, but it does not block shipping.
- Empty thread states may still show the generic `# channel` if thread metadata is not available through `useChannelStore`; if Discord-style thread empty states are in scope later, pass display metadata from `ThreadPanel` or read from `useThreadStore`.

## Verification Run

- `pnpm -F @cove/client build` ✅ passed.
- `pnpm -F @cove/client test` ✅ passed: 2 files / 6 tests.
- `pnpm -F @cove/client lint` ⚠️ still fails on existing lint errors in `MessageList.tsx`/`ThreadPanel.tsx`; the previously unused `Empty` import is gone and there are no new lint failures from the added empty-state lines.

## Rating

✅ **Ready** — the two Round 1 blocking issues are fixed, the selector now properly avoids unrelated `MessageList` re-renders, and I found no new blocking regressions.
