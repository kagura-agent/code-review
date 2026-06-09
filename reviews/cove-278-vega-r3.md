# Code Review: PR #278 - Round 3

## 📝 Summary
Great job on the critical fixes! The scroll restoration clobbering bug, the ESLint ref mutation error, and the memory leak from unbounded Maps have all been successfully addressed. The `distanceFromBottom` approach with `useLayoutEffect` and `restoringRef` is conceptually solid and correctly implemented.

However, per the re-review rules, any unaddressed feedback from Round 2 must be escalated. All the suggestions from R2 were left unaddressed in this iteration, so they are now escalated to **Must Fix**. Additionally, there is a new dead code issue introduced in R3.

## 🔴 Must Fix (Escalated from R2)

1. **Date parsing overhead in render loop**
   You are still executing `new Date(msg.timestamp).getTime()` inside `messages.map`. For 10,000 messages, this instantiates 20,000 Date objects on every render. Use a lighter parsing method or precompute this state.
   
2. **Fixed Placeholder Height**
   `PLACEHOLDER_HEIGHT = 60` is still hardcoded. If messages are taller (e.g., multiline text, attachments), substituting them with 60px placeholders will cause the scroll height to jump wildly when they render, breaking the smooth scroll experience.

3. **Missing Tests for Scroll Logic**
   This scroll architecture is too complex to remain untested. Unit/integration tests are required to ensure no regressions occur.

4. **Silent Fetch Failure**
   API failures in `fetchMessages` only log to the console (`.catch((err) => console.error(...))`) but provide no UI feedback. If it fails, the user is left with a perpetual loading state or stale cache.

5. **IntersectionObserver missing `root`**
   The `IntersectionObserver` in `LazyMessageItem` still defaults to the browser viewport instead of the scroll container. If the app has structural padding or headers, this will miscalculate visibility.

6. **One Observer per `LazyMessageItem`**
   You are still instantiating a `new IntersectionObserver` for every single lazy item. This creates thousands of observers in memory. Use a single shared `IntersectionObserver` for the whole list.

## 🔴 Must Fix (New in R3)

7. **Dead Code (`cappedSetAdd`)**
   In `MessageList.tsx`, `SET_CAP`, `SET_EVICT`, and `cappedSetAdd` are defined but never used. The Set logic for `revealedIds` was placed in `LazyMessageItem.tsx` where it implements its own eviction. This unused code will trigger an ESLint/TS failure on CI. Remove it.

## ✅ Verified Fixes
- **Stale-cache scroll clobbering**: Fixed. `pendingScrollToBottomRef` is now safely gated by `!mem || mem.wasAtBottom`.
- **ESLint ref mutation**: Fixed. `channelIdRef.current = channelId` is properly moved inside `useLayoutEffect`.
- **Memory leaks**: Fixed. `scrollMemory`, `lastFetchTime`, and `lastAckedIds` are correctly bounded using the eviction helpers.

Please address the escalated items and the dead code to move forward.
