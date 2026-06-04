# 🌠 Nova — Round 3 Review: PR #191 (cove)

**PR**: multi-line message input with auto-resize (Shift+Enter)
**Rating**: ✅ **Ready to ship** (with 2 minor non-blocking notes)

---

## 1. Summary

All three R2 escalated issues have been addressed in this round, each with a clean, targeted fix:

- Focus ring restored via `:focus-visible` box-shadow in a new `MessageInput.css`.
- Height auto-restoration via `useLayoutEffect` keyed on `content` — covers the send-failure rollback path.
- Mobile path gated on `(pointer: coarse)`; `handleKeyDown` becomes a no-op on touch, so Enter inserts a newline. The send button lost the `mobile-only` class and is now always visible, giving touch users a way to submit.

The diff is small (+51/-17), focused, and the rest of the implementation (composition guard, throttled typing, maxLength=2000, flex-end alignment for bottom-anchored button) is intact.

---

## 2. Previous Issues Status

### R2-1 🔴 → ✅ Focus ring removed (WCAG 2.4.7)
**Fixed.** New `MessageInput.css`:
```css
.message-textarea { outline: none; }
.message-textarea:focus-visible { box-shadow: 0 0 0 2px var(--accent); }
```
- Uses `:focus-visible` (keyboard-only, no ring on click) — correct modern pattern.
- 2px ring on `--accent` is a clear, theme-consistent indicator.
- Class is applied via `className="message-textarea"`.
- WCAG 2.4.7 (Focus Visible) satisfied.

### R2-2 🔴 → ✅ Height not restored on send failure
**Fixed.** Replaced ad-hoc height mutation with:
```ts
useLayoutEffect(() => {
  const ta = textareaRef.current;
  if (!ta) return;
  ta.style.height = "auto";
  ta.style.height = `${ta.scrollHeight}px`;
}, [content]);
```
- On successful send: `setContent("")` → effect runs → height collapses to single line.
- On failure: catch block calls `setContent(text)` → effect runs → height re-expands to match restored text.
- `useLayoutEffect` (not `useEffect`) prevents the one-frame flicker. Correct choice.
- The previous imperative height code is gone, so there's a single source of truth.

### R2-3 🔴 → ✅ Mobile multi-line impossible
**Fixed.** Module-level capability check + early return:
```ts
const isTouchDevice =
  typeof window !== "undefined" &&
  matchMedia("(pointer: coarse)").matches;
...
function handleKeyDown(e) {
  if (isTouchDevice) return;
  if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) { ... }
}
```
- On touch devices, the keydown handler returns immediately → browser default applies → Enter inserts a newline. ✅
- Send button is no longer `mobile-only`, so touch users have a tap target. ✅
- SSR-safe via `typeof window` guard.

---

## 3. Critical Issues

**None.** No new blockers introduced.

---

## 4. Product Impact

- Desktop UX: unchanged behavior (Enter sends, Shift+Enter newline) + a proper focus ring back. Net positive.
- Mobile UX: Enter now inserts a newline; send is via the always-visible button. This matches Discord/Slack mobile conventions. Net positive.
- Accessibility: WCAG 2.4.7 restored; `aria-label="Message"` already present.
- Failure recovery: textarea visually matches its content on send-failure rollback — no more "collapsed but full of text" state.

---

## 5. Suggestions (non-blocking)

1. **`isTouchDevice` is captured once at module load.** It won't react to:
   - A user pairing a Bluetooth keyboard mid-session on iPad/Android, where `(pointer: coarse)` still matches but the user now expects Enter-to-send.
   - Hybrid devices (Surface). `(pointer: coarse)` is true when the touch screen is the primary pointer.

   Realistically this matches Discord's behavior too, so it's fine to defer. If you want to be slicer, subscribe to the MediaQueryList inside an effect, or fall back on `(any-pointer: fine)` to detect "has a real keyboard." Not blocking.

2. **`paddingBottom` formula stacks `var(--space-sm)` on top of safe-area + keyboard-offset.** Verify on iOS that the input doesn't sit too high above the home indicator now that the wrapper lost its fixed `var(--footer-height)`. Probably fine, but worth a quick eye-check on a real device.

3. **Optional micro-polish:** consider `box-sizing: border-box` and an explicit `max-width: 100%` on `.message-textarea` to harden against any parent layout regressions. Current inline style doesn't set `box-sizing`; if the global reset already does, ignore this.

4. **Test coverage:** R2 mentioned 148 passing tests; consider one assertion that on `(pointer: coarse)` the keydown handler does NOT call `sendMessage`. A tiny vitest with `matchMedia` mocked would lock in the fix permanently. Not blocking for ship.

---

## 6. Positive Notes

- Clean, minimal diff — every line earns its place.
- `useLayoutEffect` chosen correctly over `useEffect` to avoid layout flash.
- `isComposing` guard preserved (CJK IME safe).
- `:focus-visible` is the right tool — keyboard-only ring, no click ring noise.
- Removing `mobile-only` from the send button at the same time as enabling mobile-newlines shows the change was thought through end-to-end, not bolted on.
- Top-level `isTouchDevice` constant is cheap, SSR-safe, and avoids re-evaluating on every keystroke.

---

**Verdict: ✅ Ready to ship.** All R2 blockers resolved with appropriate fixes; remaining notes are polish, not blockers.
