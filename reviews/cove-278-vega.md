# Code Review: PR #278 (cove)

**Reviewer:** 💫 Vega  
**Target:** `kagura-agent/cove` PR #278  

### 1. Summary
This PR implements a robust, Discord-like scroll architecture that successfully addresses layout flashing and position persistence across channel navigation. The combination of a module-level `scrollMemory` map, stable `distanceFromBottom` calculations, and an `IntersectionObserver`-based lazy renderer (`LazyMessageItem`) is highly effective. Eagerly rendering the bottom N items to guarantee accurate container dimensions for scroll math is a particularly brilliant insight.

### 2. Critical Issues (Blocking)
* **Scroll Listener Never Attached on First Visit:** 
  In `MessageList.tsx`, Effect #2 (the scroll listener) has `[channelId]` as its only dependency. If a user visits a channel that isn't in the cache, `messages` is initially `undefined`, which causes `<Spin />` to render and `scrollContainerRef.current` to be `null`. The effect runs, hits `if (!container) return;`, and stops. When the fetch completes and `messages` populates, the `<div ref={scrollContainerRef}>` mounts, but **Effect #2 does not re-run** because `channelId` hasn't changed. 
  * **Result:** The scroll position is never saved for freshly loaded channels. If the user scrolls up and switches away, their position is lost.
  * **Fix:** Add a boolean dependency for when messages load. For example: `const hasMessages = !!messages;` and use `[channelId, hasMessages]` in the dependency array.

### 3. Product Impact
Overall, this introduces a massive UX upgrade. The lazy rendering will keep the DOM light and performant even in heavily populated channels. However, due to the critical bug mentioned above, the position-restore feature will subtly fail for channels visited for the first time during a session, which could frustrate users who scroll up to read history and then switch tabs. 

### 4. Suggestions (Non-blocking)
* **Date Parsing Overhead:** In the render loop for `messages.map`, the `isGroupStart` variable parses `new Date(msg.timestamp)` twice per message. On channels with hundreds of cached messages, parsing strings into Date objects on every single render (e.g. when typing indicators or reactions change) causes unnecessary CPU drag. Consider storing timestamps as numerical epochs in the store, or using a simpler numerical comparison if the API already provides epochs.
* **Race Condition in Auto-Scroll Suppression:** `channelSwitchRef` uses `requestAnimationFrame` to unset itself. This creates a ~16ms window where if a real-time message arrives exactly after a channel switch, the auto-scroll for that specific message will be erroneously suppressed. Not a big deal, but a strict React state update cycle might be more predictable than relying on the animation frame queue.

### 5. Positive Notes
* The module-level documentation block (`SCROLL ARCHITECTURE`) is outstanding. It clearly explains the "why" behind the code, which is invaluable for future maintenance.
* The realization that `distanceFromBottom` is mathematically stable even when lazy items expand *above* the viewport is spot-on.
* Eagerly rendering the newest 30 items (`EAGER_COUNT`) so that the bottom of the container has a stable layout during initial calculation is a very elegant solution to a notoriously difficult UI problem.

**Rate:** ⚠️ Needs Changes