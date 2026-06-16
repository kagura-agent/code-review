# Review: PR #372 — feat(client): Discord-style empty channel welcome screen

## Summary
This PR is a focused frontend improvement that replaces the generic Ant Design empty state with a Discord-style welcome screen for empty message lists. The implementation is small, readable, and should materially improve the perceived polish of new/empty channels by showing the channel name, a “beginning of channel” line, and the topic when available. I did not find any blocking issues; the main risks are minor maintainability/theme consistency concerns around the channel lookup and CSS variables.

## Critical Issues
None blocking.

## Product Impact
- Empty channels now feel intentional instead of placeholder-like, removing the broken/generic wave-empty-state impression.
- Users get useful context immediately: the channel name is repeated prominently and the topic is surfaced if set.
- Existing channels with messages should be unaffected because the new UI only renders when `messages.length === 0`.
- Thread empty states may currently fall back to `# channel` if the active thread is not present in `useChannelStore.channelsByGuildId`; if empty threads are expected to share this welcome treatment, the UI may be less helpful there.

## Suggestions
- Consider avoiding the per-render IIFE over every guild/channel. It is likely fine at current scale, but `MessageList` re-renders for message, pending-status, unread, and scroll-related state changes, so this lookup repeats often. Passing `channel`/`channelName` from `ChatArea`, memoizing the lookup with `useMemo`, or adding a `getChannelById`/indexed selector would make the intent clearer and reduce unnecessary work.
- The new `h1` uses `var(--text-primary)`, but the existing theme tokens appear to define `--text-normal`, `--text-muted`, and `--header-primary`, not `--text-primary`. Because there is no fallback, the declaration can become invalid and rely on inherited color. Prefer `var(--header-primary, var(--text-normal, #f2f3f5))` or a project-standard token.
- The topic is rendered as plain text, while the channel header renders topics through `ChatMarkdown`. If topics may include markdown/links/mentions, consider reusing the same rendering behavior here for consistency.
- If empty thread support matters, look up thread metadata from `useThreadStore.activeThread` or allow the parent component to pass display info into `MessageList`, so the welcome text can show the actual thread name instead of the generic fallback.
- Minor accessibility polish: the heading is useful semantically; consider ensuring the containing region has consistent text alignment (the outer `textAlign: center` conflicts with the inner left-aligned layout) and that long channel names/topics wrap gracefully on narrow screens.

## Positive Notes
- Nice product polish: the new empty state matches the Discord mental model and gives users confidence that the channel is simply empty, not broken.
- The change is well-scoped to one component and gated cleanly behind `messages.length === 0`, minimizing regression risk for normal message rendering.
- Good use of existing store data; no new network requests or async loading paths are introduced.
- Responsive basics are reasonable with bounded width and side padding.

## Rating
✅ Ready
