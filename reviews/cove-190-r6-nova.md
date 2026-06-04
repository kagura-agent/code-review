# PR #190 — Round 6 Review (🌠 Nova)

**Repo:** kagura-agent/cove
**PR:** plugin dispatch resilience — timeout, reconnect abort, per-channel tracking
**Verdict:** ⚠️ **Needs Changes** (down from R5 ⚠️ — same issues, partial progress)

---

## 1. Summary

R6 makes real progress on the queued side-effect race by adding `isCurrent()` guards inside the `editQueue` callback and after `draft.seal()` in `deliver`. The reference-equality model (`pendingDispatches.get(channelId) === abortController`) is correctly applied across most callback boundaries (onPartialReply, onToolStart, onItemEvent, onPlanUpdate, etc.) — this is good defense-in-depth.

However, **3 of 4 R5 issues remain unresolved or only partially fixed**:

- Issue 1 (queued side-effect race): narrowed but not closed — REST writes after the inner `isCurrent()` check still proceed if abort fires mid-await.
- Issue 2 (async handler ordering race): **unchanged** — `AbortController` is still installed *after* the `setTimeout(1)` yield, so handler-resume ordering still controls dispatch identity, not message arrival ordering.
- Issue 3 (plugin shutdown doesn't abort pending dispatches): **unchanged** — no teardown path iterates `pendingDispatches`.
- Issue 4 (configurable timeout): **unchanged** — `DISPATCH_TIMEOUT_MS = 120_000` still hardcoded.

Per the **escalation rule**, all remaining issues stay at 🟡 (no downgrade).

---

## 2. Previous Issues Status

### 🟡 Issue 1 — Queued side-effect race (PARTIAL FIX)
**R6 changes:**
- `sendOrEdit` now checks `isCurrent()` both before enqueuing *and* inside the `editQueue` callback. ✅
- `deliver` checks `isCurrent()` before `await draft.seal()` *and* after. ✅

**Remaining gap:**
After the in-queue `isCurrent()` check in `sendOrEdit`, the code proceeds to call `rest.editMessage(...)` / `rest.writeMessage(...)` (these are the REST writes — not shown in diff but implied by the existing structure). If abort fires *during* the awaited REST call, the call still completes server-side and a stale REST write lands. Same for `deliver`'s post-seal write path.

The JSDoc explicitly acknowledges this: *"this is release-only, not cancellation — the underlying dispatch continues running but side effects … are guarded by per-channel AbortController reference equality so stale dispatches cannot send messages."* — but reference equality only blocks *new* writes, not in-flight ones. The window is narrow but real, especially under same-channel rapid replacement where C1's REST write can race C2's first message.

**Recommendation:** Pass `abortController.signal` into the REST client so the actual HTTP request can be aborted, or accept the window explicitly (the JSDoc is honest about it; that may be sufficient for ship).

**Status:** 🟡 narrowed, not closed.

---

### 🟡 Issue 2 — Async handler ordering race (UNCHANGED)
The `AbortController` setup remains *after* `await new Promise<void>((resolve) => setTimeout(resolve, 1))`. Sequence:

```
1. messageCreate fires for M1 (channel X)
2. M1 handler begins, hits setTimeout(1) await
3. messageCreate fires for M2 (same channel X)
4. M2 handler begins, hits setTimeout(1) await
5. (whichever timer resolves first wins the race)
6. Winner registers its controller; loser then sees it as "existing" and aborts it
```

In Node's event loop, two 1ms timers generally resolve FIFO, so in practice M1 wins. But this is **not guaranteed** — any prior microtask churn, GC pause, or additional await inside the handler body can reorder them. When M2 wins the race, M1's later resume will abort M2's dispatch — i.e., a late-arriving handler kills the newer message's dispatch.

**Fix:** Move the controller registration to the **synchronous prologue** of the messageCreate handler, before any await:

```ts
gatewayClient.on("messageCreate", (message) => {
  const channelId = message.channel_id;
  const existing = pendingDispatches.get(channelId);
  if (existing) existing.abort();
  const abortController = new AbortController();
  pendingDispatches.set(channelId, abortController);
  // ...then enter async work
  void (async () => { /* existing async body, using captured abortController */ })();
});
```

This makes dispatch identity track message arrival order deterministically.

**Status:** 🟡 unchanged from R5.

---

### 🟡 Issue 3 — Plugin shutdown doesn't abort pending dispatches (UNCHANGED)
No `stop`/`destroy`/`onUnload` path in the diff iterates `pendingDispatches` and aborts them. On plugin teardown, in-flight dispatches keep running until timeout (120s) or natural completion, potentially holding runtime references and (per Issue 1) writing stale messages.

**Fix:** In whichever lifecycle hook handles plugin shutdown (likely where `gatewayClient.destroy()` is called), add:
```ts
for (const c of pendingDispatches.values()) c.abort();
pendingDispatches.clear();
```

**Status:** 🟡 unchanged from R5.

---

### 🟡 Issue 4 — Configurable timeout (UNCHANGED)
`const DISPATCH_TIMEOUT_MS = 120_000;` remains a top-level module constant. Sixth round flagging this — small change, persistent miss.

**Fix:** Read from `account` or plugin config with a default fallback:
```ts
const timeoutMs = account.dispatchTimeoutMs ?? DEFAULT_DISPATCH_TIMEOUT_MS;
```

**Status:** 🟡 unchanged from R5.

---

## 3. Critical Issues (new)

None blocking. The new code is structurally sound; correctness gaps are in the items above.

### Minor observations on new code
- **`createAbortableDispatch` already-aborted branch**: `dispatch.catch(() => {})` is attached to prevent unhandled rejection of the orphaned dispatch. Good. But in the non-already-aborted abort path (`onAbort`), the `dispatch` promise is *not* given a `.catch()` swallow — if it rejects later after abort, it becomes an unhandled rejection. Add `dispatch.catch(() => {})` in `onAbort` too, or attach it unconditionally at the top.
- **Event listener cleanup on timeout**: In the timeout branch, `signal.removeEventListener("abort", onAbort)` is not called. Minor leak per timed-out dispatch (one listener per signal, controllers are short-lived so usually fine, but tidy to fix).
- **`hasConnectedOnce` is never reset**: If the gateway client is reused across long sessions this is fine; if it's recycled, ensure reset semantics are intentional. Not a bug — just worth a one-line comment.

---

## 4. Product Impact

- **Happy path:** Resilience is meaningfully better. Reconnect storms, duplicate messages, and stuck dispatches no longer wedge a channel indefinitely.
- **Edge case under R5 Issue 2:** If two messages for the same channel land within the same event-loop tick under load, the *newer* message's dispatch can be aborted by the older handler's late resume. User sees: typing indicator stops, no reply, then a 120s timeout warning. Rare but observable.
- **Edge case under R5 Issue 1:** A stale REST edit can land just after a newer dispatch begins, causing a flicker (old text briefly overwrites new). Narrow window, hard to repro, but possible.
- **Plugin shutdown:** Restart/reload during active dispatch holds resources up to 120s. Tolerable, not great.

Net: ship-able for most workloads, but the ordering race (Issue 2) is the one I'd want closed before treating this as "done".

---

## 5. Suggestions

1. **[Highest leverage]** Move `AbortController` registration to the synchronous prologue of the messageCreate handler (fixes Issue 2 cleanly, ~5 lines).
2. Add plugin teardown abort loop (Issue 3, ~3 lines).
3. Make timeout configurable (Issue 4, ~2 lines).
4. Plumb `abortController.signal` into REST writes to close Issue 1's residual window, *or* document the trade-off in code comments and ship.
5. Tidy `createAbortableDispatch`: swallow rejection in `onAbort` path; remove abort listener in timeout path.

---

## 6. Positive Notes

- The `isCurrent()` helper + reference-equality model is the right abstraction. Applied consistently across **all** dispatcher callbacks — that's thorough, not lazy.
- New `deliver` post-seal recheck is exactly the fix that was missing in R5; nicely targeted.
- `createAbortableDispatch` is well-documented, including an honest disclosure of its release-only semantics. That kind of comment ages well.
- Test coverage for the new utility is solid (5 unit tests + 2 integration-style for reconnect/replace flows).
- `hasConnectedOnce` correctly distinguishes initial connect from reconnect — clean state machine.

---

**Final rating:** ⚠️ **Needs Changes** — primary blocker is Issue 2 (handler ordering race); Issues 3 & 4 are quick wins that should land in the same PR; Issue 1's residual is acceptable if documented.
