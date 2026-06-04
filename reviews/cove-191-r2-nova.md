# PR #191 R2 Review — 🌠 Nova

**Verdict: ⚠️ Needs Changes**

## 1. Summary
R2 fixes the critical IME composition bug (good). Three R1 medium issues remain unaddressed and one (height-not-restored-on-failure) is actually still broken despite the diff touching the related code path. Escalating per anti-confirmation rules.

## 2. Previous Issues Status

| # | R1 Issue | Status | New Severity |
|---|----------|--------|--------------|
| 1 | 🔴 IME composition Enter sends prematurely | ✅ **Fixed** — `!e.nativeEvent.isComposing` guard added | resolved |
| 2 | 🟡 `outline: "none"` removes focus ring | ❌ Unaddressed — still `outline: "none"` in `textareaStyle`, no `:focus-visible` replacement | 🟠 Escalated |
| 3 | 🟡 Mobile UX — no Shift key, multi-line impossible | ❌ Unaddressed — Enter still sends on mobile; send button remains `mobile-only` (tap-to-send works but newline insertion has no path) | 🟠 Escalated |
| 4 | 🟡 Height not restored on send failure | ❌ Still broken — see Critical #1 | 🟠 Escalated |

## 3. Critical Issues

### 🟠 C1 — Height not restored when send fails (R1 #4 escalated)
```ts
async function handleSubmit() {
  const text = content.trim();
  if (!text) return;
  setContent("");
  const ta = textareaRef.current;
  if (ta) {
    ta.style.height = "auto";   // collapses immediately
    ta.focus();
  }
  try {
    await api.sendMessage(channelId, text);
  } catch (err) {
    console.error("send:", err);
    setContent(text);            // restores text…
    // …but textarea height stays "auto" (≈ one line)
    // because handleChange does not run on programmatic setState.
  }
}
```
A multi-line draft that fails to send shows as a single-line collapsed textarea with hidden overflow until the user types. Worse than R1 (R2 actively collapses on submit start instead of letting browser keep height).

**Fix:** add a `useEffect` keyed on `content` that re-runs the resize logic, or call a shared `resize(ta)` helper after `setContent(text)` (wrapped in a microtask / `requestAnimationFrame` so the DOM reflects the new value):

```ts
useEffect(() => {
  const ta = textareaRef.current;
  if (!ta) return;
  ta.style.height = "auto";
  ta.style.height = `${ta.scrollHeight}px`;
}, [content]);
```
This also removes the duplicate resize logic in `handleChange` and `handleSubmit`.

### 🟠 C2 — Focus ring removed (R1 #2 escalated)
`outline: "none"` plus AntD `Input`'s built-in focus styling no longer applies (raw `<textarea>` now). Keyboard-only users have no focus indicator on the primary input — WCAG 2.4.7 failure.

**Fix:** drop `outline: "none"` or replace with `:focus-visible` styling (e.g. `box-shadow: 0 0 0 2px var(--accent)`). Inline styles can't do pseudo-classes; move to a CSS class or use `onFocus`/`onBlur` state.

### 🟠 C3 — Mobile multi-line impossible (R1 #3 escalated)
Soft keyboards have no Shift. Current behavior on mobile:
- Tap Enter → sends.
- No way to insert a newline.

Discord/Slack convention on mobile: Enter inserts newline, dedicated send button submits. Since `Button` is already `mobile-only`, consider gating the Enter-to-send behavior:

```ts
const isMobile = matchMedia("(pointer: coarse)").matches;
if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing && !isMobile) { … }
```
At minimum, document the limitation in the PR description; ideally fix before merge since the PR title is "multi-line message input" and mobile users get *less* than before (no newline path at all).

## 4. Product Impact
- **Desktop CJK users**: now safe ✅ (was 🔴 in R1).
- **Keyboard-only users**: regression vs AntD `Input` (no focus ring).
- **Mobile users**: feature does not deliver on its name — can send via tap, cannot multi-line. Net feature value on mobile = 0.
- **Failed-send UX**: collapsed textarea + 2000-char restored text is confusing (looks like content is gone until user types).

## 5. Suggestions
- Consolidate resize via `useEffect([content])` — removes 2 of 3 manual resize sites and fixes C1 for free.
- Add `wrap="soft"` explicitly for clarity.
- Consider `e.key === "Enter" && (e.ctrlKey || e.metaKey)` as an alt "send" shortcut on mobile if you flip Enter→newline there.
- Tests: add at least one for the IME guard (`isComposing: true` should not call `api.sendMessage`).
- `maxLength={2000}`: silently truncates on paste with no user feedback; consider showing remaining count near max.

## 6. Positive Notes
- IME fix is correct and minimal — exactly the right guard.
- `aria-label="Message"` is a nice accessibility add not requested in R1.
- `alignItems: "flex-end"` keeps send button bottom-aligned as multi-line grows — good visual choice.
- Safe-area padding preserved, `flex: 1` on textarea correct.
- Reset-to-auto on submit before scrollHeight measure is the right pattern (just need to apply it on restore too).

---

**Recommendation:** Fix C1 (height restore) and C2 (focus ring) before merge — both are small. C3 (mobile multi-line) is the right time to decide since PR's stated goal is multi-line input; either implement or scope-down the PR title to "desktop multi-line input".
