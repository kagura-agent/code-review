# 🌠 Nova Review — cove#457

**PR:** fix(plugin): add diagnostics for silent reply loss (#419)
**Scope:** +37 / -8, single file (`packages/plugin/src/dispatch.ts`)
**Rating:** ✅ **Ready**

---

## Summary
Pure diagnostic-logging PR. Every previously-silent early-return / bail-out in the `deliver` / `freshSend` / `editFinal` / `sendOrEdit` chain now emits a `log.warn` (or `log.info` for the legitimate empty-text case) with `channelId` + `message.id` + relevant context (text length, abort state). No happy-path behavior change. The `warnedSendOrEditAborted` flag correctly guards against per-chunk log flooding while being scoped per `dispatchMessage` invocation. The `try/catch/throw` around `outboundBridge.sendText` in `freshSend` preserves original exception semantics (logs then rethrows) so the outer `catch` in the `try/finally` around line 307 still handles it. Orphaned-draft cleanup log now includes `message.id` and `isAborted()` state, which is exactly the missing signal needed to root-cause the next silent-loss occurrence.

## Critical Issues
None.

## Product Impact
- **User-facing behavior:** none. All changes are log emissions.
- **Log volume:** slight increase. `sendOrEdit` uses a per-dispatch dedupe flag, so worst case is +1 warn per aborted dispatch. `deliver` empty-text uses `info` (correctly, since tool-only turns are legitimate); on chatty tool-heavy conversations this can become noisy but stays below `warn` so shouldn't page anyone.
- **Ops win:** next occurrence of silent reply loss will pinpoint which bail point fired — matches PR intent precisely.

## Suggestions (non-blocking)
1. **`dispatch.ts:180-183` — dead-ish second abort check.** After adding the empty-text branch, `deliver` now has three sequential guards: abort → empty text → abort. The second `isAborted()` check is essentially a synchronous no-op (nothing awaits between it and the first check). Pre-existing, but now that you're touching it, consider dropping it. If you keep it, the diagnostic log for it (`"deliver skipped (post-text)"`) will realistically never fire, which will confuse a future debugger reading logs looking for it.
2. **Log-level consistency.** `deliver` empty-text is `info`; every other diagnostic in this PR is `warn`. Reasonable (tool-only turns are legitimate), but worth a one-line comment on the log call itself — the PR description explains it, but log reviewers won't have that context.
3. **`freshSend` sendText wrap.** The `catch (e: any) { warn; throw e; }` is fine, but note the outer `log.info` at line 109 (`"cove: reply → ..."`) prints *before* the send attempt. If the send fails, logs will show "reply → [X] (N chars)" immediately followed by "freshSend sendText failed", which is fine but could read as contradictory. Consider moving the `info` line *after* successful send, or rephrasing it to `"cove: sending reply →"` to make the two-log sequence read cleanly. Not blocking.
4. **String-interpolation cost.** All new `warn` sites unconditionally build the message string even when `log?.warn` is a no-op. Given cadence (per-dispatch, not per-token), this is trivially fine, but if a lazy-logger pattern exists elsewhere in the plugin (`log.warn(() => ...)`) it would be consistent to use it. Skip if no such pattern exists.

## Positive Notes
- **Dedupe flag on `sendOrEdit`** — smart. Without it this would emit a warn per stream chunk on abort and drown out real signal.
- **All logs include the primary correlation keys** (`channelId`, `message.id`) — exactly what a log-only diagnosis needs.
- **Text-length included** on the higher-cost sites (`freshSend`, `editFinal`, post-text `deliver`) — helps distinguish "large-payload edge case" from "small-payload race".
- **`freshSend` catch rethrows** — no silent swallowing, preserves existing error propagation. This is one of the AI-code failure modes explicitly worth flagging when done wrong; here it's done right.
- **Orphaned-draft log** picks up `message.id` + `isAborted()` — the two facts you actually need to distinguish "aborted mid-flight" from "delivery silently no-op'd".
- **Scope discipline** — PR body says "diagnostic logging only, no behavior change" and the diff matches exactly. No scope creep, no drive-by refactors.
- **Comment added above orphaned-draft block** clarifies intent for future readers ("runs regardless of abort state").

---

**Verdict:** Ship it. This is exactly the shape a diagnostics-only PR should have — minimal surface, high signal-to-noise, no behavior drift. Follow-up (root cause + fix) will be enabled by the next repro.
