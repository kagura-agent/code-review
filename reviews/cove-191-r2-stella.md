# 🌟 Stella Review — cove PR #191 Round 2

## 1. Summary

**Rate: ⚠️ Needs Changes**

Round 2 fixed the highest-risk regression: IME composition Enter no longer sends prematurely. The update also added `aria-label`, which improves screen-reader support.

However, three Round 1 issues remain unaddressed. Per the escalation rule, I’m not treating them as fresh optional nits: the removed focus ring and send-failure height recovery should be fixed before merge. Mobile multi-line behavior is still a product limitation; it can be handled as a follow-up only if the team explicitly accepts that mobile users cannot create multi-line messages in this implementation.

## 2. Previous Issues Status

1. 🔴 **IME composition Enter sends prematurely** — ✅ **Addressed**
   - Current code checks `!e.nativeEvent.isComposing` before sending:
     ```tsx
     if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) {
     ```
   - This prevents common CJK IME candidate confirmation from accidentally sending an incomplete message.

2. 🟡 **`outline: "none"` removes focus ring** — ❌ **Not addressed → escalated**
   - `textareaStyle` still contains:
     ```tsx
     fontFamily: "inherit", outline: "none",
     ```
   - There is no replacement `:focus` / `:focus-visible` style in this component, and inline style cannot express pseudo-classes. Keyboard users still lose visible focus indication.

3. 🟡 **Mobile UX: no Shift key, multi-line impossible** — ❌ **Not addressed → escalated**
   - The PR still maps plain Enter to send globally.
   - On mobile virtual keyboards, users typically do not have Shift+Enter, so this implementation still does not provide a reliable way to insert newlines on mobile.

4. 🟡 **Height not restored on send failure** — ❌ **Not addressed → escalated**
   - `handleSubmit()` clears content and collapses height before the network request:
     ```tsx
     setContent("");
     ta.style.height = "auto";
     ```
   - On failure, it restores text via `setContent(text)` but does not re-measure `scrollHeight`, so the textarea can remain collapsed with multi-line content restored.

Additional R1 suggestion:
- 🟢 **`aria-label="Message"`** — ✅ **Addressed**

## 3. Critical Issues

### 🟠 Escalated: focus indicator is still removed

The textarea is keyboard-focusable, but `outline: "none"` removes the browser’s default focus ring without replacing it. This is an accessibility regression from the native/antd input behavior.

**Why this matters:** keyboard and switch-device users cannot reliably tell where focus is. This is especially noticeable in a chat UI where the text field is the primary interaction point.

**Suggested fix:** move textarea styling to CSS/module class or add focus handlers/state. Prefer CSS:

```css
.message-textarea {
  outline: none;
}

.message-textarea:focus-visible {
  box-shadow: 0 0 0 2px var(--accent);
}
```

If staying inline, track focus state and conditionally apply a visible border/box-shadow, but CSS is cleaner.

### 🟠 Escalated: send failure restores content but not textarea height

The recovery path restores the text but does not trigger the resize logic because no `onChange` event fires when React state is restored in `catch`.

**Suggested fix:** centralize resizing in a helper and call it after content restoration, or use `useLayoutEffect` keyed on `content`:

```tsx
const resizeTextarea = useCallback(() => {
  const ta = textareaRef.current;
  if (!ta) return;
  ta.style.height = "auto";
  ta.style.height = `${ta.scrollHeight}px`;
}, []);

useLayoutEffect(() => {
  resizeTextarea();
}, [content, resizeTextarea]);
```

This also makes programmatic content changes, future draft restore, and channel switches safer.

## 4. Product Impact

- ✅ Desktop CJK/IME users are now protected from accidental sends during composition.
- ✅ Desktop users can compose multi-line messages with Shift+Enter.
- ⚠️ Keyboard accessibility is still degraded because focus visibility was removed.
- ⚠️ Failed sends can leave restored multi-line text visually collapsed, making error recovery feel broken.
- ⚠️ Mobile users still lack a practical newline path unless the virtual keyboard exposes a usable modifier/alternative behavior.

## 5. Suggestions

1. **Fix focus styling before merge.** This is small and low-risk: replace the removed default outline with an intentional `focus-visible` ring.
2. **Fix resize-on-programmatic-content-change before merge.** A `useLayoutEffect` resize pass is the most robust approach.
3. **Decide mobile behavior explicitly.** Options:
   - On coarse pointer/mobile, Enter inserts newline and the visible send button sends.
   - Add an “Enter to send” setting/toggle like Discord.
   - Accept desktop-only multi-line behavior and open a follow-up issue, but document it as a known product limitation.
4. **Optional:** consider using `aria-label={`Message ${channelId}`}` or a more contextual label later, but current `aria-label="Message"` is acceptable.

## 6. Positive Notes

- The IME fix is exactly the right direction and directly addresses the highest-risk regression.
- Adding `aria-label` improves accessibility versus R1.
- The diff remains focused to `MessageInput.tsx` with no unrelated churn.
- Existing typing throttle, max length, send recovery, and mobile send button are preserved.
- CI is green on the updated commit (`test` check succeeded in PR status).
