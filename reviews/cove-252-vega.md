# Review of PR #252: feat: emit missing Gateway events and add client cascade cleanup

## 1. Summary
This PR adds missing `GUILD_MEMBER_ADD` and `GUILD_MEMBER_REMOVE` gateway events when agents join or leave a guild, updating client-side presence state accordingly. It also introduces proper cascade cleanup in the client's Zustand stores (`useMessageStore`, `useReadStateStore`, `useTypingStore`) when a `CHANNEL_DELETE` event is received, and appends `guild_id` to `MESSAGE_DELETE` payloads.

## 2. Critical Issues
None found. The code handles the events correctly and memory cleanup is properly implemented.

## 3. Suggestions
None. The implementation is straightforward and aligns well with existing patterns.

## 4. Positive Notes
- The handling of typing timeouts (`clearTimeout` and deleting from `typingTimeoutIds` set) in `useTypingStore.ts`'s `removeChannel` method is excellent for preventing memory leaks.
- Adding a developer warning for unknown Gateway events in `useWebSocketStore.ts` is a nice DX touch.
- Zustand store state manipulation uses correct immutable updates.

## 5. Verdict
✅ Approved
