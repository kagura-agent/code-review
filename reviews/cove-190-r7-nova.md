# Cove PR #190 — Round 7 Review (🌠 Nova)

**Verdict: ✅ Ready**

## 1. Summary

R7 addresses all three R6 carry-overs cleanly. The AbortController is now installed in a synchronous prologue before any await, eliminating the ordering race. Plugin shutdown aborts pending dispatches. Timeout is config-driven via `channels.cove.dispatchTimeoutMs` with a 120s default.

Diff is +232/-2; well-scoped, tests added for the helper and the two cancellation flows.

## 2. Previous Issues Status

| # | R6 Issue | Status | Evidence |
|---|----------|--------|----------|
| 1 | 🔴 Async handler ordering race (controller installed after awaits) | ✅ Fixed | Lines ~236–245 of channel.ts: `existingDispatch` lookup, abort, and `pendingDispatches.set(channelId, abortController)` all execute **before** any `await` in the handler (the WS typing send and `loadDirectDm()` come after). `isCurrent()` closes over the controller captured in the synchronous prologue, so all side-effect guards check the *original* controller for this message. |
| 2 | 🔴 Plugin shutdown doesn't abort pending dispatches | ✅ Fixed | `ctx.abortSignal` handler now iterates `pendingDispatches`, calls `.abort()` on each, clears the map, then destroys gatewayClient. |
| 3 | 🟡 Configurable timeout | ✅ Fixed | `dispatchTimeoutMs = (channelEntry as any).dispatchTimeoutMs ?? DEFAULT_DISPATCH_TIMEOUT_MS`. Read per-message so live config updates take effect. |

No regressions detected on previously-fixed items (queued side-effect race from R5, reference-equality guards from R4).

## 3. Critical Issues

**None.** Code is mergeable.

## 4. Product Impact

- Stuck-channel failure mode from #180 is fully mitigated by three independent mechanisms (timeout, reconnect-abort, supersede-on-new-message). Defense-in-depth is appropriate here given the bug was unreproducible in dev.
- 120s default timeout is conservative — most legitimate dispatches complete in <30s. Per-channel override lets operators tune for slow tool-heavy channels without affecting fast ones.
- User-visible behavior on abort: typing indicator is cleared (`typingCallbacks.onCleanup?.()` in catch branch). No half-finished message remains because `isCurrent()` gates `deliver`/`sealAndPublish`. Clean UX.

## 5. Suggestions (non-blocking, future polish)

1. **Type the channel config field properly** — `(channelEntry as any).dispatchTimeoutMs` casts away safety. Add `dispatchTimeoutMs?: number` to the cove channel config schema (wherever `channels.cove` is typed). Small follow-up PR.
2. **Validate `dispatchTimeoutMs`** — a misconfigured `0` or negative value would cause `setTimeout` to fire immediately and abort every dispatch. Consider `Math.max(1000, configured ?? DEFAULT)` or a startup-time warning.
3. **Document the release-vs-cancellation semantic in #180** — the doc-comment on `createAbortableDispatch` is great; mirror that note in the issue/PR description so future readers understand the underlying dispatch keeps running. (Resources are bounded by the dispatcher itself; not a leak, but worth flagging.)
4. **Metric/log on timeout** — already logs a warn. Consider bumping to error severity or emitting a counter so operators can detect a chronic-timeout regression early.
5. **Integration test** — current tests cover the helper and Map semantics, not the actual `messageCreate` → `createAbortableDispatch` → finally-cleanup wiring. A single end-to-end test that injects two rapid messageCreate events for the same channel would lock in the synchronous-prologue invariant against future refactors.

## 6. Positive Notes

- The doc-comment on `createAbortableDispatch` explicitly calling out "release-only, not cancellation — side effects guarded by per-channel AbortController reference equality" is exactly the kind of design rationale that prevents future regressions. 👏
- Synchronous prologue with the explanatory comment ("two same-channel messages overlapping on await boundaries could abort the wrong one") shows the fix was made with the failure mode understood, not by trial-and-error.
- `finally` block uses reference-equality (`pendingDispatches.get(channelId) === abortController`) to avoid clobbering a newer entry — correct and important.
- `signal.aborted` early-path in `createAbortableDispatch` attaches `.catch(() => {})` to the orphaned dispatch promise to prevent unhandled rejection. Nice attention to detail.
- Reconnect event gated by `hasConnectedOnce` flag — won't spuriously abort on first connect.
- Test for "rejects with dispatch error when dispatch fails before timeout" covers the otherwise-silent error-passthrough path.
- 7 new tests, build/typecheck clean, 154 tests pass. Good hygiene.

---

**Recommendation: Merge after Luna's review.** All three R6 issues resolved with code that demonstrates understanding of the failure modes. Suggestions are polish, not blockers.
