# Nova R4 Review — cove#190

**Rating: ✅ Ready (with minor follow-ups)**

## 1. Summary

Round 4 addresses all three R3 escalated criticals. The `createAbortableDispatch` now attaches a no-op catch on the pre-aborted path, the `channelGeneration` map is cleaned in the dispatch `finally` block, and every dispatcher callback (`deliver`, `onPartialReply`, `onToolStart`, `onItemEvent`, `onPlanUpdate`, `onApprovalEvent`, `onCommandOutput`, `onPatchSummary`, `onCompactionStart`, `onCompactionEnd`, `onAssistantMessageStart`, `sendOrEdit`) is now gated by `isCurrent()`. Code looks production-ready for the originally targeted failure mode.

## 2. Previous Issues Status

| R3 Item | Status | Notes |
|---|---|---|
| 🔴 UnhandledPromiseRejection on pre-aborted signal | ✅ Fixed | `dispatch.catch(() => {})` added before early `reject` (channel.ts L52). Verified: when caller passes a pre-aborted signal, the orphaned dispatch promise no longer raises `unhandledRejection`. |
| 🔴 `channelGeneration` map grows unbounded | ✅ Mostly fixed | `channelGeneration.delete(channelId)` runs in the `finally` block when the current dispatch still owns the controller (L505-507). One small residual leak — see Critical Issues #1 below. |
| 🔴 Incomplete callback guards | ✅ Fixed | All 11 dispatcher callbacks + `sendOrEdit` now check `isCurrent()`. Grepped the diff — no callback escapes the guard. |

R3 *suggestions* status:
- Configurable timeout → **not done** (still hardcoded `DISPATCH_TIMEOUT_MS = 120_000`).
- Plugin shutdown abort hook → **not done** (no `destroy()`/`onShutdown` path that drains `pendingDispatches`).
- Integration tests (real ws reconnect end-to-end) → **not done** (unit tests only).
- JSDoc on `reconnect` event in `GatewayEvents` → **not done**.

## 3. Critical Issues

**None blocking.** The three R3 criticals are resolved. One minor residual + one minor robustness gap noted below.

## 4. Product Impact

The original Cove-stuck-channel bug (#180) should be reliably fixed:
- Stuck dispatch → 120s timeout releases the channel slot.
- Server restart / WS reconnect → all pending dispatches aborted, generations bumped, callbacks silenced.
- Rapid same-channel re-send → previous dispatch aborted, new one takes over cleanly.

User-visible behavior: no more permanently dead channels after a Cove server restart. Worst case is a 120s delay before a stuck channel self-heals, which is acceptable for the failure mode being addressed.

No regressions expected for happy-path dispatches — the only added cost is one `Map` lookup per callback invocation, negligible.

## 5. Suggestions (Non-blocking)

1. **Residual `channelGeneration` leak on reconnect path.** When the `reconnect` handler runs:
   ```
   pendingDispatches.clear();
   ```
   the aborted dispatch's `finally` block then checks `pendingDispatches.get(channelId) === abortController` — this is now `undefined`, so `channelGeneration.delete(channelId)` is **skipped**. Each unique channel ever active during a reconnect leaves one stale `Map` entry behind. It's bounded by the number of distinct channels (not per-message), so practical impact is tiny — but a clean fix is one line:
   ```ts
   gatewayClient.on("reconnect", () => {
     for (const [channelId, controller] of pendingDispatches) {
       channelGeneration.set(channelId, (channelGeneration.get(channelId) ?? 0) + 1);
       controller.abort();
     }
     pendingDispatches.clear();
     channelGeneration.clear(); // <-- safe; new dispatches initialize from 0 again
   });
   ```
   (Safe because gen counters are only meaningful for in-flight dispatches; after `clear()` plus `abort()` no in-flight closure can match any future value.)

2. **Plugin shutdown hook still missing.** If the plugin is unloaded with dispatches in flight, controllers are never aborted and the dispatcher's pending I/O may leak across a hot-reload. Add a `destroy()`/teardown path that:
   ```ts
   for (const c of pendingDispatches.values()) c.abort();
   pendingDispatches.clear();
   channelGeneration.clear();
   ```
   Carry over to a follow-up issue if not done here.

3. **Configurable timeout.** `DISPATCH_TIMEOUT_MS = 120_000` is hardcoded. Promote to plugin config (`account.dispatchTimeoutMs` or env). 120s is reasonable for chat dispatches but a few long-running tool flows may legitimately exceed it; today they'll be timed-out and silently dropped.

4. **JSDoc on the new `reconnect` event.** `GatewayEvents.reconnect: () => void;` has no doc — add a line stating it fires on *subsequent* CONNECTED frames (not first), so plugin authors don't conflate it with `ready`.

5. **Test coverage gap — same-channel takeover within the dispatcher closure.** The new tests exercise `createAbortableDispatch` in isolation and the `pendingDispatches` map externally. Neither test asserts that an *in-flight* dispatch's callbacks become no-ops after a new same-channel message arrives (i.e., the `isCurrent()` guard). A test that captures a callback reference, increments the generation externally, then verifies the callback's side effect is suppressed would lock down the contract that R3 highlighted.

6. **Style nit.** `new Promise<void>(() => {})` is repeated across tests — extract a `neverResolves()` helper. Cosmetic.

## 6. Positive Notes

- The `isCurrent()` closure is a clean idiom — one capture, one check, applied uniformly. Easy to audit.
- The `finally`-block ownership check (`pendingDispatches.get(channelId) === abortController`) correctly handles the "newer dispatch took over" race; the older finalizer correctly defers cleanup to the newer one.
- `hasConnectedOnce` flag on the gateway client is the right shape — distinguishes initial connect from reconnect without leaking state.
- New error subclasses (`DispatchTimeoutError`, `DispatchAbortedError`) enable typed catch handling and produce clearer logs than string matching.
- Pre-aborted path now correctly drains the orphan dispatch promise (`dispatch.catch(() => {})`) — the exact bug R3 flagged is gone.
- Tests are tight and readable; vi mocks used minimally.

---

**Verdict: ✅ Ready to merge.** The three R3 blockers are addressed correctly. Open the four suggestions above as follow-up issues (especially #1 and #2) but don't hold the PR.
