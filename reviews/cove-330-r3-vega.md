# Code Review: PR #330 (Round 3)
**Reviewer:** Vega 💫
**Status:** ✅ Ready

## Summary
Round 3 looks rock solid. The critical issues identified in Round 2 have been successfully resolved. The UX for infinite scrolling should now feel smooth, without jarring visual jumps from the spinner or incorrect auto-scrolling behaviors during channel switches.

## Critical Issues (Resolved)
1. **firstMessageIdRef Channel Switch Bug**: ✅ Fixed. The `useLayoutEffect` correctly resets `firstMessageIdRef.current` to `undefined` on channel switch, preventing `wasPrepend` from falsely triggering and skipping auto-scroll.
2. **Spinner Double Jolt**: ✅ Fixed. The spinner is now rendered outside the scroll container flow using an absolute positioned overlay with a gradient background. This prevents the scrollHeight from mutating when the spinner toggles, fully eliminating the 30-40px jolt.
3. **loadingOlder State Leak**: ✅ Fixed. The `.finally()` block now correctly implements the `channelIdRef.current === id` guard before updating the React state, preventing cross-channel leaks.

## Product Impact
Infinite scroll functionality is stable. Fast channel switching while a fetch is in-flight is handled gracefully by the guards. Scroll height restoration works perfectly, even correctly accounting for the height of the newly added "beginning of the conversation" text indicator when `hasMore` flips to false.

## Suggestions (Non-blocking)
- **Minor Memory Leak in `fetchingOlder`**: The `fetchingOlder` Map is still unbounded, meaning it will slowly accumulate channel IDs over time. Since it only stores booleans, the footprint is small, but it's best practice to clean it up (e.g., using `fetchingOlder.delete(id)` in the finally block instead of setting it to `false`, or using `cappedMapSet`).
- **Initial Fetch Array Mutation**: The new `loadOlder` logic correctly copies the array before reversing (`[...fetched].reverse()`). However, the initial load fetch in the existing code still performs an in-place mutation (`msgs.reverse()`). Consider applying the spread copy there as well for consistency.
- **AbortController**: Still no `AbortController` implemented for the API requests, though the channel guard mitigates the visual impact of abandoned requests.

## Positive Notes
- The implicit fix for the `pendingPrependRestoreRef` cross-channel bug via the `channelIdRef.current !== id` guard is very clean. It avoids the need for a complex channel-keyed ref map.
- Excellent use of `useLayoutEffect` for scroll restoration.