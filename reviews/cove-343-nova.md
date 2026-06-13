# 🌠 Nova — Review of cove#343: Right-click context menu w/ delete

**Verdict: ✅ Ready** (with a couple of important notes the author should be aware of before/after merge)

---

## 1. Summary
Adds a Discord-style context menu (`Copy Text` / `Copy Message ID` / `Delete Message`) wired into `MessageList` → `MessageItem`. Delete uses a two-step "click again to Confirm" pattern, only shows for own messages, and hits the existing `DELETE /channels/:id/messages/:id`. Code is small (+178/-2), well-scoped, no schema or server changes. Functionally ready.

## 2. Critical Issues
None blocking. Two important caveats worth surfacing:

- **Server-side delete authorization is permissive (pre-existing, NOT introduced here).** Reading `packages/server/src/routes/messages.ts` confirms:
  ```
  // TODO: check MANAGE_MESSAGES permission once permission system is implemented (#113)
  // For now, any guild member can delete any message in channels they have access to
  ```
  The PR's `isOwnMessage` gate is **client-side only**. Any guild member can still call `api.deleteMessage(channelId, otherUserMsgId)` from devtools and successfully delete someone else's message. This is fine *for this PR* (it doesn't regress the existing posture, and #113 is the tracking issue), but the PR description's "仅自己的消息可删" wording overstates the guarantee. Recommend either (a) tightening it in the description, or (b) adding a `if (existing.author_id !== user.id) return 403` short-circuit in the server route as a defense-in-depth follow-up before #113 lands.

- **No user-visible error on delete failure.** `handleDelete` catches the API error with `console.error` and still calls `onClose()`. If the server rejects (network drop, 403, race with WS gone), the message stays on screen with zero feedback — user is likely to retry and get confused. A toast/notification on failure would close the loop.

## 3. Product Impact
- **Power users get what they expect** (Discord parity for right-click). Good.
- **Edge case — touch / mobile / Android WebView:** `contextmenu` doesn't fire reliably on touch devices; this feature is implicitly desktop-only. If cove is shipped to the mobile node, there's no long-press fallback. Not a regression, just a gap.
- **Clipboard API:** `navigator.clipboard.writeText` requires a secure context (HTTPS or localhost). On `http://` LAN/IP deployments the promise rejects silently (caught with `.catch(() => {})`), giving the user no clue the copy failed. Worth a toast or at least not swallowing the error.
- **Markdown leakage:** `Copy Text` copies the raw `message.content` (Markdown source). For most use cases that's correct, but worth confirming this matches user expectation (vs. rendered plain text).
- **No XSS surface introduced.** Menu items are static strings; user content is only passed to `clipboard.writeText` (string sink, not HTML). ✅

## 4. Suggestions (non-blocking)

**Rendering / UX**
- `useEffect` for viewport adjustment causes a one-frame flash at the original (possibly off-screen) coords before re-positioning. Swap to `useLayoutEffect` to eliminate the flicker.
- Two-step confirm has **no timeout and no visual reset.** If the user hovers off after the first click and comes back 10s later, one more click silently deletes. Either auto-revert `confirmDelete` after ~3s, or add a clearer visual state ("Click again to confirm").
- `z-index: 1000` collides with Antd's default modal/popover stack (Antd uses 1000+ for `Modal`, `Drawer`). If a modal is ever open behind the menu, the menu may render under it. Bump to e.g. 1500 or align with whatever the app uses for top-layer overlays.
- Menu is rendered inline inside `MessageList` rather than via a portal (`createPortal` → `document.body`). `position: fixed` saves you from overflow clipping, but stacking context bugs are easier to hit this way. Portal is the safer pattern.

**Accessibility (the weakest area)**
- No ARIA: should have `role="menu"` on the container, `role="menuitem"` on items, `aria-label="Message actions"`.
- No keyboard nav: can't `Tab` / Arrow between items, no `Enter` to activate, no focus moved into menu on open. Pure mouse UI today.
- Items are `<div onClick>` rather than `<button>` — no native keyboard activation, no focusable-by-default.
- `tabIndex={-1}` on container + focus-on-mount + arrow-key handler would close most of this gap.

**State / hooks**
- `handleContextMenu` in `MessageList` depends on the whole `pendingStatus` object, so it changes identity whenever *any* message's pending state flips, re-rendering every `MessageItem`. Either select only the relevant key on demand, or read `pendingStatus` from a ref inside the callback.
- The `mousedown`-to-close listener races subtly with opening on right-click: on most platforms `mousedown` fires before `contextmenu`, but since the listener is registered in a `useEffect` after the menu mounts, this happens to work. Worth a comment so a future refactor doesn't break it. Alternatively, use `pointerdown` and check `e.button !== 2` to ignore right-click.
- Right-clicking a different message while a menu is open: works (mousedown closes old → contextmenu opens new), but it'd be cleaner to detect "contextmenu while menu open" in the parent and replace state directly.

**Misc**
- `border-radius: var(--space-xs)` — semantically that token is for spacing, not radius. Minor token misuse.
- `onClose()` is called in `handleDelete` even when the API call is still pending (it `await`s, then closes). Fine, but if the delete is slow the menu disappears and the user has no idea anything happened until the WS event arrives.

## 5. Positive Notes
- **Clean separation of concerns.** Menu is a standalone component with a tight `Props` interface; `MessageList` owns coordinates + lifecycle; `MessageItem` is a passive forwarder of `onContextMenu`. Easy to test and easy to extend (Reply / Edit / Pin can drop in).
- **Event-listener cleanup is correct.** `mousedown` and `keydown` are both removed in the effect teardown — no leak.
- **Pending messages are excluded from the menu** at the *parent* level, which is the right place. Avoids the temptation to call DELETE on a not-yet-persisted message id.
- **Reuses the existing `DELETE` endpoint and existing `MESSAGE_DELETE` WS path** — no new server surface, no new dispatch logic, no migration. Minimal blast radius.
- **Viewport-edge clamping** is implemented and handles all four edges with an 8px margin. Most "context menu" PRs ship without this.
- `onContextMenu={(e) => e.preventDefault()}` on the menu itself prevents the browser's native menu from popping on top — small detail, easy to forget.
- Two-step delete confirm is a thoughtful safety choice vs. the "type DELETE to confirm" overkill or the destructive single-click.

---

**TL;DR:** Ship it. The only thing I'd ask before next iteration is (1) a follow-up issue to harden server-side delete auth (or land #113), (2) error feedback for failed deletes/copies, and (3) a separate a11y pass for ARIA + keyboard nav. None of those block this PR.
