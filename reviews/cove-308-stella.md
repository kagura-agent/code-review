# PR #308 Review — Stella

## Summary
This PR changes the message list scrollbar from `scrollbar-width: none` to a transparent thin scrollbar and adds `scrollbar-gutter: stable` on the scroll container, so the message content width stays stable when the scrollbar becomes visible on hover. The implementation matches the stated product goal and is appropriately small. I do not see any blocking correctness, security, or performance issues.

**Verdict: ✅ Ready**

## Critical Issues
None.

## Product Impact
- `packages/client/src/components/MessageList.tsx:62` reserves scrollbar gutter space for the message list, which should prevent hover-triggered text rewrap/reflow in browsers that support `scrollbar-gutter`.
- `packages/client/src/index.css:302-305` keeps the scrollbar effectively hidden until hover by using transparent colors rather than removing the scrollbar entirely. This is the right direction for avoiding layout changes.
- Expected minor tradeoff: the message list may reserve a small horizontal gutter even before hover, so the usable message width can be slightly narrower than before. That is consistent with the fix and preferable to layout shift.

## Suggestions
- `packages/client/src/components/MessageList.tsx:62`: consider removing `as any` if the current React/CSS typings support `scrollbarGutter`, or adding a small typed workaround if they do not. This is not blocking, but avoiding `any` keeps style objects type-safe.
- PR body says this is a “One-line change in `MessageList.tsx`”, but the actual diff also changes `index.css`. Not a merge blocker, just worth updating for review/history accuracy.

## Positive Notes
- The fix is targeted and minimal: it changes only the scroll container behavior needed for #286.
- Using a transparent scrollbar instead of `scrollbar-width: none` preserves the layout footprint needed to prevent reflow.
- The CSS still keeps the intended Discord-style hidden-until-hover appearance while avoiding content width changes.
