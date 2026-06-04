# 🌠 Nova — PR #176 Round 3 Review

**PR:** kagura-agent/cove#176 — refactor: decouple WebSocket store from domain stores via gateway dispatcher
**Verdict:** ✅ **Ready** (with non-blocking suggestions)

---

## 1. Summary

Round 3 addresses **all four R2 critical issues**. The author extracted typing state into its own `useTypingStore`, moved the activeChannelId filter off MESSAGE_CREATE (no more silent drops), added a teardown path that clears both dispatcher handlers and outstanding TYPING timeouts, and shipped real Vitest coverage for both `gateway-dispatcher.ts` and `gateway-subscriptions.ts`. The refactor now matches the Flux/dispatcher intent claimed in the PR description.

Net: 335/-72, 124 tests pass per PR body. Architecture is clean — WS store is a transport, dispatcher is the bus, domain stores are independent subscribers.

---

## 2. Previous Issues Status

| # | R2 Issue | Status | Evidence |
|---|---|---|---|
| 1 | 🔴 Silent message drop (active-channel gate on MESSAGE_CREATE) | ✅ **Fixed** | `gateway-subscriptions.ts:21` calls `addMessage(msg.channel_id, msg)` unconditionally; the old `if (msg.channel_id === activeId)` guard is gone (diff in `useWebSocketStore.ts`). |
| 2 | 🔴 Missing tests for dispatcher + subscriptions | ✅ **Fixed** | `gateway-dispatcher.test.ts` (4 cases incl. self-removal during emit, off, no-handler emit). `gateway-subscriptions.test.ts` (idempotent setup, teardown silences emits). |
| 3 | 🔴 Typing state still in WS store | ✅ **Fixed** | New `stores/useTypingStore.ts` owns `typingUsers` + `clearTyping`. `useWebSocketStore` no longer declares `typingUsers`/`clearTyping`. `MessageList.tsx` now reads from `useTypingStore`. |
| 4 | 🔴 useEffect deps / timer leak | ✅ **Fixed** | `App.tsx:184–186` adds cleanup returning `teardownGatewaySubscriptions()`. Teardown iterates module-level `typingTimeoutIds` Set and clears every pending timeout (`gateway-subscriptions.ts:90–93`). `useTypingStore.clearTyping` also removes from the Set so it stays accurate. |

All four blockers from R2 are resolved. No escalation needed.

R2 secondary suggestions:
- ✅ **Module-level handlers array** — implemented (`gateway-subscriptions.ts:9`).
- ✅ **TYPING timer leak on teardown** — implemented via shared `typingTimeoutIds` Set.
- ⚠️ **Runtime payload guards** — not addressed (see Suggestions).
- ⚠️ **Handler error isolation in emit** — not addressed (see Suggestions).
- ⚠️ **WS cleanup on unmount** — App.tsx tears down subscriptions but does not call `disconnect()`; minor.

---

## 3. Critical Issues

None.

---

## 4. Product Impact

- **Background-channel notifications now work.** Previously, messages for non-active channels were dropped at the WS layer, so unread badges / future notification logic could never see them. R3 stores every MESSAGE_CREATE; unread counters can be layered on cleanly.
- **CHANNEL_UPDATE rename now propagates** (new `updateChannel` on channel store + CHANNEL_UPDATE handler). Previously channel rename events were ignored client-side.
- **`addChannel` is now idempotent** (`useChannelStore.ts:19–23`), preventing duplicate sidebar entries if CHANNEL_CREATE arrives twice (reconnect + race).
- **Typing indicator survives store decoupling** and clears correctly on send (MESSAGE_CREATE handler still calls `clearTyping`).

No regressions detected in user-facing flows.

---

## 5. Suggestions (non-blocking)

1. **Runtime payload validation (S/M).** `useWebSocketStore.ts:60–62` blindly casts `payload.d` to the typed event payload. A malformed server frame (missing `channel_id`, wrong `t`) would crash inside a handler. A tiny per-event guard (`typeof payload.d?.channel_id === "string"`) or a zod schema keyed by event would harden this without much code.
2. **Handler error isolation in `dispatcher.emit` (S).** `gateway-dispatcher.ts:34–37` iterates `[...list]` but a throw aborts the remaining handlers for that event. Wrap each call in `try/catch` and `console.error` so one buggy subscriber can't break unrelated stores.
3. **`disconnect()` on App unmount (S).** The `App.tsx` cleanup tears down subscriptions but leaves the WebSocket open. In an SPA this is mostly fine, but during HMR / route swap you can accumulate sockets. Consider `disconnect()` in the same cleanup.
4. **Effect dep churn (S).** The setup effect depends on `setChannels`, `setActiveChannel`, `connect` (stable Zustand selectors, so likely stable refs — verify). If any becomes non-stable, every render would re-run teardown/setup and momentarily blank dispatcher state.
5. **`typingTimeoutIds` cross-module Set (S, style).** `gateway-subscriptions.ts` reaches into `useTypingStore`'s exported Set. Functionally fine and tested, but cleaner would be a `useTypingStore.getState().addTimeout(id)` / `clearAll()` API so the store owns its lifecycle end-to-end.
6. **`subscribe` internal cast (trivial).** `handlers` is typed with `any` on data. Acceptable for a closed event map, but a small generic tuple type could remove the `eslint-disable`.
7. **`gatewayEvents` Set is declared after the store** (`useWebSocketStore.ts:86–96`). Hoisted at runtime, but for readability move it above the `create<>()` call.

---

## 6. Positive Notes

- Clean Flux/dispatcher boundary — `useWebSocketStore` is now genuinely transport-only.
- Dispatcher's snapshot-iteration (`[...list]`) plus the self-removal test case shows the author thought about handler mutation during emit. Nice.
- `setupGatewaySubscriptions()` is **idempotent by construction** (it calls teardown first) and that invariant is unit-tested.
- `addChannel` idempotency + new `updateChannel` reducer are immutable and side-effect-free.
- Tests use proper Vitest mocks instead of `any` casts, and assertions are behavioural (call counts) rather than structural.
- `vite.config.ts` excludes `chat-markdown.test.ts` only — limited blast radius, presumably pre-existing flake; worth a TODO comment but not a blocker.

---

**Final rating:** ✅ **Ready to merge** after author's discretion on suggestion #1/#2 (payload guard + handler isolation are the only things I'd weakly prefer pre-merge; everything else is polish).
