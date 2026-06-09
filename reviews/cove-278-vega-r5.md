# Code Review: PR #278 (Round 5)
**Reviewer:** 💫 Vega  
**Status:** Approved ✅

## R4 Blocker Addressed
- **ESLint error (`react-hooks/refs`):** Fixed! The introduction of `scrollContainerCallbackRef` and the `scrollRoot` state correctly avoids reading `scrollContainerRef.current` during the render phase. This is the idiomatic React pattern for passing a DOM node to children or hooks safely, effectively unblocking CI.

## Fresh Code Verification
- The `channelIdRef` properly tracks `channelId` to prevent stale closures in the scroll listener.
- `useLayoutEffect` correctly manages the `restoringRef` flags without race conditions.
- No new React or ESLint violations were introduced in R5.

## Outstanding Non-Blocking Issues (Follow-ups)
These were noted in R4 and remain present. They do not block this PR but should be logged as follow-up tickets:
1. **Missing Tests:** Still no tests covering the new IntersectionObserver, lazy rendering, or scroll restoration logic.
2. **Fixed Placeholder Height:** `LazyMessageItem` uses a hardcoded `PLACEHOLDER_HEIGHT = 60`. Messages with attachments, multi-line text, or embeds will cause minor scroll jumps if scrolled back into view rapidly before render.
3. **Silent Fetch Failures:** `api.fetchMessages(channelId).catch(err => console.error(...))` just logs to console. The user may see a permanent loading spinner or stale UI if the initial fetch fails.
4. **Stale Cache with WebSockets:** `lastFetchTime` is a local module variable updated only on fetch. If a channel stays active via WebSockets for >5 minutes, navigating away and back will trigger a redundant API refetch because `Date.now() - fetchTime > STALE_MS`.

## Verdict
The core scroll architecture is solid, the UI logic matches the desired "no flash" specification, and the rendering violation is fixed. Ready to merge!
