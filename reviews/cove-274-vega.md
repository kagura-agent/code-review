# Code Review: cove#274 (Round 2)

**Reviewer:** Vega
**Status:** Approved 🟢

## R1 Issues Verification

### 🔴 Must Fix
- ✅ **1. setTimeout leak:** `autoHideTimerRef` was successfully added, and timers are now properly cleared on unmount, channel switch, and before setting new timeouts. Cross-channel pollution is fixed.
- ✅ **2. Mark as Read doesn't call ackMessage:** `handleMarkAsRead` now fetches the latest messages and calls `api.ackMessage(channelId, lastMessage.id)` to update the server.
- ✅ **3. Banner direction mismatch:** `bannerModeRef` tracks "catchup" vs "live" modes. The UI now distinguishes live arrivals ("↓ X new messages") from catching up ("↑ X new messages since ... — Jump"), and `handleBannerClick` correctly routes to either `scrollToBottom()` or `scrollToDivider()`.
- ✅ **4. Initial scroll race:** `isInitialScrollRef` successfully guards the first programmatic scroll event, preventing it from instantly dismissing the newly shown banner.

### 🟡 Should Fix
- ✅ **5. Extra wrapper div:** The `<div>` wrapper in the mapping function was correctly replaced with a `<Fragment>`, preserving CSS layout.
- ✅ **6. unreadInfo count accumulates:** `setUnreadInfo(null)` is now called appropriately alongside `setShowBanner(false)` in the scroll listener, dismiss button, and click handler.
- ✅ **7. findIndex O(n) every render:** `dividerBeforeIndex` is now properly memoized via `useMemo`.
- ✅ **8. onScroll re-binds on showBanner change:** `showBannerRef` is now used inside the `onScroll` closure, and `showBanner` was removed from the effect dependencies, ensuring the listener binds only once per channel.

## Fresh Code Review

The refactoring and logic adjustments look solid:
- The implementation of `isInitialScrollRef` effectively sidesteps the React/DOM event race condition without causing side effects.
- The use of `Fragment` paired with passing `isGroupStart = {showDivider || isGroupStart}` to `MessageItem` is an excellent touch, ensuring the divider cleanly forces an avatar/header redraw right below it.
- State management across modes (Live vs Catch-up) is handled robustly, blending React refs (to avoid unnecessary re-renders) and state variables (to drive UI).

**Conclusion:** All requested changes have been excellently addressed. The feature is clean, safe from memory leaks, and handles edge cases reliably. Ready to merge!