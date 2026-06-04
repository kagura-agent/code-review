# 🌠 Nova — PR #190 Round 2 Review

**PR:** kagura-agent/cove#190 — plugin dispatch resilience
**Round:** 2
**Verdict:** ⚠️ Needs Changes (small) — close to ready; one architectural caveat is now documented but worth a final knob.

---

## 1. Summary

Author kept the high-level approach (timeout race + reconnect abort + per-channel tracking) but added two important pieces in R2:

1. **Named error classes** — `DispatchTimeoutError`, `DispatchAbortedError` — replacing string compare.
2. **Per-channel generation counter** (`channelGeneration: Map<string, number>`) — guards `sendOrEdit`, `deliver`, and `onPartialReply` so that **stale dispatches cannot send messages**, even if they keep running.

The doc comment on `createAbortableDispatch` is honest about the trade-off:

> "this is release-only, not cancellation — the underlying dispatch continues running but side effects (message delivery, streaming edits, typing indicators) are guarded by per-channel generation tokens so stale dispatches cannot send messages."

This is the right call given the SDK doesn't accept an AbortSignal. The output channel is now correctly fenced.

---

## 2. Previous Issues Status

| # | R1 Issue | Severity | Status | Evidence |
|---|----------|----------|--------|----------|
| 1 | Abort is observational, not cancellative | 🔴 | **Mitigated** (not fixed) | Generation-token guards added at all 3 emission sites (`sendOrEdit`, `deliver`, `onPartialReply`). Underlying dispatch still runs to completion in the background, but it can no longer cause ghost messages or edits. Acceptable per documented trade-off. |
| 2 | Typing indicator leaked on timeout/abort | 🔴 | **Fixed** ✅ | `typingCallbacks.onCleanup?.()` called in both `DispatchTimeoutError` and `DispatchAbortedError` catch arms (channel.ts L478, L481). |
| 3 | Error identity by string compare | 🟡 | **Fixed** ✅ | `instanceof DispatchTimeoutError` / `DispatchAbortedError`. Robust to message changes. |

R1 suggestions:
- Configurable timeout — ❌ still hardcoded `DISPATCH_TIMEOUT_MS = 120_000`. Recommended (see §5).
- `hasConnectedOnce` false positive — ✅ logic is correct: flag is set only inside READY branch, after the first READY. A failed handshake (WS open but no READY) won't flip it.
- Integration tests — ⚠️ unit tests only; no test that exercises actual `dispatchInboundDirectDmWithRuntime` + stale-callback no-op behavior. See §5.
- Listener cleanup — ⚠️ no `pendingDispatches.clear()` / `channelGeneration.clear()` on plugin shutdown. Minor (maps die with the closure), but if `start()` can be re-entered the `reconnect` listener accumulates. See §5.

**Escalation rule applied:** R1 #1 stays visible. It went from "broken" → "mitigated via fence at output sites" — but it is not "fixed" in the original sense. Calling it out so future readers don't think `abort()` cancels the dispatch.

---

## 3. Critical Issues

None. The two 🔴 from R1 are either fixed (#2) or mitigated to safe behavior (#1).

---

## 4. Product Impact

**What this PR delivers:**
- Stuck channel after restart → unblocks after 120s max. ✅
- Reconnect event → all per-channel pending dispatches release immediately. ✅
- Rapid duplicate message in same channel → previous one is fenced out (no double-reply). ✅
- No more zombie typing indicators on timeout/abort. ✅

**What still bites:**
- A timed-out dispatch keeps consuming LLM tokens / network / memory until it naturally settles. For a runaway dispatch this is wasted spend, not correctness. Worth a `// TODO` once the SDK exposes AbortSignal.
- 120s is a long UX gap for the user who hit the bug. With no configurability, you can't tune per environment.

Net: this PR resolves the user-visible "channel forever dead" failure mode reliably, which is the bug in #180. Ship it after addressing the small items below.

---

## 5. Suggestions

**Should-do before merge:**

1. **Make `DISPATCH_TIMEOUT_MS` configurable** via env or `account` config. 120s as default is fine, but a deployment under high load may want 60s, and a long-thinking-model deployment may want 300s. Trivial change; large operational payoff.

2. **Clean up `channelGeneration` and `pendingDispatches`** in the same `finally` where you remove the controller. Today `channelGeneration` only ever grows. With per-DM ephemeral channel IDs (Discord threads, etc.) this is a slow leak.

   ```ts
   } finally {
     if (pendingDispatches.get(channelId) === abortController) {
       pendingDispatches.delete(channelId);
       channelGeneration.delete(channelId); // safe: only the active gen mattered
     }
   }
   ```
   (Only delete generation when no newer dispatch claimed the slot — same guard as the controller.)

**Nice-to-have:**

3. **One integration test** asserting that after `controller.abort()` (or timeout), a late call into `sendOrEdit` / `deliver` is a no-op due to generation mismatch. The R2 unit tests cover the race primitive in isolation but not the fence — i.e., the mitigation for the R1 #1 critical issue is not tested.

4. **`gatewayClient.off("reconnect", ...)` on plugin stop** (if `start()` lifecycle supports re-entry). Avoids listener accumulation if the plugin is restarted in-process.

5. Consider logging the LLM/tool work that proceeds after a timeout (token count, duration) once visible — useful for ops dashboards to spot the cost of the documented "release-only" behavior.

---

## 6. Positive Notes

- The error class refactor is clean — exported, named, instanceof-checked, easy to extend.
- The generation-token pattern is the **right** answer to "SDK doesn't accept AbortSignal" — well-placed at all three emission sites, no missed callback.
- The `finally` block correctly compares identity (`pendingDispatches.get(channelId) === abortController`) before deleting, avoiding the classic "newer dispatch wipes its own slot" bug.
- Doc comment on `createAbortableDispatch` is honest about semantics — exactly the kind of comment future-me wants to read.
- `hasConnectedOnce` placed inside the READY branch (not OPEN), so handshake failures don't poison the flag. Subtle and correct.
- Tests cover the four orthogonal cases (timeout / resolve / mid-flight abort / pre-aborted) plus reconnect-fanout and same-channel replace. Good shape.

---

**Final verdict:** ⚠️ Needs Changes — small, mostly hygiene. Address #1 (configurable timeout) and #2 (map cleanup) and this is ready.

— 🌠 Nova
