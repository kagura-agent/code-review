# Review — cove#274: NEW divider + unread banner

**Reviewer:** 🌠 Nova
**Verdict:** Request changes (a few real bugs; mostly polish)

Solid first cut. Divider placement logic is correct, snapshot lifecycle is sound, and the auto-ack comment in gateway is a nice touch. A handful of issues worth fixing before merge.

---

## 🔴 Bugs

### 1. `setTimeout` leak / setState-on-unmount in fetch effect
`MessageList.tsx` (~L70–75)
```ts
setTimeout(() => {
  if (wasNearBottomRef.current) {
    setShowBanner(false);
  }
}, 5000);
```
The timer is created inside the fetch effect but never cleared. If the user switches channels within 5s, the effect's cleanup runs but this timer keeps ticking and calls `setShowBanner` on an unmounted-or-different-state component (React 18 warning, in some cases stomps the *next* channel's banner state because `setShowBanner` is the same setter identity after remount on a different `channelId` key only if React preserves the instance — here it does, since `channelId` is a prop, not a `key`. So it **can leak state across channels.**)

Fix:
```ts
let bannerTimer: ReturnType<typeof setTimeout> | undefined;
// ...
bannerTimer = setTimeout(...);
// in the outer cleanup:
return () => {
  cancelled = true;
  if (bannerTimer) clearTimeout(bannerTimer);
};
```

### 2. "Mark as Read" doesn't actually mark as read
`handleMarkAsRead` only clears the local snapshot + banner. No `api.ackMessage` call. If the user is scrolled up and clicks the button:
- Local UI clears ✅
- Server still has stale `last_read_message_id` ❌
- Sidebar badge on other clients / next session reload reappears

Fix: call `api.ackMessage(channelId, lastMessage.id)` before clearing the snapshot.

### 3. Wrapping every message in an extra `<div>` may regress layout
```tsx
return (
  <div key={msg.id}>
    {showDivider && <div ref={dividerRef}><NewMessagesDivider /></div>}
    <MessageItem ... />
  </div>
);
```
Previously `MessageItem` was a direct flex child of `.scroll-container`. Now it's nested in an extra block `div`. Any sibling-selector CSS (`MessageItem + MessageItem`, gap, group-start margin rules, hover-pill positioning that relies on parent geometry) will silently break. Worth spot-checking message spacing/grouping visually.

Cheap fix: use a fragment with the divider hoisted before the item:
```tsx
return showDivider ? (
  <Fragment key={msg.id}>
    <div ref={dividerRef}><NewMessagesDivider /></div>
    <MessageItem message={msg} isGroupStart />
  </Fragment>
) : (
  <MessageItem key={msg.id} message={msg} isGroupStart={isGroupStart} />
);
```

---

## 🟡 Correctness / state edges

### 4. Snapshot only taken when `unreadChannels[channelId]` is true
```ts
if (store.unreadChannels[channelId]) {
  store.snapshotChannelOpen(channelId);
}
```
That's the intended path (don't show divider when there's nothing new), but it means a channel that becomes unread *after* mount (e.g., new message arrives while user is in the channel but scrolled up) never gets a snapshot → **no NEW divider for messages arriving mid-session.** The banner handles count, but the in-thread divider line is missing.

Consider snapshotting lazily the first time `wasNearBottomRef.current === false` and a new message arrives.

### 5. `unreadInfo` count keeps accumulating after dismiss-via-scroll
When the user scrolls to bottom, `showBanner` flips to false but `unreadInfo` is left intact. If they scroll up and a new message arrives:
```ts
const count = (prev?.count ?? 0) + newCount;
```
…now the banner shows e.g. "12 new messages" when only 1 actually arrived since the last bottom hit. Reset `unreadInfo` to `null` (or zero) when banner is hidden by scroll, not just on mark-as-read.

### 6. `channelOpenReadId` is reactive, but `dividerBeforeIndex` is recomputed in render
```ts
let dividerBeforeIndex = -1;
if (channelOpenReadId) {
  dividerBeforeIndex = messages.findIndex((m) => m.id > channelOpenReadId);
}
```
`messages.findIndex` runs O(n) on **every** render (typing indicator, hover, reaction, scroll causing parent re-render via context, etc.). For a 500-message channel and a chatty UI this is wasted work. Wrap in `useMemo([messages, channelOpenReadId])`.

While there: message IDs look comparable with `>` (string compare). If IDs are ULIDs/snowflakes-as-strings this works; if they ever become numeric strings of unequal length (`"9" > "10"`), the divider will land in the wrong spot. Worth a comment confirming the ID format, or use a sequence/timestamp field instead.

### 7. `onScroll` effect re-binds on every `showBanner` change
```ts
useEffect(() => { ... }, [showBanner]);
```
Each `showBanner` toggle removes/re-adds the scroll listener. Not catastrophic, but easy to avoid by reading `showBanner` from a ref or moving the hide-on-bottom logic into the same place that sets `wasNearBottomRef`.

---

## 🟢 Nits

- The `5000ms` auto-hide is a magic number; pull it to a named constant alongside `NEAR_BOTTOM_THRESHOLD`.
- `bannerWrapperStyle` has `position: relative; zIndex: 10` but the banner is rendered *outside* `scrollContainerRef` as a sibling, so `position: relative` doesn't do anything here. Either drop it or change to `absolute` if you wanted it to overlay the list (current placement pushes layout — fine, but document the choice).
- `aria-label="New messages"` on the divider is good. The banner has `role="button" tabIndex={0}` but **no `onKeyDown`** — keyboard users can focus it but can't activate it. Add `Enter`/`Space` handling.
- The dismiss `<button>` lives inside a `role="button"` div → nested interactive elements. Accessibility tools will complain. Make the outer container a real `<button>` or restructure (header text as button, dismiss as separate sibling button).
- `prev` declared with `let` reuses the closure variable from the parent map's `(msg, i)` — fine but could be `const prev = i > 0 ? ...`.

---

## ✅ What's good

- Snapshot lifecycle (snapshot on mount-if-unread, clear on unmount) is the right shape.
- `channelOpenReadIds` carved out as a separate field from `readStates` keeps the "I have unread" semantic clean and survives the auto-ack overwriting `readStates`.
- The gateway-subscriptions comment explains the dual-ack responsibility — future readers will thank you.
- `isGroupStart={showDivider || isGroupStart}` is a nice touch so the first unread message gets full author header.

---

## Recommended path
1. Fix #1, #2, #3 (real bugs / regressions).
2. Memoize #6 and decide on string-ID comparison safety.
3. The rest can be follow-ups but #5 will visibly confuse users, worth grabbing now.
