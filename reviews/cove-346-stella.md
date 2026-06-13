# Stella Round 2 Re-review — kagura-agent/cove PR #346

## 1. Summary

Since Round 1, the author added explicit entry-state tracking for unread indicators, top-of-list NEW separator fallback cases, a never-read path, a top banner with a Mark as Read action, and a new bottom pill for real-time messages while scrolled up. The client build passes (`pnpm -F @cove/client build`).

Overall, the main Round 1 correctness holes are materially improved: the NEW separator now renders when the saved read cursor is not in the loaded window, never-read channels now show indicators, and Mark as Read now directly calls the ack API.

I would rate this **⚠️ Needs Changes** rather than Ready because one Round 1 timing problem is only partially fixed: the banner still is not dismissed by the scroll-to-bottom path when the component programmatically restores/lands at bottom, because the scroll handler explicitly ignores those programmatic scroll events. There are also a few non-blocking regressions/cleanup items in the new code.

**Rate: ⚠️ Needs Changes**

## 2. Previous Issues Status

### C1 — NEW line unreachable when `lastReadIdx === -1`

**Status: ✅ Fixed**

The new render logic handles the missing-cursor case by rendering the separator before the first loaded message:

- `lastReadIdx === -1` now sets `showNewLine=true` and `showTopBanner=true` during unread computation (`MessageList.tsx:218-225`).
- Rendering computes `isFirstUnread` with the fallback `i === 0 && (!lastReadId || !lastReadIdInMessages)` (`MessageList.tsx:623-630`).

That addresses the previous unreachable condition where `prev.id === lastReadId` could never match.

### C2 — No indicators for never-read channels (`lastReadId = null` / missing cursor)

**Status: ✅ Fixed**

The store exposes missing/null read cursors as `undefined`, and the new unread computation treats that as a never-read channel:

- `if (!lastReadId) { ... all messages are unread ... }` sets count, NEW line, and banner (`MessageList.tsx:208-215`).
- The render fallback places the separator before the first message for this case (`MessageList.tsx:625-630`).

This matches the claimed fix for never-read channels, assuming the intended client representation for `null` remains “no `readStates[channelId]` entry”.

### C3 — Top banner persists forever on bottom-entry / scroll restore suppresses scroll events

**Status: ⚠️ Partially Fixed**

The banner now has an explicit **Mark as Read** action, so it is no longer literally stuck forever (`MessageList.tsx:582-596`). However, the original scroll-timing problem is still present for the “scroll to bottom” dismissal path:

- Programmatic restore/entry scroll sets `restoringRef.current = true` (`MessageList.tsx:286-299`, `MessageList.tsx:457-460`).
- The scroll handler returns early while restoring (`MessageList.tsx:320-322`).
- The only automatic scroll-handler dismissal of the top banner is inside that skipped handler (`MessageList.tsx:328-331`).

So if channel entry restores or scrolls directly to bottom, the code still does not clear the banner via the bottom condition. The user can click Mark as Read, which is an improvement, but the claimed “dismissed on user scroll-to-bottom” behavior is not robust when the user is already at bottom and there is no further downward scroll possible.

Recommendation: after any programmatic scroll/restore completes, if the container is near bottom and the user action was intended to mark/read/dismiss, explicitly clear the banner/pill in the same path rather than relying only on the suppressed scroll listener. If the product spec wants the entry banner to stay visible until Mark as Read, then update the implementation/spec and tests to make that explicit.

### Nova-1 — Mark as Read does not actually call ack

**Status: ✅ Fixed**

The Mark as Read control now calls both local read-state update and the ack API for the latest non-pending message:

- `useReadStateStore.getState().markRead(channelId, lastMsg.id)`
- `api.ackMessage(channelId, lastMsg.id)`

See `MessageList.tsx:584-590`.

One caveat: channel entry still auto-acks in the existing fetch/cache paths (`MessageList.tsx:393-404`, `MessageList.tsx:429-438`), so Mark as Read may often be a redundant ack rather than the first ack. That is existing behavior around the new feature, but worth clarifying in the product semantics.

## 3. New Issues

### N1 — Banner dismissal still relies on suppressed scroll events in programmatic bottom-entry cases

**Severity: Medium**

This is the remaining part of C3, but I am listing it as the main actionable Round 2 issue because the fix commits added banner state without closing the scroll/restore gap. The code clears the banner only inside the passive scroll handler or Mark as Read. Programmatic scroll-to-bottom intentionally suppresses that handler, so bottom-entry state and banner state can diverge.

Suggested fix: centralize “reached bottom” side effects in a helper, e.g. `handleReachedBottom({ userInitiated })`, and call it from both the scroll handler and relevant click/programmatic paths according to the final spec.

### N2 — `lastReadIdInMessages` is recomputed for every rendered message

**Severity: Low**

Inside `messages.map`, the code calls `messages.some(...)` for every message (`MessageList.tsx:623-624`), making separator rendering O(n²). With the current page size this is unlikely to be catastrophic, but the list supports older-history prepends and can grow over time.

Suggested fix: compute `lastReadIdx` or `lastReadIdInMessages` once before the map, or memoize it with `useMemo`.

### N3 — New wrapper `<div>` around each lazy item may interfere with layout/lazy-list assumptions

**Severity: Low**

The fix wraps every `LazyMessageItem` in `<div key={msg.id}>` (`MessageList.tsx:632-647`) to insert the separator. Previously `LazyMessageItem` was the direct flex child. This adds an extra DOM node around every message, and the wrapper does not carry the placeholder’s `flexShrink: 0` style. It may be fine in practice, but it is a layout regression risk for the lazy placeholder/scroll-height logic.

Suggested fix: use a `Fragment` keyed by `msg.id`, or ensure the wrapper preserves the same flex sizing behavior as the previous direct child.

### N4 — New clickable controls are spans without keyboard/a11y semantics

**Severity: Low**

The banner action is a clickable `<span>` (`MessageList.tsx:582-597`) and the bottom pill is a clickable `<div>` (`MessageList.tsx:653-668`). These should be buttons or at least have role, tab index, and keyboard handlers.

## 4. Remaining Suggestions

- Add tests for the exact Round 1 regression matrix:
  - last read ID present in loaded messages;
  - last read ID older than the loaded window;
  - never-read channel/no cursor;
  - entering at bottom with unread banner;
  - Mark as Read calls ack and clears local indicators.
- Clarify the final product spec around whether the NEW line should clear on scroll-to-bottom. The PR description says it clears when `isNearBottom()` triggers, while `docs/unread-spec.md` says the NEW line does **not** disappear from scrolling and only clears on sending/leaving.
- Consider using `currentUserId` rather than only `pending-*` IDs for own-message detection if messages from the current user can arrive without the optimistic pending path.
- Consider de-duping `lastAckedIds` when Mark as Read calls `ackMessage`, to avoid redundant ack calls after entry auto-ack.

## 5. Positive Notes

- The Case B/C NEW separator fix is straightforward and addresses the core Round 1 rendering bug.
- Never-read channel behavior is now explicitly represented and much easier to reason about.
- Mark as Read now performs the expected local and remote read-state updates.
- The new `docs/unread-spec.md` is helpful; it gives future reviewers a concrete behavior contract to compare against.
- Build verification passed successfully.
