# Code Review: PR #335 (feat: message reply/quote — Discord-style)

**Reviewer:** Vega 💫
**Status:** ✅ Ready

## 1. Summary
The PR successfully implements a full-stack, Discord-style message reply and quote feature. It seamlessly adds the necessary database migration (`referenced_message_id`), enhances the REST API to validate and link referenced messages, updates shared types, and integrates per-channel reply state in the React client. The feature is well-structured, performant, and ready for merge.

## 2. Critical Issues
*None.* 
- SQL queries are properly parameterized.
- N+1 query problems are actively avoided in batch message loading.
- Client state handles component unmounting and channel switching safely.
- Database migrations correctly advance the `user_version`.

## 3. Product Impact
- **New Capability:** Users can reply directly to messages, making conversations in fast-moving channels much easier to track.
- **Optimistic UI:** Replies appear instantly without waiting for the server, creating a snappy user experience.
- **Limitation - Distant Message Jumping:** Because `handleJumpToMessage` relies on `container.querySelector`, clicking a reply quote for a message that is far back in history (and thus not currently rendered in the DOM due to virtualization or pagination) will silently do nothing. This is totally acceptable for V1 but worth noting for UX.

## 4. Suggestions (Non-blocking)
- **Distant Message Jumping:** In a future iteration, if `querySelector` returns null, you might want to fetch the target message's surrounding history and scroll there.
- **Markdown in Quotes:** `MessageReplyQuote` currently renders `referencedMessage.content` as raw string text. If the original message contains markdown (like bold, links, or code blocks), it will render the raw markdown syntax. Consider a lightweight markdown stripper for the quote preview later.
- **Draft Recovery on 400 Error:** If a user is typing a reply and the referenced message is deleted *before* they click send, the server correctly returns a 400. However, `MessageInput` clears the textarea on submit, meaning their drafted text ends up in a "failed pending message" rather than staying in the input.

## 5. Positive Notes
- **Excellent DB Optimization:** `populateReferencedMessages` correctly extracts unique missing IDs and uses a single `WHERE id IN (...)` query. This perfectly avoids N+1 database queries.
- **Graceful Degradation:** Rendering "Original message was deleted" when a referenced message is missing (or deleted later) mirrors Discord's behavior perfectly.
- **Clean State Management:** Capturing and clearing the reply state *before* the async send operation in `MessageInput` avoids race conditions. 
- **Aesthetics:** The CSS animations (`message-highlight-fade`) and UI components (`ReplyBar`, `MessageReplyQuote`) are clean, minimal, and fit the existing design system beautifully.