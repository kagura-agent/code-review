# Review: PR #372 - feat(client): Discord-style empty channel welcome screen

## 1. Summary
This PR replaces the generic, centered empty message state in `MessageList` with a left-aligned, Discord-style welcome screen. The new UI pulls the channel's name and topic from the store, rendering a large `# channel-name` header and an introductory message, providing a much more contextual and polished first-time user experience in empty channels.

## 2. Critical Issues
* **Performance / Re-render Issue:** The way `currentChannel` is derived inside the `MessageList` component is problematic. 
  ```typescript
  const channelsByGuildId = useChannelStore((s) => s.channelsByGuildId);
  const currentChannel = (() => { ... })();
  ```
  By subscribing to the entire `channelsByGuildId` object without a precise selector, the `MessageList` component will re-render anytime *any* channel in *any* guild is created, updated, or deleted. Since `MessageList` is a core, high-frequency component, this breaks memoization. You should move the search logic into a memoized selector inside `useChannelStore`.

## 3. Product Impact
* **User Experience:** Significantly improves the look and feel of new or empty channels. The UI now looks deliberate and familiar (Discord-like) rather than a placeholder with a broken wave emoji. 
* **Contextual Clarity:** Users immediately know which channel they are in and what its topic is, reducing confusion.

## 4. Suggestions
* **Extract Selector:** Change the store subscription to something like: `const currentChannel = useChannelStore(useCallback((s) => findChannelById(s.channelsByGuildId, channelId), [channelId]));` to avoid unnecessary re-renders.
* **Styling Consistency:** The PR uses heavy inline styles for the new layout. If the project uses a CSS-in-JS library, Tailwind, or standard CSS modules, it would be better to extract these into a class to keep the component file clean.

## 5. Positive Notes
* The new visual layout perfectly matches the described product intent. 
* Clean removal of the old `<Empty>` component dependency.
* Handles missing channel topic gracefully without breaking layout.

## Rating
⚠️ **Needs Changes** (due to the store subscription/re-render performance concern)