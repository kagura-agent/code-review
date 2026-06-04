# Stella Review — kagura-agent/cove PR #191

## Summary
This PR replaces the single-line Ant Design `Input` with a native auto-resizing `textarea`, adding Enter-to-send and Shift+Enter newline behavior. The core implementation is small and mostly matches the product goal, and CI is green (`test` and staging deploy checks passed). However, the raw Enter handler does not account for IME composition, which can break message entry for Chinese/Japanese/Korean users. Rate: ⚠️ Needs Changes

## Critical Issues
1. **IME composition Enter can prematurely send messages** — `packages/client/src/components/MessageInput.tsx:42-46`
   - The new `onKeyDown` sends whenever `e.key === "Enter" && !e.shiftKey`. During IME composition, users often press Enter to confirm a candidate; without checking `e.nativeEvent.isComposing` (and/or composition state), this can submit an incomplete message instead of selecting the composed text.
   - This is especially relevant for Cove’s chat UX and CJK input. Ant Design’s previous input abstraction may have handled more browser/key edge cases; the native textarea now owns that behavior.
   - Suggested fix: return early when composing, e.g. guard with `if (e.nativeEvent.isComposing) return;` before submit logic. If browser coverage is a concern, track `onCompositionStart`/`onCompositionEnd` state as well.

## Product Impact
- Positive: Multi-line input is a clear chat UX improvement and matches Discord-style behavior: Enter sends, Shift+Enter inserts a newline.
- Risk: The IME issue would make normal typing frustrating for CJK users by sending text before candidate selection is complete.
- Minor UX/accessibility concern: `outline: "none"` on the textarea (`MessageInput.tsx:18`) removes the native focus indicator without replacing it. Keyboard users may not be able to tell where focus is. Consider adding an explicit focus style/class rather than suppressing focus affordance entirely.
- Minor failure-state concern: on send failure, `setContent(text)` restores the message but the textarea height remains reset to `auto` (`MessageInput.tsx:52-63`) until the next edit. A failed multi-line send may reappear visually collapsed. Not blocking, but worth smoothing.

## Suggestions
1. Add a composition guard to `handleKeyDown`, and manually verify with a Chinese/Japanese/Korean IME that Enter selects candidates while non-composing Enter still sends.
2. Consider replacing inline textarea styles with a CSS class so hover/focus states can be expressed cleanly, including a visible focus ring using existing design tokens.
3. When restoring content after `sendMessage` failure, resize the textarea on the next frame after state restoration, or keep the original draft value/height until the request succeeds.
4. If this component gets tests later, the highest-value coverage would be keyboard behavior: Enter submits, Shift+Enter does not submit, empty/whitespace content does not submit, and composition Enter does not submit.

## Positive Notes
- The change is appropriately scoped to `MessageInput.tsx` and keeps existing typing throttling and send error recovery behavior.
- Auto-resize is simple and bounded with `maxHeight: 200` plus scrolling, avoiding unbounded layout growth.
- Resetting focus after submit preserves fast chat flow.
- CI status on the PR is green, and the PR description accurately reflects the implemented behavior.
