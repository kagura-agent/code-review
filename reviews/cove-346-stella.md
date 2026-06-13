# Stella Review — PR #346 Round 3

## 1. Summary

The Round 2 blocker has been addressed: the NEW separator render path no longer does `messages.some()` inside every `messages.map()` iteration. The bottom pill is now inside the `position: relative` wrapper, and the top banner now renders a `+` suffix when the visible page is only a lower bound.

I re-reviewed the current diff fresh. The PR is much closer, and the previous blocker is fixed. However, I found one remaining correctness issue around stale cached message windows: unread indicators are computed once from whatever messages are currently in the store, before the fresh fetch effect runs. If the cached page is stale and does not contain the snapshotted `lastReadId`, the code treats every visible message as unread and then locks that wrong result for the visit.

Build check: `pnpm -F @cove/client build` passes.

**Rating: ⚠️ Needs Changes**

## 2. Previous Issues Status

### R2 Blocker

- ✅ **N1: O(N²) render — `messages.some()` inside `messages.map()`**
  - Fixed. `lastReadIdInMessages` is now computed once before `messages.map()` at `MessageList.tsx:610-613`, making this O(N) instead of O(N²).

### R2 Medium

- ✅ **N-Nova-1: `entryUnreadCount = messages.length` lies for Case B/C**
  - Mostly addressed in the UI. The code still only knows the loaded page count, but it now renders `+` when `entryUnreadCount >= messages.length` (`MessageList.tsx:581`), so users see e.g. `50+ new messages` instead of a falsely precise `50 new messages`.

- ✅ **N-Nova-2: Bottom pill positioned outside `position: relative` container**
  - Fixed. The bottom pill now renders inside the relative flex wrapper (`MessageList.tsx:653-672`).

### R2 Low / Suggestions

- ⚠️ **Mark as Read no-ops on pending last message**
  - Still possible: if the final message is pending, the handler skips ack (`MessageList.tsx:587-591`) but still dismisses the banner/NEW line. This is a low-probability edge case and was already a suggestion.

- ⚠️ **Mark as Read ack order / fire-and-forget**
  - Still fire-and-forget (`api.ackMessage(...).catch(() => {})`). UI updates optimistically without retry/error handling.

- ⚠️ **Bottom pill does not explicitly ack**
  - Still true. Clicking the pill scrolls and clears the pill only (`MessageList.tsx:663-666`). There may be active-channel auto-ack behavior elsewhere, but this handler itself does not mark/ack.

- ❌ **PR description stale: says Jump ↑ instead of Mark as Read**
  - Still stale in `gh pr view`: the PR description says `"{count} new messages — Jump ↑"` and clicking `Jump` scrolls to the NEW separator, while the implementation/spec now says `Mark as Read`.

- ❌ **Extra div wrapper per message**
  - Still present (`MessageList.tsx:632`). This can affect layout/virtualization assumptions; a `Fragment` would avoid adding DOM nodes.

- ❌ **a11y: clickable span/div instead of button**
  - Still present. The top banner action is a clickable `<span>` (`MessageList.tsx:582-597`), and the bottom pill is a clickable `<div>` (`MessageList.tsx:653-672`). Keyboard users and assistive tech do not get native button semantics.

- ❌ **No tests**
  - Still no tests in the diff.

- ❌ **Scroll handler throttling**
  - Still not addressed. The scroll handler can call React state setters and update maps directly on every scroll event.

### R1 Issues

- ✅ **C1: NEW line unreachable when `lastReadIdx = -1`**
  - Fixed. Missing `lastReadId` now renders the separator before the first loaded message (`MessageList.tsx:626-629`).

- ✅ **C2: No indicators for never-read channels**
  - Fixed. `!lastReadId` sets count and shows both entry indicators (`MessageList.tsx:209-215`).

- ✅ **C3: Banner persistence on bottom-entry**
  - Still fixed per current spec. Programmatic restore/scroll-to-bottom suppresses scroll handling via `restoringRef`, so the banner is not immediately cleared by the entry auto-scroll.

- ✅ **Nova-1: Mark as Read does not call ack**
  - Fixed. The handler updates the local read state and calls `api.ackMessage()` for the latest non-pending message (`MessageList.tsx:587-590`).

## 3. New Issues

### Medium — Unread indicators can be computed from stale cached messages and then frozen incorrectly

`MessageList.tsx:204-242` computes unread state once as soon as `messages` exists, and records `unreadComputedForRef.current = channelId`. This runs before the later fetch effect (`MessageList.tsx:365+`) has a chance to replace stale cached messages.

Failure case:

1. The channel has cached messages in the store, but the cache is stale.
2. The snapshotted `lastReadId` is newer than, or otherwise absent from, that cached page.
3. The unread computation runs first, hits `lastReadIdx === -1`, and assumes `lastReadId not in loaded messages` means "all visible messages are unread" (`MessageList.tsx:218-225`).
4. It sets `unreadComputedForRef.current = channelId`.
5. The fresh fetch later loads the actual current page, but unread computation is skipped forever for this channel entry.

Result: the banner count and NEW separator position can be wrong for the entire visit, including showing `50+ new messages` before the first cached message even when the user may already have read through a newer message.

Suggested fix: do not finalize/freeze the entry unread computation until the current channel's initial fetch/cache freshness decision is resolved. Alternatively, allow recomputation when the message set changes from stale cache to the fetched current page, especially when the prior computation was based on `lastReadIdx === -1`.

## 4. Remaining Suggestions

- Use real `<button type="button">` elements for `Mark as Read` and the bottom pill, with visible focus states.
- Replace the per-message wrapper `<div key={msg.id}>` with a keyed `Fragment` unless the wrapper is intentionally required for layout.
- Add focused tests for:
  - `lastReadId` in page → separator after that message
  - `lastReadId` missing because older than page → separator before first message and `+` count
  - never-read channel → separator before first message and banner
  - stale cache replaced by fresh fetch → unread computation is not frozen incorrectly
  - Mark as Read calls `markRead` and `ackMessage`
- Consider throttling or RAF-batching the scroll handler's state/map updates.
- Update the PR description to match the current behavior (`Mark as Read`, not `Jump ↑`).

## 5. Positive Notes

- The O(N²) issue was fixed cleanly with a single precomputed `lastReadIdInMessages` scan.
- The current implementation now covers the important missing-cursor cases for the NEW separator.
- The `+` suffix is a good pragmatic improvement when only the loaded page count is known.
- The client build passes successfully.
