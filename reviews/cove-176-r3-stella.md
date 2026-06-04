# PR #176 Round 3 Review — Stella

## 1. Summary

⚠️ **Needs Changes**

Round 3 fixes the four Round 2 blockers in the code path that was originally reviewed: background `MESSAGE_CREATE` events are now stored, gateway tests were added, typing state moved out of `useWebSocketStore`, and typing timers are tracked/cleared during gateway subscription teardown.

I found one fresh lifecycle issue that should be fixed before merge: the authenticated WebSocket is still left open when the app effect cleans up, including logout / setup transitions. This keeps the transport alive after the UI has torn down its subscriptions and after the token has been removed locally.

Validation run locally:
- `pnpm test` ✅ 124 tests passed
- `pnpm --filter @cove/client lint && pnpm --filter @cove/client build` ✅ build passed; lint has one warning for unused `get` in `useWebSocketStore.ts:23`

## 2. Previous Issues Status

1. **Silent message drop — MESSAGE_CREATE only stored for active channel** — ✅ **Addressed.** `packages/client/src/lib/gateway-subscriptions.ts:20-23` now unconditionally calls `addMessage(msg.channel_id, msg)`. The active-channel gate is gone.

2. **Missing tests — gateway-dispatcher.ts and gateway-subscriptions.ts had zero coverage** — ✅ **Addressed.** `packages/client/src/lib/gateway-dispatcher.test.ts:4-42` covers on/off/emit, self-removal during emit, and no-handler emits. `packages/client/src/lib/gateway-subscriptions.test.ts:28-80` covers idempotent setup and teardown. Coverage is still thin for per-event behavior and timer cleanup, but the zero-coverage blocker is resolved.

3. **Typing state still in WS store** — ✅ **Mostly addressed.** Typing state now lives in `packages/client/src/stores/useTypingStore.ts:17-31`, and `MessageList` reads it from `useTypingStore` at `packages/client/src/components/MessageList.tsx:48`. `gateway-subscriptions.ts` no longer imports or mutates `useWebSocketStore`. There is still residual transport → typing-store coupling in `useWebSocketStore.ts:4` and `useWebSocketStore.ts:61-68` for close cleanup; see Suggestions.

4. **useEffect deps / timer leak** — ✅ **Timer leak addressed; lifecycle cleanup incomplete.** `teardownGatewaySubscriptions()` clears all tracked typing timers at `packages/client/src/lib/gateway-subscriptions.ts:91-94`, and `useTypingStore.clearTyping` removes cleared timers from the shared set at `packages/client/src/stores/useTypingStore.ts:23-29`. However, `App.tsx` cleanup only tears down subscriptions and does not close the WebSocket; see Critical Issues.

R2 secondary suggestions:
- Runtime payload guards — ❌ Not addressed.
- Handler error isolation — ❌ Not addressed.
- WS cleanup on unmount — ❌ Not addressed; now a blocker below.
- Timer leak on teardown — ✅ Addressed.
- Module-level handlers array — ✅ Implemented at `gateway-subscriptions.ts:10`.

## 3. Critical Issues

### C1. Authenticated WebSocket remains open after app cleanup/logout

**Location:** `packages/client/src/App.tsx:183-187`, `packages/client/src/stores/useUserStore.ts:24-28`, `packages/client/src/stores/useWebSocketStore.ts:79-83`

The app effect now sets up gateway subscriptions and opens the WebSocket, but its cleanup only calls `teardownGatewaySubscriptions()`:

- `App.tsx:183-184` sets up subscriptions and calls `connect()`.
- `App.tsx:185-187` tears down subscriptions, but never calls `disconnect()`.
- `useUserStore.logout()` removes the token and flips `needsSetup` at `useUserStore.ts:24-28`; this triggers the effect cleanup, but the already-authenticated socket remains alive.

Product/security impact: after a user signs out or transitions back to setup, the UI has no subscribers, but the browser still holds an authenticated gateway connection and continues receiving/heartbeating until the socket closes for some other reason or the page unloads. If it does close later, the reconnect loop can also keep waking up after logout until the hello/token path closes it again.

**Fix:** select `disconnect` from `useWebSocketStore` in `App.tsx` and call it in the cleanup before or after `teardownGatewaySubscriptions()`:

- `const disconnect = useWebSocketStore((s) => s.disconnect);`
- cleanup: `disconnect(); teardownGatewaySubscriptions();`

This also completes the R2 “WS cleanup on unmount” suggestion and makes the gateway lifecycle symmetrical.

## 4. Product Impact

Positive fixes from Round 3:
- Background channel messages are no longer dropped, so multi-channel usage is much more reliable.
- Typing timers are explicitly tracked and cleared, reducing remount/logout leaks.
- The dispatcher/subscription split is now tested enough to catch the most obvious global-handler regressions.

Remaining risk:
- Sign-out does not fully sign out of realtime transport until the socket happens to close. That violates user expectations for logout and leaves unnecessary authenticated network activity running in the background.

## 5. Suggestions

- **Add runtime payload guards before mutating stores.** `useWebSocketStore.ts:55-57` casts `payload.d` directly into the event map. For example, `gateway-subscriptions.ts:21` can add a malformed `MESSAGE_CREATE` before `msg.author.id` throws at line 22, and the outer WebSocket `try/catch` will swallow the error. Validate required fields per event before dispatch or at the start of each handler.

- **Isolate handler errors in the dispatcher.** `gateway-dispatcher.ts:35-36` lets one throwing handler stop later handlers for the same event. Today there is mostly one handler per event, but the dispatcher abstraction invites multiple subscribers. Consider catching per handler and logging/reporting without aborting the remaining handlers.

- **Expand subscription tests.** The new tests solve the zero-coverage blocker, but they do not exercise `TYPING_START` timer cleanup, `MESSAGE_CREATE` for non-active/background channels, `READY` presence filtering, or channel create/update/delete wiring. These are low-cost tests and would lock in the Round 3 fixes.

- **Remove the unused `get` parameter.** `useWebSocketStore.ts:23` has an ESLint warning because the store factory still accepts `get` but no longer uses it.

- **Consider a gateway disconnect event for full decoupling.** `useWebSocketStore.ts:4` still imports `useTypingStore` to clear typing indicators in `onclose`. A `GATEWAY_DISCONNECT` dispatcher event would let typing cleanup live with other gateway subscriptions and keep the WebSocket store transport-only.

## 6. Positive Notes

- The `MESSAGE_CREATE` fix is the right product behavior: storing by `msg.channel_id` keeps background channels coherent.
- `useTypingStore` is a good extraction and makes `MessageList` depend on the actual domain state instead of transport state.
- The dispatcher uses a null-prototype handler map and snapshot iteration, preserving the earlier security/correctness fixes.
- `setupGatewaySubscriptions()` remains idempotent by teardown-first behavior, which is helpful under React Strict Mode and test re-entry.
