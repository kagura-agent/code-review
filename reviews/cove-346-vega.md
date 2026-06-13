# Code Review: PR #346 (Round 2)

## 1. Summary
The fixes in this round successfully implement the Unread Spec rules for edge cases (never-read channels, missing last-read messages) and correctly bind the "Mark as Read" button to the API. However, a **critical performance regression** was introduced during the rendering of the `NEW` separator. Because of this $O(N^2)$ bug, I am marking this PR as **❌ Major Issues** requiring immediate changes before merge.

## 2. Previous Issues Status

* **C1: NEW line unreachable when lastReadIdx=-1** — ✅ **Fixed**. The logic now properly falls back to showing the line before the first message (`i === 0`) if `lastReadId` is not found in the loaded messages.
* **C2: No indicators for never-read channels** — ✅ **Fixed**. Explicitly handles `!lastReadId` by treating all messages as unread and setting the separator at `i === 0`.
* **C3: Top banner persists forever on bottom-entry** — ⚠️ **Partially Fixed**. Scrolling to the bottom now successfully clears the banner via `handleScroll`. However, if the channel has very few messages and **no scrollbar exists**, `onScroll` will never fire. The user is stuck with the banner until they manually click "Mark as Read".
* **Nova-1: "Mark as Read" doesn't actually call ack** — ✅ **Fixed**. It now correctly invokes `useReadStateStore.getState().markRead()` and `api.ackMessage()`.

## 3. New Issues (Introduced in Fixes)

* ❌ **Major Performance Regression ($O(N^2)$ Render)**
  In `MessageList.tsx`, inside the `messages.map` loop, you added:
  ```typescript
  const lastReadIdInMessages = lastReadId ? messages.some((m) => m.id === lastReadId) : false;
  ```
  `messages.some` traverses the array. Because it is inside `messages.map`, it runs $N$ times, resulting in $O(N^2)$ operations on *every single render*. For a channel with 500 messages, this is 250,000 checks per render frame, which will cause massive UI lag during typing.
  **Fix**: Hoist `lastReadIdInMessages` computation *outside* the `messages.map` loop so it only runs once per render.

## 4. Remaining Suggestions

* **No-scrollbar Banner Persistence**: To fix the C3 edge case, consider checking `isNearBottom(container)` inside the `useEffect` that runs on channel entry or messages update. If the user is already at the bottom and all unread messages are visible without scrolling, immediately clear the top banner.
* **Wrapper Divs**: Wrapping `LazyMessageItem` in a `div` might slightly impact flex layouts depending on the parent CSS. Using `<React.Fragment key={msg.id}>` is generally safer for injecting sibling elements like the separator.

## 5. Positive Notes
* The entry state computation logic using `unreadComputedForRef` is very clean and accurately reflects the freeze-on-entry requirement from the spec.
* Good job thoroughly reading the spec and mapping out the three conditions (Case A, B, C) for the separator!

## Rating
**❌ Major Issues** (O(N^2) render loop must be fixed).
