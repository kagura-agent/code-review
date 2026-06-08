# Code Review: PR #274 (Message-level unread indicators)

## 🐛 Critical Bugs

1. **Banner Immediately Dismisses on Load (Race Condition)**
   In the `fetchMessages` effect, when there are unread messages, the code calls `scrollToBottom("instant")` and `setShowBanner(true)`. However, scrolling to the bottom triggers the `onScroll` listener. 
   Inside `onScroll`, there is:
   ```typescript
   if (wasNearBottomRef.current && showBanner) {
     setShowBanner(false);
   }
   ```
   Because the scroll position is now at the bottom, `wasNearBottomRef.current` becomes `true`, and the banner is immediately dismissed. The user will either see a brief flash or not see the banner at all.

2. **Live Messages Banner is Broken (Wrong Direction & Action)**
   When a user is scrolled up reading history and a new message arrives via WebSocket, the code correctly detects `!wasNearBottomRef.current` and shows the banner. 
   **However**, the banner hardcodes the `↑` arrow and its click handler (`handleBannerClick`) calls `scrollToDivider()`. 
   - New messages arrived at the **bottom**, so the arrow should point down (`↓`).
   - `scrollToDivider()` jumps *up* to the old unread divider (if one exists) instead of scrolling *down* to the new messages. If no divider exists, clicking the banner does nothing.

3. **Divider Never Clears if Banner Auto-Hides**
   The `clearChannelOpenSnapshot(channelId)` is only called on unmount or when explicitly clicking "Mark as Read" (`handleMarkAsRead`). If the banner auto-hides after 5 seconds (or dismisses due to the scroll bug above), the "NEW" divider stays in the DOM forever until the channel is closed and re-opened.

## 🎨 UX / Product Issues

1. **Initial Scroll Position Strategy**
   Currently, opening a channel with unread messages jumps the user to the very bottom, forcing them to click a banner to jump *up* to read what they missed. The standard pattern (e.g., Discord, Slack) is to jump the user to the "NEW" divider initially, and show a "↓ X new messages" banner to jump to the bottom. If jumping to the bottom is intentional, the `onScroll` logic needs to be fixed to not immediately clear the "jump up" banner when the user is at the bottom.

## 🛠️ React Patterns & Architecture

1. **`onScroll` Event Re-binding**
   ```typescript
   useEffect(() => {
     // ...
     container.addEventListener("scroll", onScroll, { passive: true });
     return () => container.removeEventListener("scroll", onScroll);
   }, [showBanner]);
   ```
   Adding `showBanner` to the dependency array means the scroll listener is destroyed and recreated every time the banner toggles. Use a `ref` (e.g., `showBannerRef = useRef(showBanner)`) to check the current state inside a single mount `useEffect` to avoid unnecessary rebinding.

2. **Auto-hide Stale Closure**
   The 5-second `setTimeout` for auto-hiding the banner captures the environment. While `wasNearBottomRef.current` is a ref and will be up-to-date, auto-dismissing the banner without clearing the divider state (`clearChannelOpenSnapshot`) leaves the UI in a weird half-read state.

## 📝 Recommendations

1. **Split Banner States**: You have two distinct banner use cases:
   - *Catch-up*: User opens channel, banner points UP (`↑`) to the divider.
   - *Live arrival*: User is scrolled up, new message arrives, banner points DOWN (`↓`) to the bottom.
   Track these states separately so the click action and scroll dismissal logic can do the right thing.
2. **Sync Divider & Banner State**: If the user dismisses the banner by scrolling or timeout, you likely want to clear the divider too (or vice versa).
3. **Fix the Load Race Condition**: If keeping the jump-to-bottom behavior, don't dismiss the "Catch-up" banner when `wasNearBottomRef.current` is true, since the user is *supposed* to be at the bottom for that banner to be visible.