# PR #176 Round 2 Review — Stella

## 1. Summary

⚠️ **Needs Changes**

Round 2 addressed several mechanical issues from the first review: channel deduplication, prototype-pollution-safe event lookup/storage, and mutation-during-iteration in the dispatcher. The architecture is cleaner than the original direct WebSocket-store coupling.

However, three previous findings remain unaddressed. Per the re-review escalation rule, I am escalating them to **Critical**: no unit tests for the new dispatcher/subscription layer, typing state still living in the WebSocket store, and silent dropping of messages for non-active channels. The last one is the most user-visible correctness issue.

## 2. Previous Issues Status

- **Channel dedup needed in `addChannel`** — **Addressed.** `useChannelStore.ts:19-23` now skips existing channel IDs.
- **Prototype pollution in event allowlist** — **Addressed.** `useWebSocketStore.ts:103-113` now uses `Set`, and dispatcher handler storage is null-prototype at `gateway-dispatcher.ts:18`.
- **Mutation during iteration in `emit()`** — **Addressed.** `gateway-dispatcher.ts:35` iterates over a copied handler array.
- **No unit tests for `gateway-dispatcher`** — **Not addressed → escalated to Critical.** There are still no tests covering `gateway-dispatcher.ts` or `gateway-subscriptions.ts`.
- **`useEffect` deps stability in `App.tsx`** — **Addressed.** The imported setup/teardown functions are stable, and `connect` is selected directly from Zustand at `App.tsx:136`.
- **Typing state still in WS store** — **Not addressed → escalated to Critical.** `gateway-subscriptions.ts:7` imports `useWebSocketStore`, and `TYPING_START` still mutates `useWebSocketStore` at `gateway-subscriptions.ts:41-57`.
- **Silent message drop for non-active channels** — **Not addressed → escalated to Critical.** `gateway-subscriptions.ts:22-27` only stores `MESSAGE_CREATE` when `msg.channel_id === activeId`.

## 3. Critical Issues

1. **Non-active channel messages are still silently dropped**  
   `gateway-subscriptions.ts:22-27` ignores `MESSAGE_CREATE` for every channel except the active one. That means messages received while the user is reading another channel are not cached, cannot drive unread state later, and can be overwritten/lost depending on subsequent fetch timing. This was called out in Round 1 and is unchanged. At minimum, store the message in `useMessageStore` for its channel regardless of active channel; UI notification/unread behavior can still be conditional.

2. **Typing state remains in `useWebSocketStore`, preserving domain coupling**  
   `gateway-subscriptions.ts:7` imports the WS store, and `gateway-subscriptions.ts:41-57` owns typing mutations through that store. This keeps domain/UI state in the transport store, contrary to the PR goal that `useWebSocketStore` acts as a pure gateway dispatcher. Move typing state/actions to a domain store such as `useTypingStore`, or colocate it with channel/message domain state.

3. **New dispatcher/subscription behavior has no unit coverage**  
   No tests were added for `gateway-dispatcher.ts` or `gateway-subscriptions.ts`. This is risky because the PR introduces global subscription state, teardown/re-setup behavior, allowlisted dispatch, and event-to-store wiring. Please add focused tests for: duplicate setup does not duplicate handlers, teardown unsubscribes all handlers, emit survives unsubscribe-during-emit, unknown gateway events are ignored, and each gateway event updates the intended store.

## 4. Product Impact

The non-active-channel drop can make Cove feel unreliable: users can receive a WebSocket event but not see the message when navigating later unless a fresh fetch recovers it. It also blocks future unread indicators because the client discards the only real-time signal for background channels.

Keeping typing state in the WS store weakens the intended architectural boundary. Future typing behavior changes will continue to touch transport code or transport-owned state, making the dispatcher refactor only partial.

## 5. Suggestions

- Add runtime payload guards before dispatching or before mutating stores. `useWebSocketStore.ts:72-73` casts `payload.d` directly, and handlers assume required fields. A malformed `MESSAGE_CREATE` can partially add a bad message before throwing at `gateway-subscriptions.ts:27`.
- Consider isolating handler failures in `GatewayDispatcher.emit()`. Today one throwing handler prevents later handlers for the same event (`gateway-dispatcher.ts:35-37`). There is currently one handler per event, but the dispatcher API supports multiple subscribers.
- In `App.tsx:185-187`, cleanup tears down subscriptions but does not disconnect the WebSocket. If this effect ever unmounts due to auth/setup transitions or hot reload, the socket may keep reconnecting with no domain subscribers.

## 6. Positive Notes

- The dispatcher is small, readable, and dependency-free.
- The null-prototype handler map plus `Set` allowlist is a good hardening improvement.
- `setupGatewaySubscriptions()` begins with teardown, which avoids duplicate subscriptions across repeated setup calls.
- `addChannel` dedup is now simple and correct for repeated `CHANNEL_CREATE` events.
