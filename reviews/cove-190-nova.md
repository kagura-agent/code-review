# 🌠 Nova Review — cove#190
**PR**: plugin dispatch resilience — timeout, reconnect abort, per-channel tracking
**Verdict**: ⚠️ Needs Changes

---

## 1. Summary
The PR layers three resilience mechanisms onto the Cove plugin's inbound message path: a 120 s timeout, a reconnect-driven abort, and per-channel dispatch tracking. The intent is sound and closes a real production bug (#180). The wrapper itself (`createAbortableDispatch`) is correctly implemented with proper settle-once semantics and event-listener cleanup, and the tests cover the happy paths of the wrapper. However, the mechanism is **observational, not cancellative** — the `AbortSignal` is never threaded into `dispatchInboundDirectDmWithRuntime`, so "aborted" dispatches keep running in the background. Combined with a missing typing-cleanup path on timeout/abort, this leaves the plugin healthier than before but not actually cancelling work.

## 2. Critical Issues

### C1 — AbortSignal is never propagated to the underlying dispatch (`channel.ts:408–453`)
`createAbortableDispatch(dispatchInboundDirectDmWithRuntime({...}), ..., signal)` receives the dispatch **promise**, not the dispatch call. The signal is wired only to the wrapper's `Promise.race`-equivalent — the inner LLM/runtime work is not informed. Consequences:
- A stuck dispatch on timeout remains stuck, holding sockets, LLM streams, runtime locks, and any per-session mutex inside `dispatchInboundDirectDmWithRuntime`.
- On reconnect, every previously-stuck dispatch is "released" from the plugin's view but continues consuming resources on the runtime — under repeated restarts this **accumulates ghost dispatches** rather than fixing the leak.
- Per-channel "abort the old one, start fresh" can result in two concurrent dispatches for the same channel on the runtime side, which is exactly what the original handler `await` was guarding against.

**Action**: pass `signal` into `dispatchInboundDirectDmWithRuntime` (add support if the SDK lacks it) so abort actually propagates. If the SDK cannot currently honor a signal, file a follow-up issue and clearly document the wrapper as "release-only, not cancel" in code comments and the PR body.

### C2 — Typing indicator is leaked on timeout/abort (`channel.ts:~452–468`)
The new inner `try/catch` swallows `dispatch timeout` and `dispatch aborted` without rethrowing. The pre-existing outer `catch` block (which calls `typingCallbacks.onCleanup?.()`) is therefore never reached on these paths. Users will see a permanent "typing…" indicator on channels whose dispatches were timed out or aborted by reconnect.

**Action**: call `typingCallbacks.onCleanup?.()` inside the new catch (or move it into a shared `finally`) for both timeout and abort branches. Also covers any user-facing "thinking" state set during dispatch.

### C3 — Error identity by `err.message` string compare is fragile (`channel.ts:~456–462`)
Branching on `err.message === "dispatch timeout"` / `"dispatch aborted"` will silently swallow any unrelated downstream error that happens to share that message string, and will misclassify wrapped/rewritten errors.

**Action**: use sentinel `Error` subclasses (`DispatchTimeoutError`, `DispatchAbortedError`) or a `cause`/`code` field, and switch on `instanceof` / `err.code`.

## 3. Product Impact
- **Positive**: A single hung channel will no longer freeze the user 100 % — within 120 s another message will get through, and on reconnect the user can immediately retry. That is a real UX win.
- **Negative**: If C1 is not addressed, behavior on the runtime is *more* concurrent than before, which may surface different bugs (duplicate replies, ordering issues, runtime memory growth). The fix should be paired with monitoring of dispatch concurrency per session.
- **Latency surprise**: 120 s is long. Consider exposing this via env or shrinking; an upstream LLM call rarely needs >60 s. A shorter timeout makes the bug less painful in practice and reduces the C1 ghost window.

## 4. Suggestions
1. **`hasConnectedOnce` lives only on the in-memory instance** (`gateway-client.ts:39, 127–130`). If a duplicate `READY` ever arrives without a transport disconnect (server bug, RESUME race), a spurious `reconnect` is emitted and all pending dispatches are aborted. Consider gating on an explicit `disconnect`/`close` having occurred between READYs (e.g., `wasDisconnected` flag flipped in close handler) instead of just "second READY ever".
2. **Map iteration uses `for (const [, controller] of pendingDispatches)`** (channel.ts:~196 and tests). `pendingDispatches.values()` is more idiomatic and avoids the unused-key tuple.
3. **Magic constant**: `DISPATCH_TIMEOUT_MS = 120_000` is module-scoped; please export it (or accept it as a plugin option) so the tests can pin it and operators can tune.
4. **Tests do not assert log behavior or the cleanup of `pendingDispatches` after a real run through `messageCreate`.** Add an integration-style test that drives the `messageCreate` handler with a fake `dispatchInboundDirectDmWithRuntime` to verify: (a) map empties after success, (b) map empties after timeout, (c) typing cleanup runs, (d) reconnect path empties map. The current tests only exercise the wrapper and a hand-rolled map dance.
5. **Concurrency note**: `pendingDispatches.set` followed by `await createAbortableDispatch` is fine in JS single-thread, but log lines like `aborting ${pendingDispatches.size} pending dispatch(es)` may misreport size if a `set` happened in the same tick before reconnect handling. Minor.
6. **`as any` cast** on `runtime: patchedRuntime as any` — pre-existing but adjacent. Worth a follow-up to type properly.
7. **README/PR body** claims "Uses `AbortController` for clean cancellation". Reword to "for release of the awaiting handler" until C1 is addressed, to avoid misleading future maintainers.

## 5. Positive Notes
- `createAbortableDispatch` is well-written: settle-once guard, `clearTimeout` and `removeEventListener` on every terminal path, pre-aborted signal short-circuit, and `{ once: true }` on the abort listener. Nicely defensive.
- The `pendingDispatches.get(channelId) === abortController` check in `finally` correctly avoids clobbering a newer dispatch's controller — subtle and correct.
- Emitting `reconnect` only after the first successful READY is the right call (`hasConnectedOnce` pattern), modulo the duplicate-READY caveat in S1.
- Tests are clean, focused, and cover the wrapper edge cases (timeout, pre-abort, mid-flight abort, success, error propagation).
- Logging levels (warn for timeout/abort-old, info for reconnect-abort) are well chosen.
- Scope discipline: the diff is small (190/-2), additive, and does not touch unrelated areas.

---

**Final**: ⚠️ Needs Changes — address C1 (signal propagation or explicit documentation as "release-only"), C2 (typing cleanup leak), and C3 (error identity). The remaining items can ship as follow-ups.
