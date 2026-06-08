# 🌠 Nova — Re-Review (R2) of kagura-agent/cove#274

**Scope:** Message-level unread indicators — banner + `NEW` divider in `MessageList.tsx`, snapshot state in `useReadStateStore.ts`, comment-only change in `gateway-subscriptions.ts`.

**Verdict:** ✅ **All 8 R1 items addressed.** Code is approvable after addressing 2 small follow-ups noted below. Nice, surgical implementation.

---

## R1 Issue Status

| # | Severity | Issue | Status | Evidence |
|---|----------|-------|--------|----------|
| 1 | 🔴 | setTimeout leak / cross-channel pollution | ✅ Fixed | `autoHideTimerRef` stored, cleared on channel switch effect-cleanup AND before scheduling new timer AND inside its own callback. |
| 2 | 🔴 | Mark as Read didn't ack server | ✅ Fixed | `handleMarkAsRead` now calls `api.ackMessage(channelId, lastMessage.id)` and updates `lastAckedIds` + `clearUnread`. |
| 3 | 🔴 | Banner direction mismatch (catchup vs live) | ✅ Fixed | `bannerModeRef` tracks `"catchup" \| "live"`. Click → `scrollToDivider()` for catchup, `scrollToBottom()` for live. Arrow + text differ accordingly (`↑ … since HH:MM — Jump` vs `↓ N new messages`). |
| 4 | 🔴 | Initial scroll race hides banner | ✅ Fixed (mostly) | `isInitialScrollRef` guard skips the first scroll event after the programmatic `scrollIntoView("instant")`. See **Follow-up A** below. |
| 5 | 🟡 | Extra wrapper div | ✅ Fixed | Top-level uses `<Fragment>` (`<>…</>`), per-row uses `Fragment` keyed by msg.id. |
| 6 | 🟡 | unreadInfo accumulates after dismiss-via-scroll | ✅ Fixed | onScroll handler clears both `showBanner` and `unreadInfo` when user reaches bottom; banner click handler also resets `unreadInfo`. |
| 7 | 🟡 | findIndex O(n) every render | ✅ Fixed | `dividerBeforeIndex` wrapped in `useMemo([messages, channelOpenReadId])`. Placed before early returns — correctly respects Rules of Hooks. |
| 8 | 🟡 | onScroll re-binds on showBanner change | ✅ Fixed | `showBannerRef` mirror used inside handler; effect deps narrowed to `[channelId]`. |

---

## Follow-ups (minor — non-blocking)

### A. 🟡 `isInitialScrollRef` may swallow a real user scroll
`isInitialScrollRef.current = true` is set unconditionally before the rAF, but the `scrollIntoView("instant")` does **not** fire a scroll event when the container is already at the bottom (or when there is no overflow at all — short channel). In that case the flag stays `true` until the user's first manual scroll, which then gets eaten as if it were the initial programmatic one.

**Suggested fix (one of):**
- Clear the flag from a `setTimeout(…, 0)` / second rAF after the scroll so the guard is one-shot in time, not one-shot per event:
  ```ts
  requestAnimationFrame(() => {
    scrollToBottom("instant");
    setShowBanner(true);
    requestAnimationFrame(() => { isInitialScrollRef.current = false; });
    // …timer setup…
  });
  ```
- Or only set the guard when `container.scrollHeight > container.clientHeight`.

Low-impact (only manifests on short or already-bottom channels), but easy to fix.

### B. 🟡 `bannerModeRef` is a ref, not state — banner text relies on a piggy-backed re-render
`bannerText` is computed during render from `bannerModeRef.current`. Today this is fine because every transition that changes the mode also calls `setUnreadInfo`/`setShowBanner`, triggering a render. If a future edit ever sets the mode without also calling a setter, the banner will show stale arrow/text with no warning.

**Suggested:** promote to `useState<BannerMode>("catchup")`. The single-state-update batching cost is negligible and the invariant becomes self-enforcing. Not required for this PR.

### C. 🟢 Nit — `handleMarkAsRead` swallows ack errors silently
`api.ackMessage(...).catch(() => {})` — consistent with the rest of the file, but if the server ack fails the sidebar/local state will diverge until next event. Consider at minimum `console.warn`. Non-blocking, matches existing pattern.

### D. 🟢 Nit — `bannerModeRef` reset on channel switch but not on dismiss-via-scroll
After live mode → user scrolls to bottom → `unreadInfo=null`, `showBanner=false`, but `bannerModeRef.current` stays `"live"`. If new messages arrive while still scrolled up… mode is still "live", which is actually correct. So this is fine — flagging only to confirm the design is intentional.

---

## New Code — Fresh Findings

1. **Effect ordering on channel open — verified safe.** The snapshot effect and the fetch effect both depend on `[channelId]`. React runs them top-to-bottom, so the `snapshotChannelOpen` call lands before `fetchMessages().then(...)` reads `channelOpenReadIds[channelId]`. The `getState()` access inside `.then` is correct (avoids stale closure).

2. **`snapshotChannelOpen` only fires when channel was unread.** Good — prevents producing a `NEW` divider on a fully-read channel.

3. **`removeChannel` now also strips `channelOpenReadIds`.** Good cleanup, prevents memory leak on channel deletion.

4. **`isGroupStart={showDivider || isGroupStart}`** — neat: forces the first post-divider message into its own group visually. ✅

5. **`position: "relative"` added to `listStyle`** — used so… actually the banner is rendered as a **sibling** to the scroll container (outside the `<div ref={scrollContainerRef}>`), not inside it. So `position: relative` on `listStyle` isn't doing anything for the banner. Either remove it or move the banner inside the scroll container if sticky-over-messages was the intent. Currently it sits below the list in the flex column — works, but the relative position is dead code.

6. **Gateway subscription auto-ack still in place.** Comment correctly documents the dual ack path (gateway for active-channel-bottom; MessageList for scroll/explicit). No race observed: both call `api.ackMessage` with monotonically increasing ids; server should be idempotent on duplicate/older ids.

7. **Banner accessibility:** `role="button" tabIndex={0}` on the outer banner div is good, but there's no `onKeyDown` handler — Enter/Space won't trigger it. Minor a11y gap (matches codebase patterns, non-blocking).

---

## Approval

✅ **Approve with minor follow-ups.** R1 must-fix items are all resolved with sensible patterns. Items A/B/C/E/G are quality-of-life improvements — fine to land as a follow-up PR or squash into this one. No regressions detected vs R1.
