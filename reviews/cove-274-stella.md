# R2 Review — kagura-agent/cove#274 (Stella)

## Verdict

**Request changes.** Most R1 items were addressed in the visible diff, but the timer/state pollution fix is incomplete: the new `requestAnimationFrame` path can still run after a channel switch and recreate stale banner/timer state. I also found one fresh product-correctness gap for channels with no previous read cursor.

## R1 Follow-up Checklist

### 🔴 Must Fix

1. **setTimeout leak / cross-channel state pollution** — ❌ **Not fully addressed; escalated.**
   - The timeout is stored/cleared, but the `requestAnimationFrame` scheduled at `MessageList.tsx:162-176` is not cancelled and does not re-check `cancelled` inside the callback. If the user switches channels after fetch resolves but before the RAF runs, the stale callback can still call `scrollToBottom`, `setShowBanner(true)`, and create a new timeout after cleanup already ran.

2. **Mark as Read doesn't call `ackMessage`** — ✅ Addressed.
   - `handleMarkAsRead` now calls `api.ackMessage(channelId, lastMessage.id)` at `MessageList.tsx:289-295` and clears local unread state.

3. **Banner direction mismatch** — ✅ Mostly addressed.
   - `bannerModeRef` distinguishes `catchup` vs `live`; catch-up jumps to the divider and live jumps to bottom (`MessageList.tsx:270-280`, `317-321`).

4. **Initial scroll race** — ✅ Mostly addressed, but related stale RAF caveat above.
   - The first programmatic scroll event is guarded with `isInitialScrollRef` (`MessageList.tsx:160-164`, `209-214`).

### 🟡 Should Fix

5. **Extra wrapper div may break CSS layout** — ✅ Addressed.
   - Uses `Fragment` around divider + message (`MessageList.tsx:332-336`).

6. **`unreadInfo` count accumulates after dismiss-via-scroll** — ✅ Addressed.
   - Scroll-to-bottom and banner click both clear `unreadInfo` (`MessageList.tsx:216-220`, `277-279`).

7. **`findIndex` O(n) every render** — ✅ Addressed.
   - Divider index is memoized (`MessageList.tsx:299-303`).

8. **`onScroll` re-binds on `showBanner` change** — ✅ Addressed.
   - `showBannerRef` is used and the scroll listener deps no longer include `showBanner` (`MessageList.tsx:105-107`, `205-224`).

## Blocking Findings

### 🔴 Must Fix: stale RAF can still leak banner/timer state across channel switches

**Where:** `packages/client/src/components/MessageList.tsx:162-176`

The R2 fix clears `autoHideTimerRef` during cleanup, but the timeout is created inside an uncancelled `requestAnimationFrame`. This leaves a race:

1. Channel A fetch resolves and schedules the RAF at lines 162-176.
2. User quickly switches to Channel B before the RAF executes.
3. Cleanup runs, but there is no timeout yet to clear and the RAF id is not cancelled.
4. The stale RAF from Channel A executes in the reused component instance, scrolling the current DOM, setting `showBanner`, and creating a fresh timeout using Channel A unread info.

This is the same class of cross-channel state pollution as R1 #1, just moved one async boundary earlier.

**Recommendation:** store the RAF id in a ref and cancel it on cleanup, and also re-check `cancelled` / current `channelId` inside every RAF before setting state or creating timers.

### 🔴 Must Fix: channels with no prior read cursor never show message-level unread indicators

**Where:** `packages/client/src/stores/useReadStateStore.ts:55-60`, `packages/client/src/components/MessageList.tsx:117-123`, `150-181`

`initReadStates` marks a channel unread when `last_read_message_id` is `null` and `last_message_id` exists, but `snapshotChannelOpen` only writes `channelOpenReadIds[channelId]` when `get().readStates[channelId]` exists. For a user who has never acked/read that channel before, `current` is `undefined`, so no snapshot is stored. Then `MessageList` sees no `openReadId` and takes the plain `scrollToBottom("instant")` path, with no NEW divider and no catch-up banner.

That means a fully unread channel — arguably the most important unread case — silently loses the new message-level indicators.

**Recommendation:** represent the “no previous cursor” case explicitly (e.g. `null` snapshot) and treat it as “divider before first message / unread count = all loaded messages,” or snapshot enough metadata to compute that case without relying on a truthy message id.

## Non-blocking Notes

- `handleMarkAsRead` swallows `ackMessage` errors (`catch(() => {})`) after optimistically clearing local UI. Existing code does this elsewhere too, so I’m not blocking on it, but a visible retry/log path would make this feature easier to debug.
- The clickable banner `div` has `role="button"` and `tabIndex={0}` but no keyboard handler. Consider handling Enter/Space for accessibility.
