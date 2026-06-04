# Vega - PR #191 R2 Review

## 1. Summary
Round 2 of the multi-line input PR. The IME composition issue has been correctly addressed, which is a great fix for CJK users. However, several accessibility, mobile UX, and state restoration issues from Round 1 were not addressed and must be escalated. 

## 2. Previous Issues Status
* 🔴 **IME composition Enter sends prematurely**: **FIXED** (`!e.nativeEvent.isComposing` added).
* 🔴 **outline: "none" removes focus ring**: **NOT FIXED** (Escalated from 🟡). The textarea still has `outline: "none"`, destroying keyboard accessibility.
* 🔴 **Mobile UX (No Shift on Mobile)**: **NOT FIXED** (Escalated from 🟡). The logic `if (e.key === "Enter" && !e.shiftKey)` will trigger a send on mobile when the user presses the software keyboard's "Return" key. Mobile users cannot insert newlines.
* 🔴 **Height not restored on send failure**: **NOT FIXED** (Escalated from 🟡). `handleSubmit` sets `ta.style.height = "auto"` synchronously before the API call. If the API call fails, `setContent(text)` restores the value but the height remains collapsed.

## 3. Critical Issues
* **Mobile UX Regression**: Intercepting a raw "Enter" on a textarea means mobile soft-keyboards cannot insert newlines at all. We need to either detect touch/mobile devices and disable the Enter-to-send behavior, or use a separate pattern for mobile.
* **Accessibility Failure**: `outline: "none"` is an WCAG violation. You need a custom focus style if you don't like the default outline, e.g., `:focus { box-shadow: ... }`.
* **State Sync**: Manually manipulating `style.height` via DOM works for typing, but breaks on asynchronous restores. A `useEffect` on `content` might be a more resilient way to trigger the resize calculation.

## 4. Product Impact
* **Accessibility**: Keyboard users will not know when the input is focused.
* **Mobile**: Multi-line is fundamentally broken on mobile.
* **Error Recovery**: Annoying UI bug when a message fails to send.

## 5. Suggestions
* Replace `outline: "none"` with an appropriate focus ring, or move the styles to a CSS class and handle `:focus-visible`.
* For mobile, you might need to check if the device is mobile/touch and skip the `e.preventDefault() + handleSubmit()` on bare Enter, allowing the software keyboard's Enter to work naturally. Mobile users can tap the Send button to submit.
* Move the height auto-adjustment logic into a `useLayoutEffect` that depends on `content`, so it correctly resizes when `content` changes programmatically (e.g. restoring on failure).

## 6. Positive Notes
* Thank you for fixing the IME issue (`!e.nativeEvent.isComposing`), this is critical for global users.

## Rate
❌ Major Issues (Needs Changes)