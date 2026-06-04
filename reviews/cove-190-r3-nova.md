# Nova R3 Review — cove#190 (plugin dispatch resilience)

**Rating: ⚠️ Needs Changes**

## 1. Summary

R3 substantively addresses the single 🔴 from R2: per-channel generation tokens are now incremented on **new dispatch**, **timeout**, and **reconnect**, and the three primary write paths (`sendOrEdit`, `deliver`, `onPartialReply`) check generation before emitting side-effects. This closes the stale-dispatch-can-still-send hole that Stella flagged.

However, **3 of the 4 yellow issues from R2 are unaddressed**, and one of them (unhandled rejection on pre-aborted signal) is now isolated enough that I'm escalating it to a hard correctness concern rather than a latent risk. The PR is close, but I'd ask for one more pass before merge.

## 2. Previous Issues Status

| # | R2 Issue | R3 Status | Notes |
|---|---|---|---|
| 1 | 🔴 Generation not incremented on timeout/reconnect | ✅ **Fixed** | Increment on reconnect (line ~213), on timeout (catch block), and on every new dispatch (gen = current + 1). All three deliver paths guarded. |
| 2 | 🟡 `DISPATCH_TIMEOUT_MS` hardcoded | ❌ **Unaddressed** | Still `const DISPATCH_TIMEOUT_MS = 120_000;` at module top. No env var, no plugin config field. |
| 3 | 🟡 `channelGeneration` map never cleaned up | ❌ **Unaddressed** | Map grows unbounded. Each unique `channelId` ever seen retains an integer entry forever. Cove DM channels are stable per-user so growth is slow, but there's no upper bound and no eviction. |
| 4 | 🟡 UnhandledPromiseRejection on pre-aborted signal | ❌ **Unaddressed** — escalating | See Critical Issues below. |
| 5 | 🟡 Not all dispatcher callbacks guarded | ⚠️ **Partially addressed** | `deliver` and `onPartialReply` are guarded. `typingCallbacks` (onToolStart/onCompactionStart/etc., wired into `dispatcherOptions`) and `onDispatchError` are **not** guarded — they will still fire for stale dispatches. |

**Escalation tally:** 1 fixed, 1 escalated, 2 unchanged-yellow, 1 partial.

## 3. Critical Issues

### 🔴 NEW/Escalated — `createAbortableDispatch` leaks unhandled rejection when signal is pre-aborted

```ts
if (signal.aborted) {
  clearTimeout(timer);
  reject(new DispatchAbortedError());
  return;  // ← returns BEFORE attaching .then() to dispatch
}
signal.addEventListener("abort", onAbort, { once: true });
dispatch.then(...);
```

If the caller passes an already-aborted signal, the function rejects synchronously and **never attaches a handler to the `dispatch` promise**. If that underlying `dispatchInboundDirectDmWithRuntime(...)` promise later rejects (timeout in upstream code, network error, runtime throw), Node will emit an `unhandledRejection` — which in modern Node can terminate the process depending on `--unhandled-rejections=strict` or future defaults.

In the current call site the controller is freshly created one line before use, so this path is only exercised in tests today. But:
- It's a real correctness bug in a published-shape helper.
- Reconnect path could plausibly race here in the future (e.g. if abort fires between `pendingDispatches.set` and `createAbortableDispatch` invocation — currently it can't because they're synchronous, but the gap is fragile).

**Fix:** always attach the `.then()` handler before the early-return, OR call `dispatch.catch(() => {})` as a swallow before returning.

```ts
if (signal.aborted) {
  clearTimeout(timer);
  dispatch.catch(() => {}); // prevent unhandled rejection
  reject(new DispatchAbortedError());
  return;
}
```

### ⚠️ Stale `typingCallbacks` and `onDispatchError` still fire

R2 issue #5 is only half-fixed. `typingCallbacks` is constructed once and threaded into `dispatcherOptions`, so callbacks like `onToolStart`, `onCompactionStart`, `onCleanup` invoked by upstream `dispatchInboundDirectDmWithRuntime` will still execute against a stale dispatch — meaning typing indicators and tool-progress messages may flap after a reconnect/timeout even though no reply will be sent.

This is user-visible (ghost "typing…" or "running tool X" indicators) but not a data-integrity issue. Worth one more guard, or wrap `typingCallbacks` in a gen-checking proxy.

## 4. Product Impact

**Good news:** The fundamental "stuck channel after restart" symptom from #180 is genuinely fixed now. R3's generation increments mean stale dispatches cannot send messages or edit drafts — the worst observable user impact (wrong/duplicate replies) is closed.

**Remaining risks (post-merge):**
- Slow memory growth from uncleaned `channelGeneration` map — likely irrelevant for typical Cove usage (bounded user set) but real for high-churn deployments.
- Ghost typing / tool-progress indicators after reconnect (cosmetic).
- Latent unhandled-rejection bug in a helper that's currently safe-by-call-site but easy to misuse.

I'd ship R2's behavior if forced, but R3's deltas are small and worth one more iteration.

## 5. Suggestions

1. **Fix unhandled-rejection in `createAbortableDispatch`** (one line — see above). Priority: must-fix.
2. **Guard `typingCallbacks` and `onDispatchError`** with the same generation check. Either wrap each callback or factor out a `withGenCheck(fn)` helper. Priority: should-fix.
3. **Make `DISPATCH_TIMEOUT_MS` configurable** via `account` or env (`COVE_DISPATCH_TIMEOUT_MS`), default 120_000. Priority: nice-to-have but cheap.
4. **Add cleanup for `channelGeneration`**: either evict on plugin disconnect/destroy, or piggyback on `pendingDispatches.delete(channelId)` finally-block when no new dispatch arrives within N minutes (LRU). Simplest: clear both maps in a `destroy()`/`close` handler. Priority: low.
5. **Test for pre-aborted unhandled rejection**: add a test where `dispatch` rejects after `signal.aborted` was true at construction — assert no unhandled rejection (use `process.on('unhandledRejection', ...)` listener in test).
6. **Document the `reconnect` event contract** on `CoveGatewayClient` — the "fires only on 2nd+ connection" semantics is subtle and worth a JSDoc on the event field.

## 6. Positive Notes

- Generation-token pattern is clean and applied consistently at the three primary write paths. Comment in `createAbortableDispatch` explicitly calls out the "release-only, not cancellation" semantics — exactly the right framing.
- `pendingDispatches.get(channelId) === abortController` identity check in `finally` is the correct way to avoid clobbering a newer dispatch's entry. Nice detail.
- `hasConnectedOnce` flag in gateway-client is the right place for the reconnect-vs-first-connect distinction.
- 7 new tests cover the main happy paths and the most likely failure modes; abort-after-set and reconnect-abort-all tests are well-targeted.
- Same-channel-replaces-pending logic with a warn log gives ops a clear breadcrumb.

---

**Verdict:** ⚠️ Needs Changes — one must-fix (unhandled rejection) plus the partial-callback-guard gap. Re-review after those land.

— 🌠 Nova (R3)
