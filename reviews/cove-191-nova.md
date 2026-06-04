# Code Review: cove PR #191 — Multi-line message input

**Reviewer:** 🌠 Nova
**Verdict:** ⚠️ Needs Changes (minor)

## 1. Summary
Replaces antd `<Input>` with a native `<textarea>` to support multi-line composition (Shift+Enter newline, Enter to send), with `scrollHeight`-based auto-resize capped at 200px. Change is small (33/-15) and well-scoped to `MessageInput.tsx`. Build, typecheck, and 148 tests pass per PR description.

## 2. Critical Issues
None. No security, data-loss, or correctness blockers. XSS surface is unchanged (content is sent as text via `api.sendMessage`, no `dangerouslySetInnerHTML`).

## 3. Product Impact
- **Positive:** Achieves Discord-parity composition (Shift+Enter newline, auto-grow). Closes #182.
- **IME (CJK) regression risk — important for Kagura's users:** `handleKeyDown` fires Enter-to-send even when the user is composing in an IME (Pinyin/Japanese/Korean). Pressing Enter to *confirm* a candidate will instead *send the message*. This is a real, user-visible regression vs. antd `Input`/`onPressEnter`, which handles composition internally.
  - **Fix:** guard on `e.nativeEvent.isComposing` (and/or `e.keyCode === 229`):
    ```ts
    if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) {
      e.preventDefault();
      handleSubmit();
    }
    ```
- **Mobile UX:** Removing fixed `--footer-height` and switching `alignItems` to `flex-end` is correct for a growing textarea, but verify that any sibling layout that previously reserved `--footer-height` (message list bottom padding, scroll anchoring) still behaves — the footer is now variable height up to 200px + safe-area + keyboard offset.
- **Send button alignment:** With `alignItems: "flex-end"` the send button sits at the bottom of a tall composer. That matches Discord; just confirm the visual against the design.

## 4. Suggestions (non-blocking)
1. **Resize on programmatic clear:** After `setContent("")` in `handleSubmit`, you reset `ta.style.height = "auto"` — good. But `setContent` is async (state flush), so the textarea's `value` at that microtask is still the old text. In practice React re-renders before the next paint and the height-auto reset takes effect, but it's slightly fragile. Consider using a `useLayoutEffect` keyed on `content` to set height, which centralizes the logic and also covers the case where `content` is reset from elsewhere (e.g. channel switch).
2. **Auto-resize on mount / channel switch:** If `content` is ever preloaded (drafts), initial height will be 1 row until the user types. Same `useLayoutEffect` fixes it.
3. **maxLength UX:** `maxLength={2000}` silently truncates. With multi-line input this is easier to hit; a small char counter near the limit would be nice (follow-up).
4. **Accessibility:** Add `aria-label="Message"` to the textarea since there is no visible label, only a placeholder. Placeholder ≠ label for screen readers.
5. **Style nit:** Inline `padding: "8px 11px"` and `fontSize: 14` are hard-coded, while the rest of the file uses `var(--*)` tokens. Consider `var(--space-sm)` / a font-size token for consistency with the design system.
6. **Paste of huge text:** `scrollHeight` measurement on every keystroke is cheap, but pasting a 10k-char blob will hit `maxLength` truncation + a single resize — fine, just noting `maxHeight: 200` + `overflowY: auto` correctly contains it.
7. **Typing indicator:** `sendTypingThrottled` only fires when `value.trim()` is truthy; pressing Enter to insert a newline (via Shift+Enter) on otherwise-empty content won't trigger typing. Unchanged behavior, just noting.

## 5. Positive Notes
- Minimal, focused diff; no churn in unrelated files.
- Correct use of `flex-end` so the send button doesn't jump as the textarea grows.
- `paddingBottom` correctly composes `safe-area-inset-bottom` + `--keyboard-offset` + `--space-sm` — keeps iOS keyboard + notch handling intact.
- Preserves `maxLength`, `autoComplete="off"`, and the typing-throttle behavior.
- Resets height after send so the composer collapses back to one line.
- Native `<textarea>` avoids antd `TextArea`'s extra wrapper and keeps bundle/DOM lean.

## Recommended action
Land after adding the **IME composition guard** in `handleKeyDown` (one-line change). Everything else is polish / follow-up.
