# Review of PR #191: feat: multi-line message input with auto-resize (Shift+Enter)

## 1. Summary
This PR replaces the single-line Ant Design `<Input>` with a native `<textarea>`, enabling multi-line message composition. It includes logic for auto-resizing height based on `scrollHeight` (capped at 200px) and mapping "Enter" to send while "Shift+Enter" inserts a newline.

## 2. Critical Issues
None.

## 3. Product Impact
- **Highly Positive**: Brings the chat input closer to modern messaging apps (like Discord, Slack). Greatly improves user experience when writing longer messages.
- **Mobile Consideration**: On mobile devices, users typically expect the "Return" key to add a newline, as there's no native "Shift" key modifier for Shift+Enter. With this logic, the virtual keyboard's return key will trigger submission. While this matches the desktop behavior, it might make multi-line input impossible on standard mobile keyboards. 

## 4. Suggestions
- **Mobile Device Newline Support**: Consider bypassing the `Enter` submission if the user is on a touch/mobile device, or providing a toggle for "Enter to send" vs "Enter to newline".
- **Refocusing on Send**: `ta.focus()` is called after submit, which keeps the keyboard open on mobile and retains cursor focus on desktop. This is good, but just ensure it aligns with your mobile UX goals (keeping keyboard open after send).
- **Jitter Prevention**: Setting `ta.style.height = "auto"` followed by `${ta.scrollHeight}px` can occasionally cause a micro-stutter/jitter in some browsers. It's usually fine, but if it becomes noticeable, consider a hidden mirror-div approach for height calculation.

## 5. Positive Notes
- **Clean Implementation**: Replacing the heavy `antd` input with a native textarea for this specific need is smart and keeps the bundle/complexity light.
- **Good CSS Handling**: The `flex-end` alignment and constraints (`minHeight`, `maxHeight`, `overflowY`) are perfectly configured to keep the Send button at the bottom and the layout stable.

**Rate**: ✅ Ready
