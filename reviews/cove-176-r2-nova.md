# 🌠 Nova — Re-review (Round 2): cove PR #176

**Rating: ⚠️ Needs Changes** (down from R1 ✅ — see escalations)

## 1. Summary

Round 2 added three fix commits (`4f52e55`, `e1ee172`, `6fdf043`) that successfully address the **dispatcher-layer** correctness/security findings from R1 (channel dedup, emit iteration safety, prototype pollution). However, **three behavioral/quality findings from R1 received zero attention**, and per the escalation rule they now move up in severity. No tests were added despite this being a new pub/sub primitive in the data path.

## 2. Previous Issues — Status

| # | Issue | Reviewer(s) | Status | New severity |
|---|---|---|---|---|
| 1 | `addChannel` dedup | Vega+Nova | ✅ Addressed (`useChannelStore.ts:19-23`, `.some(c => c.id === …)`) | resolved |
| 2 | Prototype pollution in event allowlist | Vega | ✅ Addressed — now uses `Set` (`useWebSocketStore.ts:103-113`) and handler bag uses `Object.create(null)` (`gateway-dispatcher.ts:18`) | resolved |
| 3 | Mutation during iteration in `emit()` | Nova | ✅ Addressed — snapshot copy `for (const handler of [...list])` (`gateway-dispatcher.ts:36`) | resolved |
| 4 | **No unit tests for gateway-dispatcher** | Nova | ❌ Not addressed — `find packages/client -name 'gateway*test*'` returns nothing | **Critical** (escalated) |
| 5 | `useEffect` deps stability | Nova | ⚠️ Partially — same dep array now ALSO drives `setupGatewaySubscriptions`/`teardownGatewaySubscriptions` (App.tsx:183-187). Any non-stable selector return ⇒ tears down & re-subscribes mid-session, dropping in-flight `TYPING_START` timeouts. | **High** (escalated) |
| 6 | Typing state still lives in WS store | Vega | ❌ Not addressed — subscriber now reaches **into** WS store via `useWebSocketStore.setState(...)` from `gateway-subscriptions.ts:36-46`, which is *worse* coupling than before (an outsider mutates internal shape). | **High** (escalated) |
| 7 | Silent message drop for non-active channels | Nova | ❌ Not addressed — `gateway-subscriptions.ts:21-25` keeps `if (msg.channel_id === activeId) addMessage(...)`. No unread counter, no per-channel cache fill. | **High** (escalated) |

## 3. Critical Issues

### C1. Missing tests for the new dispatcher + subscription layer (escalated)
The PR introduces a custom typed event bus (`gateway-dispatcher.ts`) and a side-effectful wiring module (`gateway-subscriptions.ts`) sitting on the realtime path, but ships zero tests. The fixes added in Round 2 (emit-iteration snapshot, null-prototype handler bag, dedup) are exactly the kind of subtle behavior that regressions silently break. Minimum coverage needed before merge:
- `dispatcher.on/off/emit` happy path + off-during-emit + double-off + emit-with-no-handlers
- `gatewayEvents` allowlist rejects unknown `payload.t` (regression test for the prototype-pollution fix)
- `setupGatewaySubscriptions` is idempotent (it self-teardowns; verify no leak by emitting and asserting single delivery)
- `MESSAGE_CREATE` for non-active channel: documents current "drop" behavior so future authors don't trip over it.

These run in Vitest, the package already has it configured.

### C2. `useEffect` dependency churn now tears down realtime subscriptions
`App.tsx:175-188` adds setup/teardown into the same effect whose deps are `[needsSetup, authLoading, setChannels, setActiveChannel, connect]`. `setChannels`/`setActiveChannel`/`connect` are Zustand action references and *should* be stable, but the effect was already flagged in R1 for fragility. Now the cost of a dep flip is much higher: every re-run will `teardownGatewaySubscriptions()` → `setupGatewaySubscriptions()` → `connect()`. Each `TYPING_START` handler also schedules an 8 s `setTimeout` whose handle is stored inside WS store state — teardown does **not** clear those timers, so churned re-mounts leak timers that continue firing `clearTyping` against potentially stale state.

Fix: split into two effects — one that runs `setup/teardown` exactly once on mount (`[]`), one for the data loading. Or move `setup`/`teardown` outside React (e.g., module-init + StrictMode-safe ref counting).

## 4. Product Impact

- **CHANNEL_CREATE while open** is now idempotent — duplicate channels from race/replay no longer appear in the sidebar. Real user-visible win.
- **CHANNEL_UPDATE** works end-to-end for the first time (name/topic edits will reflect live).
- **Unread / background channels still go nowhere** (Issue 7). For a Discord-style client this is a visible product gap: switching channels shows an empty pane until history fetch, and there is no unread badge driven by the gateway. Should be a tracked follow-up if not fixed here.
- Prototype-pollution surface in the WS hot path is closed; safe to expose to untrusted gateway payloads.

## 5. Suggestions

1. **(High) Decouple typing state from WS store.** `gateway-subscriptions.ts` currently does `useWebSocketStore.setState((s) => ({ typingUsers: …}))` from outside the store. Either (a) expose `addTypingUser(channelId, entry)` action on the WS store and call it, or (b) move typing into its own `useTypingStore`. As-is, two modules own the shape of `typingUsers`.
2. **(Med) Hoist `gatewayEvents` Set above its use site** in `useWebSocketStore.ts`. It works due to closure timing, but declaring it at line 103 while referencing it in the `create()` callback above is needlessly clever — move it to the top of the file.
3. **(Med) `dispatcher.off` leaves empty arrays.** Minor, but consider `delete this.handlers[event]` when the filtered list is empty so the bag doesn't grow with stale keys over many teardown cycles.
4. **(Med) `TYPING_START` timer leak on teardown.** When subscriptions tear down (or the WS reconnects via `onclose`), pending 8 s timeouts still fire and call `clearTyping` on possibly cleared state. Track and clear timers in teardown.
5. **(Low) Single shared `handlers` array module-level** means two concurrent `setupGatewaySubscriptions` calls would race (the second `teardownGatewaySubscriptions()` inside `setup` mitigates this, but it’s still implicit). Consider returning an unsubscribe function from `setup` and storing it in a ref.
6. **(Low) `READY` typing:** `GatewayEventMap.READY.presences[].status` is typed `string`; tighten to `"online" | "offline" | "idle"` to match `PRESENCE_UPDATE`.
7. **(Low) MESSAGE_CREATE drop:** at minimum add a comment in `gateway-subscriptions.ts:21-25` explaining the drop is intentional pending unread-counter work, and file/link the follow-up issue.

## 6. Positive Notes

- R1 critical findings were addressed cleanly with minimal, surgical commits.
- Using `Set.has` instead of `in` on a plain object is the right primitive for the allowlist — not just defensive but more honest about intent.
- `Object.create(null)` for the handler bag is the correct belt-and-suspenders fix.
- `for (const handler of [...list])` is the simplest correct fix for off-during-emit; no clever generation counters required.
- `addChannel` dedup is implemented as identity-preserving (`return s` when duplicate) — avoids spurious re-renders. Nice touch.
- Architecture direction (Flux-style dispatcher) is sound and the WS store is now genuinely a transport — readable diff.

---
**Verdict:** ⚠️ Needs Changes. Block on **C1 (tests)** and **C2 (effect/timers)**; the three unaddressed behavioral findings (typing coupling, message drop, useEffect deps) should be resolved or explicitly deferred with linked issues before merge.
