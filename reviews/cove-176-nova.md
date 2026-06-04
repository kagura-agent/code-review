# Nova Review — cove#176: Gateway Dispatcher Refactor

## Summary
Clean Flux-style refactor that removes 4 domain-store imports from `useWebSocketStore`, replacing direct mutation with a typed event dispatcher. The architectural direction is correct, the type modeling is sound, and behavioral equivalence with the prior `if/else if` chain looks preserved for the 5 previously-handled events. The new CHANNEL_* handlers are net-new behavior the server may not yet emit; that's fine but worth confirming. No critical bugs, but a few sharp edges worth tightening before merge.

Rating: **✅ Ready** (with minor suggestions)

## Critical Issues
None.

## Product Impact
1. **CHANNEL_CREATE / CHANNEL_UPDATE / CHANNEL_DELETE are now consumed.** Before this PR these events were ignored by the client. After merge, if the server emits any of them, channel list state will mutate live. Two product questions:
   - Does the server currently emit CHANNEL_UPDATE/DELETE? If yes, was the previous "ignore" actually the desired UX (e.g., requiring manual refresh)? If no, this is dead code until backend ships — harmless.
   - `addChannel` blindly appends. If the server re-emits CHANNEL_CREATE on reconnect/READY for channels already in the list, you'll get duplicates. Worth a dedupe guard (`channels.some(c => c.id === channel.id)`).
2. **READY no longer drops through to MESSAGE_* checks.** Old code had `if (payload.t === "READY") {...}` then continued to the MESSAGE_* `if/else if` chain. Since READY's `t` doesn't match any of those, behavior is identical — verified. No regression.
3. **Unknown event types are now filtered by allowlist** (`payload.t in gatewayEvents`). Previously they fell through silently. Functionally equivalent.

## Suggestions

**`gateway-subscriptions.ts`**
- L11: module-level `handlers` array is a process singleton. Combined with React StrictMode's double-mount in dev, `setup → teardown → setup` runs twice on mount. The defensive `teardownGatewaySubscriptions()` at the top of `setup` handles this correctly, but means setup is *not* re-entrant safe under concurrent calls. Single-threaded JS makes this academic, but a comment noting the singleton assumption would help future readers.
- L21-27 (MESSAGE_CREATE): silently dropping messages for non-active channels means unread-state, badges, and last-message-preview cannot work later without revisiting this. Preserving prior behavior is fine for this PR, but flag as a known limitation.
- L36-55 (TYPING_START): the `setTimeout` reference is captured into store state but if the user types again, `clearTyping` is called and the old timeout fires harmlessly (clears already-cleared entry). Assuming `clearTyping` does `clearTimeout` on the stored handle (not visible in diff), fine. If not, you accumulate no-op timers — worth verifying in `useWebSocketStore.clearTyping`.
- L92 (`teardownGatewaySubscriptions`): the `as any` cast is necessary because of the union narrowing limit; could be `as keyof GatewayEventMap` to drop the eslint-disable.

**`gateway-dispatcher.ts`**
- L31-37 (`emit`): iterates the live array. If a future handler ever calls `dispatcher.off()` mid-emit, mutation during iteration is unsafe. Trivial fix: `for (const handler of [...list])`.
- No `once()` or unsubscribe-returning `on()`. Optional convenience, not required.

**`useWebSocketStore.ts`**
- L72-74: the `gatewayEvents` allowlist is defined *below* its usage (hoisted const works because it's an object literal — but stylistically it would read better moved above the `create` block or co-located with the dispatcher module).
- The cast `payload.d as GatewayEventMap[keyof GatewayEventMap]` is a union type loss. Practically OK since handlers narrow by event name, but means the dispatcher itself has no runtime payload validation — a malformed server payload (e.g., MESSAGE_CREATE without `author`) will crash inside the subscriber. Consider zod or runtime guards at the WS boundary in a follow-up.

**Testing**
- No tests added for `gateway-dispatcher.ts` or `gateway-subscriptions.ts`. The dispatcher is pure logic (on/off/emit, handler array semantics, off-during-emit) and trivially unit-testable — adding ~20 lines of tests would catch any future regression in this central piece. Not a blocker for a small team, but high ROI.

**App.tsx**
- L183-187: `useEffect` deps include `connect`, `setChannels`, `setActiveChannel`. If these store-derived functions are not referentially stable across renders, the effect re-runs, tearing down and re-setting up subscriptions plus calling `connect()` again. Zustand getters are typically stable, so likely fine — but worth confirming `connect()` is idempotent (no duplicate WS) since this PR doesn't change that contract but now also affects subscription churn.

## Positive Notes
- Type modeling in `GatewayEventMap` is the right shape — discriminated by event name, payload typed per event. Clean.
- `setup` calls `teardown` first — defensive against React StrictMode and re-mount. Good instinct.
- Behavior-preserving refactor: I walked each of the 5 original branches against the new subscriptions and they match (including the `if (data.user_id === selfId) return` early-out and the typing-timeout pattern).
- Eliminating 4 cross-store imports from the WS layer is a real architectural win — useWebSocketStore is now genuinely testable in isolation.
- Scope discipline: refactor only, no behavior creep beyond the 3 new CHANNEL_* hooks which are cheap to add while you're already wiring the dispatcher.

---
Path: `~/.openclaw/workspace/code-review/reviews/cove-176-nova.md`
