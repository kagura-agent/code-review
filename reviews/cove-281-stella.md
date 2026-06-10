# Review: kagura-agent/cove PR #281 — Stella

## Summary

This PR moves the WebSocket status indicator into a new `ConnectionBanner` component and removes the old inline chat-area status. The implementation is small and readable, and the new component has a reasonable basic accessibility shape (`role="status"`, `aria-live="polite"`). However, it does not implement the key behavior requested by #158 / the PR description: the banner is not an overlay, it pushes the whole app layout down, and the connected state never disappears/fades out. Because those are the main product requirements for this PR, I would hold merge until they are fixed.

## Critical Issues

1. **Connected banner remains permanently visible instead of disappearing/fading out**  
   - `packages/client/src/components/ConnectionBanner.tsx:17-31` always renders a `.connection-banner` for every status, including `connected`.
   - `packages/client/src/index.css:648-652` styles the connected state as a persistent normal bar.
   - The issue asks for `Connected: bar disappears smoothly (fade out)`, and the PR body claims a brief green flash/fade-out. As implemented, logged-in users permanently lose vertical space to a 24px server-name bar. This is a real user-facing behavior mismatch, not just a style preference.

2. **Banner is in normal document flow, not an overlay, so it pushes content down**  
   - `packages/client/src/App.tsx:49-56` changes the app root to a flex column and makes the main layout `flex: 1`.
   - `packages/client/src/App.tsx:253-260` renders `<ConnectionBanner />` before the grid layout.
   - `packages/client/src/index.css:636-646` gives the banner `height: var(--banner-height)` and `flex-shrink: 0`, with no `position: fixed`/`absolute` overlay behavior.
   - This directly contradicts #158: “Should not push down or overlap chat content — overlay style” and “thin, full-width banner at the very top of the app (above everything).” The old inline indicator only took space during non-connected states; the new connected banner permanently changes the app viewport.

## Product Impact

- Users will always see a top banner while connected, even though the intended Discord-style status is transient/hidden when healthy.
- The app’s usable vertical area is reduced by `--banner-height` across the sidebar, chat, member list, and footer layout. On mobile/small screens this is especially noticeable.
- The PR description says “fixed overlay” and “does not push down,” but the diff implements normal-flow layout. Future reviewers/users will expect different behavior from what ships.

## Suggestions

1. **Align the CSS token usage with the stated token standard.**  
   `packages/client/src/index.css:655-667` uses `#000` and fallback literal `18px` values. If this project enforces “no magic values,” consider adding tokens such as `--text-on-warning` / `--banner-icon-size` instead of literals.

2. **Prefer sharing the WebSocket status type.**  
   `ConnectionBanner.tsx:1` duplicates `"connecting" | "connected" | "disconnected"` from `useWebSocketStore.ts`. Exporting the store’s `WsStatus` type or defining it in a shared client type file would prevent future drift.

3. **Consider reduced-motion handling for the pulse/fade.**  
   If the final implementation keeps animation, a `@media (prefers-reduced-motion: reduce)` override would be a nice accessibility improvement.

## Positive Notes

- The component boundary is good: `ConnectionBanner` keeps the status presentation out of `App.tsx`.
- The old inline chat-area status was cleanly removed.
- The fallback server initial is simple and safe for normal guild names.
- The status region uses `role="status"` and `aria-live="polite"`, which is the right direction for connection-state announcements.

## Verification

- Reviewed PR metadata and diff with `gh pr view 281` / `gh pr diff 281`.
- Inspected the checked-out PR worktree.
- Attempted `pnpm -F @cove/client build` and `pnpm -F @cove/client lint`; both could not run because the worktree has no `node_modules` installed (`vite` / `eslint` not found). No build or lint result is claimed.

## Verdict

⚠️ Needs Changes
