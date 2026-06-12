# Code Review: PR #330 (feat: infinite scroll)
**Reviewer:** 💫 Vega

## 1. Summary
This PR successfully introduces infinite scroll functionality. It adds cursor-based pagination parameters to the API, a new store method to securely prepend and deduplicate older messages, and an intersection-based scroll listener to trigger fetching when the user scrolls within 200px of the top. The logic overall is solid, especially around avoiding stale closures in the event listeners. However, there are a couple of race conditions and memory leaks that need to be addressed before merging.

## 2. Critical Issues
- **Scroll Position Race Condition**: In `MessageList.tsx`, `prependMessages(id, older)` triggers a React state update, and immediately after, `requestAnimationFrame` is used to read `newScrollHeight`. Because React state updates are batched and asynchronous (especially in React 18+), the DOM may not have updated by the time the animation frame callback fires. If `newScrollHeight === prevScrollHeight`, the scroll adjustment fails, causing a violent viewport jump when React finally commits the DOM update.
  *Fix*: Wrap the state update in `flushSync` from `react-dom` to force a synchronous DOM update before reading the new scroll height:
  ```tsx
  const prevScrollHeight = container.scrollHeight;
  flushSync(() => {
    prependMessages(id, older);
  });
  restoringRef.current = true;
  container.scrollTop += container.scrollHeight - prevScrollHeight;
  requestAnimationFrame(() => {
    restoringRef.current = false;
  });
  ```

## 3. Product Impact
- **Unbounded Maps (Memory Leak)**: `hasMoreHistory` and `fetchingOlder` are standard module-level `Map`s, but they are updated directly via `.set()` instead of using the file's existing `cappedMapSet` helper. As users navigate through many channels over time, these maps will grow unboundedly, leaking memory.
  *Fix*: Use `cappedMapSet(hasMoreHistory, id, ...)` and `cappedMapSet(fetchingOlder, id, ...)` to ensure memory remains bounded, just like `lastFetchTime` and `lastAckedIds`.

## 4. Suggestions
- **Unmounted Component State Updates**: In the `fetchMessages` promise chain, `setLoadingOlder(false)` may be called after the `MessageList` component has unmounted (e.g., if the user quickly switches channels while loading). Consider tracking an `isMounted` ref and checking `if (isMounted.current)` in the `.finally()` block, or using an `AbortController` to cancel the fetch on unmount.
- **Zustand Deduplication Scale**: The `prependMessages` deduplication algorithm creates a `Set` of all existing message IDs. While O(N) is perfectly fine for typical channel depths, if a user scrolls back thousands of messages, this could theoretically cause slight JS thread blocking. It's acceptable for now, but keep it in mind if performance issues arise in extremely large channel histories.

## 5. Positive Notes
- **Stale Closure Avoidance**: Using `useMessageStore.getState().messages[id]` inside the `onScroll` listener to retrieve the freshest state is a fantastic pattern. It avoids the pitfall of needing to rebind the scroll listener every time the message array changes.
- **Clean Fallback for Initial Loads**: Checking `reversed.length >= PAGE_SIZE` directly on the initial channel load properly seeds `hasMoreHistory`. This smartly avoids a redundant API call when a user scrolls up in a channel that inherently has fewer than 50 messages.

**Rate**: ⚠️ Needs Changes