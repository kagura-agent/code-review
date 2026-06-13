# PR #346 Review — feat: NEW separator line and unread banner

**Reviewer:** 🌠 Nova
**Repo:** kagura-agent/cove
**Branch:** `feat/unread-experience` → `main`
**Files changed:** 2 (`MessageList.tsx` + `docs/unread-spec.md`)
**Diff:** +219 / -11

---

## 1. Summary

Implements three Discord-style unread indicators inside `MessageList.tsx`:

- **NEW line** — red separator rendered inline before the first message whose `prev.id === lastReadIdSnapshot`. Frozen via `lastReadIdSnapshotRef` captured on `channelId` change.
- **Top banner** — "N new messages — Mark as Read" pinned absolutely above the scroll container. Count is the frozen `entryUnreadCount`.
- **Bottom pill** — "N new messages ↓" incremented inside the new-message effect (#5) when `!wasNearBottomRef.current`.

The frozen-snapshot architecture is sound: `useLayoutEffect` on `channelId` resets refs + state synchronously, and a separate `useEffect` computes the count exactly once per channel entry guarded by `unreadComputedForRef`. No server changes; reuses existing `useReadStateStore.getLastReadId`.

The spec doc is well-written and matches the implementation intent. The implementation is **close** to merge-ready but has a few UX edge cases that produce visibly wrong behaviour in realistic scenarios. Logic is otherwise correct.

**Verdict: ⚠️ Needs Changes** (small, focused fixes — no data-loss risk).

---

## 2. Critical Issues

### 2.1 Top banner can persist forever when user lands at bottom

**Scenario:**
1. User enters channel B; `scrollMemory.wasAtBottom === true` (or B is new).
2. `useLayoutEffect` (scroll restore) calls `scrollToBottomImmediate` with `restoringRef = true`, so the scroll listener is suppressed.
3. Banner is shown by the compute effect.
4. User is now at bottom, banner visible, but **no `scroll` event ever fired**, so the `if (atBottom) setShowTopBanner(false)` branch in the scroll handler never runs.
5. The user reads all the visible-from-the-bottom messages without scrolling, then sends a reply. `scrollToBottom()` is invoked but it's a no-op (`scrollIntoView` on a target already in view) → still no scroll event → **banner stays "N new messages — Mark as Read" forever** until the user manually scrolls or clicks the button.

This is a real, observable UX bug in the most common entry pattern (read‑state cached at bottom, came back to find a few new messages).

**Fix:** Either
- After the entry restore, if `wasNearBottomRef.current === true` (i.e. landed at bottom), schedule `setShowTopBanner(false); setNewMessagesBelowCount(0)` once `restoringRef` clears, or
- In effect #5 when `isOwnMessage`, also clear `showTopBanner` (sending = engaged), or
- Trigger an explicit `isNearBottom(container)` check inside the own-message branch and clear if true.

### 2.2 "Mark as Read" doesn't call any ack/clearUnread

```jsx
onClick={() => {
  scrollToBottom();
  setShowTopBanner(false);
}}
```

It works *coincidentally* because effect #3 already auto-acks to the latest message on channel mount, so `lastReadId` server-side is already up to date. However:

- The intent of a "Mark as Read" button is to call `useReadStateStore.clearUnread(channelId)` + `api.ackMessage(...)` explicitly.
- If the auto-ack logic in effect #3 is ever refactored (e.g. delayed until actual read), this button silently becomes a lie.
- Any real-time message that arrives between mount and the click is **not** acked by this handler.

**Fix:** explicitly call `useReadStateStore.getState().clearUnread(channelId)` and `api.ackMessage(channelId, messages[messages.length-1].id)` in the handler, keyed to the *current* latest message id (not the entry snapshot).

### 2.3 `entryUnreadCount = messages.length` when `lastReadId` not in loaded messages

```js
if (lastReadIdx === -1) {
  setEntryUnreadCount(messages.length);
  setShowNewLine(true);   // ← will never render (no prev.id === lastReadId match)
  setShowTopBanner(true);
  ...
}
```

Two problems:
1. **`showNewLine` is set true but cannot render** — no message has `prev.id === lastReadId` because lastReadId isn't in the array. UX-inconsistent: banner says "5 new messages" while the NEW line is absent.
2. **The count is wrong-by-direction.** `lastReadId` not being in the loaded slice could mean *older than oldest loaded* (banner count ≤ messages.length is reasonable) **or** *newer than the loaded slice* (e.g. user read on another device and that newer message hasn't been fetched yet). In the latter case, `messages.length` over-reports dramatically.

**Fix:** in the `lastReadIdx === -1` branch, prefer to suppress the banner entirely (or compute by comparing timestamps/ids if your id scheme is ordered). At minimum, do not also set `showNewLine = true` when the line cannot render.

---

## 3. Product Impact

- **Banner persistence (2.1)** is the most user-visible. Many users in active channels land at the bottom on re-entry; they will see a stuck "N new messages" banner.
- **Stale ack semantics (2.2)** are not visible to the user but are a footgun for the next refactor.
- **Wrong-count fallback (2.3)** is rare but produces visibly inflated numbers ("47 new messages") in cross-device scenarios.
- The NEW line behaviour matches the spec exactly: stays on scroll, clears on send/leave. ✓
- The bottom pill only appears for real-time messages while scrolled up. ✓
- Auto-scroll for own messages still works; entry ack still happens. No regressions to existing scroll architecture.

---

## 4. Suggestions (non-blocking)

1. **Wrapping `<div key={msg.id}>` around `LazyMessageItem`** changes the rendered DOM tree (+1 node per message, every render). Use `<React.Fragment key={msg.id}>` to avoid layout/CSS-selector surprises and a small reflow cost on long channels. Note: `LazyMessageItem` is passed `scrollRoot` explicitly so its IntersectionObserver is fine, but flex/grid containers and `:nth-child` selectors targeting the previous structure could break subtly.

2. **`getLastReadId` in the deps of the `useLayoutEffect`** — if Zustand ever rebinds the selector reference, the effect will re-run mid-session and *reset every indicator while wiping the snapshot*. In practice store methods are stable, but it's safer to dereference inside the effect: `const lastReadId = useReadStateStore.getState().getLastReadId(channelId);` and drop the dep.

3. **Bottom pill is `position: absolute`** but rendered outside the inner `position: relative` wrapper, so it positions against whatever ancestor is relative (probably the page root). Move it inside the relative wrapper or give the outer fragment a positioned parent — currently the pill may anchor to the wrong element in some layouts.

4. **Scroll handler fires `setShowTopBanner(false); setNewMessagesBelowCount(0)` on every scroll event when at bottom.** React bails on identity-equal `useState` updates, so this is cheap, but consider gating: `if (atBottom && (showTopBanner || newMessagesBelowCount)) {...}` would also save a function call. Minor.

5. **Compute effect short-circuits on `unreadComputedForRef.current === channelId`** before the `!messages?.length` check. If `setMessages` ever **replaces** with a smaller array (fresh fetch returns 50 but cache had 100 including lastReadId), the previously-computed count silently becomes inaccurate. Consider recomputing if `lastReadIdx` would now disagree with the stored count, or at least re-check whether `lastReadId` is still in the new array.

6. **NEW line key safety:** the `<div key={msg.id}>` wraps both the separator and the message. If you ever filter the NEW line into its own list item (e.g. for accessibility), having it inside the message wrapper means screen readers may announce it as part of the next message. A bare sibling element with `role="separator" aria-label="New messages"` would be friendlier.

7. **A11y:** "Mark as Read" `<span onClick>` should be `<button>` (keyboard-focusable, role=button); same for the bottom pill.

8. **The compute effect's three branches all end with the same lines** (`setEntryUnreadCount(...); setShowNewLine(...); setShowTopBanner(...); unreadComputedForRef.current = channelId;`). Extracting a single `commit(count, show)` helper or computing locally then setting once would tighten the logic and avoid drift if a future branch is added.

---

## 5. Positive Notes

- The **frozen-snapshot architecture** (`lastReadIdSnapshotRef` + `unreadComputedForRef`) cleanly separates "what was unread on entry" from "current state" — exactly what's needed to honour "Chatting at bottom never triggers anything."
- The **layout-effect reset** (sync with `channelId`) avoids the classic race where a new channel's messages render with the old channel's snapshot.
- The fetch-promise channel-id guard (pre-existing) means **channel-switch-during-load is safe** — no need to add a new guard for the unread compute.
- Effect #5 correctly distinguishes own messages (clear NEW line + always scroll) from received messages (only scroll if at bottom; otherwise increment pill).
- Including `docs/unread-spec.md` as ground truth is great practice — review can be done against an authoritative spec instead of guessing.
- Uses CSS variables (`--accent`, `--status-danger`) for theming consistency.
- Reuses existing `useReadStateStore` — zero server change is a big win.

---

## Final Verdict

**⚠️ Needs Changes** — three small fixes (banner-persistence on bottom entry, Mark-as-Read actually marking as read, sane fallback when `lastReadId` not in loaded slice) before merge. Architecture and core logic are correct. Once the bottom-entry banner is dismissed and the click handler does what its label promises, this is ready.
