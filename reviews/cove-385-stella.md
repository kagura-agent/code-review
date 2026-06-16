# 🌟 Stella Review — PR #385

**PR:** kagura-agent/cove#385 — feat(client): message actions — reply, edit in context menu + hover bar (#300)  
**Verdict:** ⚠️ Needs Changes

## 1. Summary

This PR adds message actions in the client: reply in the context menu, edit for own messages via context menu and hover action bar, an edit-mode input banner, and a client API wrapper for `PATCH /channels/:id/messages/:msgId`.

I also see additional mention/autocomplete and gateway mention-set-cap changes in the PR. CI is green, but the PR adds no test files or updated tests despite several user-visible behavior changes.

## 2. Critical Issues

### 1) Editing can leak the edited message text into another channel after navigation

`MessageInput` keeps local `content` state while `channelId` changes. When editing starts, the effect copies the original message into `content`. If the user switches to another channel while edit mode is active, `isEditing` becomes false because the edit store still points to the previous channel, but the textarea content remains populated.

Result: the user can accidentally send the message being edited as a new message in the new channel, with no edit banner visible.

Suggested fix: when `channelId` changes and the active edit belongs to a different channel, either clear/restorably isolate the textarea content, stop editing, or maintain per-channel draft/edit state. At minimum, do not leave edit content visible as normal compose text in another channel.

### 2) Context-menu Reply builds an incomplete fake `Message`

`MessageContextMenu.handleReply()` constructs a minimal `Message` with blank author fields and empty timestamp instead of using the actual message object already available in `MessageList` state.

Product-visible effects:
- Reply bar can show a blank author.
- Pending reply quote can render incomplete/incorrect metadata.
- Future reply UI that depends on author, timestamp, attachments, embeds, etc. will silently degrade.

Suggested fix: pass the full `contextMenu.message` into `MessageContextMenu` or pass an `onReply(message)` callback from `MessageList`, instead of reconstructing a partial message from `messageId/channelId/content`.

### 3) No test coverage for new behavior

The PR changes multiple user behaviors:
- reply from context menu
- edit from context menu
- edit from hover action bar
- edit-mode submit/cancel/Escape behavior
- clearing reply state when editing starts
- mention trigger behavior and autocomplete accessibility markup
- gateway mention set capping

No tests are added or updated in the PR. Per review standard, behavior changes need coverage before merge.

Recommended minimum coverage:
- `useEditStore` state transitions.
- `MessageInput` edit submit calls `api.editMessage`, clears edit mode, and does not send a new message.
- Escape/cancel exits edit mode safely.
- Channel switch while editing does not expose edit text as normal compose text in another channel.
- Context-menu reply uses complete message data.
- Mention trigger boundary cases if those changes remain in this PR.

## 3. Product Impact

The feature direction is good, but the current implementation risks user-visible mistakes:

- A user editing a message can unintentionally post that message content into another channel after switching channels.
- Reply previews from the context menu can look broken or anonymous because author metadata is missing.
- Without tests, regressions in core compose behavior are likely; this area already combines sending, replies, attachments, mentions, typing, pending messages, and now editing.

## 4. Suggestions

- Consider storing edit state per channel or resetting/restoring drafts explicitly on channel switch.
- Pass the full `Message` to context-menu actions rather than duplicating partial message construction.
- While in edit mode, consider disabling attachments/paste/drop or clearly defining attachment behavior. Currently edit mode clears pending files when it starts, but drag/drop/paste remains enabled afterward while `editMessage` only sends content.
- Change the textarea placeholder/button affordance while editing, e.g. “Edit message…” and possibly a save icon/label, so users can distinguish edit submit from normal send.
- Split unrelated mention follow-up changes into a separate PR if they are not required for #300; it will make review and testing clearer.

## 5. Positive Notes

- Own-message gating is present in both context menu and hover action bar.
- The edit API wrapper matches the existing server endpoint shape.
- Clearing active reply state when editing starts is the right product choice; reply and edit modes should not stack.
- Escape-to-cancel and visible edit banner are good interaction details.
- The hover edit action is consistent with the existing quick action pattern.
