# Stella Review — kagura-agent/cove PR #240 — Round 2

## R1 Issue Status

1. **C1: Fixed grid row clips multi-line input** — ✅ Fixed  
   `packages/client/src/App.tsx:51` now uses `gridTemplateRows: "1fr minmax(var(--footer-height), auto)"`, so the footer row can grow beyond the base footer height. `MessageInput` also moved vertical spacing into the textarea/button margins (`MessageInput.tsx:20-23`, `MessageInput.tsx:95-99`), which lets the grid row expand with multi-line input instead of clipping inside a fixed row.

2. **C2: iOS safe-area / keyboard padding squeezed by fixed row** — ✅ Fixed  
   The same `minmax(var(--footer-height), auto)` row fix (`App.tsx:51`) means `chatFooter`'s dynamic bottom padding (`App.tsx:55`) can increase the row's auto size instead of being squeezed into a fixed 52px row.

3. **Token semantic misuse: spacing tokens for sizes, font-size for dots** — ⚠️ Partially Fixed  
   The worst cases were improved: status dots now use `--status-dot-size` (`index.css:56-58`, `StatusDot.tsx:10`, `App.tsx:61-63`), large emoji/icon cases have dedicated size tokens (`index.css:57-59`), and control/button sizes use control tokens (`index.css:49-54`, `MessageInput.tsx:97`).  
   However, spacing tokens are still being used as non-spacing semantic values: radii in `ChatMarkdown.tsx:26`, `ChatMarkdown.tsx:85`, `MemberList.tsx:13`, badge radii in `MemberList.tsx:18` / `MessageItem.tsx:38`, and typing-dot dimensions in `MessageList.tsx:32-35`. Since this was explicitly called out in R1, it should be finished with dedicated `--radius-*` and `--typing-dot-size`-style tokens rather than left as spacing-token aliases.

4. **Safe-area background color gap** — ✅ Fixed  
   `chatFooter` now owns both the safe-area/keyboard padding and a `var(--bg-secondary)` background (`App.tsx:55`), matching the `MessageInput` wrapper background (`MessageInput.tsx:14`) so the padded area should not expose the page background.

5. **Empty CSS rule dead code** — ✅ Fixed  
   The previous empty mobile grid rule was replaced by real `.app-layout`, `.chat-body-cell`, and `.chat-footer-cell` mobile declarations (`index.css:470-510`). No empty selector remains in that block.

6. **MemberList needs explicit `gridColumn: 3`** — ✅ Fixed  
   `MemberList` now explicitly sets `gridColumn: 3` and spans both rows with `gridRow: "1 / -1"` (`MemberList.tsx:11`).

## New Issues

1. **Mobile sidebar content can scroll underneath the fixed UserBar.**  
   On mobile, `.sidebar-panel` is fixed from `top: 0` to `bottom: 0` (`index.css:474-480`), while `.sidebar-footer-cell` is a separate fixed element at `bottom: 0` with `height: var(--footer-height)` (`index.css:489-497`). Because the `UserBar` is no longer inside the `Sidebar` flex layout and the sidebar list has no bottom padding/reserved space (`Sidebar.tsx:13`, `Sidebar.tsx:88-118`), the last channel(s) or the add-channel form can be hidden behind the fixed footer. Reserve footer space on mobile, e.g. by setting the fixed `.sidebar-panel` bottom to `var(--footer-height)` or adding equivalent bottom padding to the scroll container.

## Summary & Verdict

The main blocking R1 layout issue was addressed correctly: the footer grid row can now grow for multi-line input and safe-area/keyboard padding. The safe-area background and member-list placement fixes are also solid.

One R1 token-cleanup item remains only partially addressed, and there is a fresh mobile-sidebar regression risk from splitting `UserBar` into a separate fixed footer without reserving scroll space in the sidebar body.

**Rate: ⚠️ Needs Changes**
