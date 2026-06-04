# Code Review: PR #176 (cove)
**Reviewer:** 💫 Vega

## Summary
The PR successfully decouples the WebSocket connection layer from the individual domain stores by introducing a standard, event-driven `GatewayDispatcher` pattern. This eliminates circular dependencies, makes the domain stores independently testable, and centralizes all WebSocket event handling into `gateway-subscriptions.ts`. The implementation is structurally sound and follows standard Flux-like architecture patterns well.

## Critical Issues
None. The code is safe to merge. Lifecycle handling in `App.tsx` correctly cleans up subscriptions to prevent memory leaks on component remounts.

## Product Impact
- **Real-Time Channel Updates (Positive):** This PR introduces a subtle but significant product improvement. Previously, the WebSocket `onmessage` handler ignored `CHANNEL_CREATE`, `CHANNEL_UPDATE`, and `CHANNEL_DELETE` events. Now, `gateway-subscriptions.ts` actively subscribes to these and updates the channel store. Users will dynamically see new channels, name changes, or deleted channels in real-time without needing to refresh the application.

## Suggestions

1. **Safety against prototype iteration (Correctness / Hardening)**
   In `useWebSocketStore.ts`, the check `payload.t in gatewayEvents` checks against a plain object. If the server (or an injected payload) sends `{"t": "toString"}`, `payload.t in gatewayEvents` will evaluate to `true` (via the prototype chain). The dispatcher will then try to iterate over the `toString` function, resulting in a `TypeError: list is not iterable` that crashes the client loop.
   *Recommendation:* Change the object to an array whitelist and use `.includes()`, or instantiate it with `Object.create(null)`.
   ```typescript
   const ALLOWED_EVENTS = ["MESSAGE_CREATE", "MESSAGE_UPDATE", ...];
   if (payload.t && ALLOWED_EVENTS.includes(payload.t)) { ... }
   ```

2. **Deduplication in `useChannelStore.addChannel`**
   With the new real-time `CHANNEL_CREATE` subscription, if the client receives the event twice (e.g. upon reconnecting), it will append duplicates to the channel list. 
   *Recommendation:* Add a quick check to prevent duplicates in `stores/useChannelStore.ts`:
   ```typescript
   addChannel: (channel) => set((s) => ({
     channels: s.channels.some(c => c.id === channel.id) ? s.channels : [...s.channels, channel]
   })),
   ```

3. **Further Decoupling (Architecture)**
   `useWebSocketStore` is still managing `typingUsers` state, while all other domain states were decoupled. For future maintainability, consider extracting typing indicators to a dedicated `useTypingStore` so `useWebSocketStore` is strictly responsible for connection lifecycle.

## Positive Notes
- The architectural shift is extremely clean. Adding new Gateway events in the future will be trivial and won't require touching the low-level WebSocket parsing code.
- Using a plain array to track handlers in `gateway-subscriptions.ts` and iterating it for teardown in `App.tsx` is an elegant, bulletproof way to prevent subscription leaks during React Strict Mode or hot reloads.
- Excellent use of types across the Dispatcher map (`GatewayEventMap`), preserving strict end-to-end type safety for WS payloads.

**Rating:** ✅ Ready
