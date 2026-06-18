# 🌠 Nova Review — cove PR #405

`refactor(plugin): adopt SDK delivery adapter + typing keepalive (#401)`

## Summary

Phase 1 of the SDK adapter migration. The new code correctly threads
`deliverWithFinalizableLivePreviewAdapter` through `dispatch.ts`, keeps
`sendOrEdit`/`editQueue`/`createFinalizableDraftLifecycle` untouched (good — that
is exactly the conservative move SPEC-401 §6.1 calls for), and adds 23 Group H
tests using the **real** adapter implementation via `vi.importActual`. Net
shape is sound and intentional. However, a careful trace through the SDK
adapter against cove's adapter object reveals a **fallback-path double-delete
bug** that the new tests don't catch, plus a regression in chunking semantics
and a few cleanup items. I'd hold this for one more rev — none of the fixes are
large.

**Verdict:** ⚠️ Needs Changes

---

## Critical Issues

### C1. Double-delete of draft message on edit-fallback path  (`dispatch.ts:97–117`)

Trace through `deliverFinalizableLivePreview` (SDK `live-DjttXqqq.js:44`)
when `canFinalize=true` and `editFinal` throws:

1. `params.draft.seal()` → cove adapter `draft.seal` → underlying lifecycle
   `seal()` (good).
2. `params.editFinal(previewId, edit)` throws → `handlePreviewEditError` returns
   `"fallback"`.
3. SDK runs `if (params.draft.discardPending) await params.draft.discardPending();`
   — cove's `discardPending` maps to the lifecycle's `stopForClear`, which **does
   not delete or null out `draftMessageId`**.
4. SDK runs `await params.deliverNormally(params.payload)` → cove's `freshSend`,
   which **manually deletes `draftMessageId` then sends**. `freshSend` does NOT
   reset the closure variable `draftMessageId = undefined`.
5. SDK `finally`: `if (delivered) await params.draft.clear();` — cove adapter's
   `draft.clear` runs `restClient.deleteMessage(channelId, draftMessageId)` a
   **second time** on the same id → 404, surfaced as
   `cove: failed to delete draft …: …` warn noise on every fallback.

The same trace fires on the `canFinalize=false` path (error-stopped draft): SDK
skips edit (because `liveState.canFinalizeInPlace=false`), goes to
`discardPending` → `freshSend` (delete + send) → `draft.clear` (delete again).

**Why the tests miss it:** H4a/H4b/H6c assert `deleteMessage` `toHaveBeenCalledWith("ch-1", "msg-draft-1")` but never check call count. The mocked lifecycle's `clear`/`discardPending` are no-ops, so the only delete you'd see in a stricter test is from `freshSend` + adapter `clear`. Add `expect(restClient.deleteMessage).toHaveBeenCalledTimes(1)` and these break.

**Fix options:**
- Easiest: in `freshSend`, after the manual delete, set `draftMessageId = undefined;` before sending. Then the adapter's `clear` is a no-op.
- Cleaner: drop the manual delete from `freshSend` entirely and rely on the SDK's `draft.clear()` call in `finally`. But this changes ordering (delete after send instead of before) — confirm that's acceptable for the user-visible "orphan is gone by the time the new message lands" guarantee.
- Or: make the adapter's `clear` clear-and-null:
  ```ts
  clear: async () => {
    const id = draftMessageId;
    draftMessageId = undefined;
    if (id) { try { await restClient.deleteMessage(channelId, id); } catch (e) { … } }
  }
  ```

### C2. `freshSend` lost chunking; messages > 4000 chars will now fail

Old code chunked through `sendDurableMessageBatch` with `formatting:
{ textLimit: COVE_TEXT_CHUNK_LIMIT }`. New code:

```ts
await restClient.sendMessage(channelId, text);   // one shot, no chunking
```

Cove's REST API has a hard text limit per message (the existence of
`COVE_TEXT_CHUNK_LIMIT = 4000` in `types.ts` and its use in `channel.ts:55`
strongly implies this). The `editFinal` path has the same issue —
`restClient.editMessage` is called with the full final text.

PR #404 reverted from `sendDurableMessageBatch` because it silently swallowed
errors, which is a legitimate reason — but the reversion threw out the chunking
baby with the bathwater. Long agent replies (long-form answers, code dumps,
multi-paragraph plans) will either fail outright or get truncated server-side.

**Action:** Either
1. Hand-roll a simple chunking loop in `freshSend` (and possibly `editFinal` for
   edit-in-place — though for that path users may accept that very-long edits
   fall back to fresh send via the new "fallback" handler), splitting at
   `COVE_TEXT_CHUNK_LIMIT` with sensible boundaries (newline/sentence), OR
2. Restore `sendDurableMessageBatch` but wrap the `deps.cove` callback with the
   error-shape fix that motivated #404, OR
3. Document and add a test asserting the new behavior is intentional — i.e.,
   "messages > 4000 chars are no longer chunked, will surface as plugin error."
   I don't believe that's the intent.

The PR description names this as a known concern ("Does freshSend revert from
sendDurableMessageBatch to direct restClient.sendMessage lose chunking?") but
the implementation just… loses chunking.

### C3. Tests under-exercise the new adapter behavior

The test file does the right thing by importing the **real**
`deliverWithFinalizableLivePreviewAdapter` (good — confirmed by
`vi.importActual` at line 40 of the diff). But the mocked
`createFinalizableDraftLifecycle` returns a bag of no-op mocks:

```ts
return { update, seal: vi.fn(async () => {}),
         discardPending: vi.fn(async () => {}),
         clear: vi.fn(async () => {}),
         loop: { flush: vi.fn(async () => {}) } };
```

Consequences:
- `seal()` never sets `draftState.final = true` in tests → `sendOrEdit`'s guard
  `draftState.stopped && !draftState.final` is never exercised in the
  post-seal state. The pre-#405 code set `draftState.final = true` explicitly
  before `seal()`; the new code relies on the lifecycle's `seal()` to do it.
  Since the mock seal is a no-op, **no test validates that the lifecycle's
  real seal flips `final` and that `sendOrEdit` honors it**. This is the exact
  contract the PR removes the explicit `draftState.final = true` line for; it
  must be tested with the real lifecycle.
- `loop.flush()` no-op → the ordering guarantee "all queued partials drain
  before the final edit lands" is not exercised. Race window: if a throttled
  edit is still pending when `deliver` runs, real `flush()` waits for it; the
  mock returns immediately. Reverse: a test that queues a slow `sendOrEdit`,
  then calls `deliver`, then asserts the slow call resolves **before** the
  final `editMessage` would catch a regression where the adapter forgets to
  `flush`. Currently nothing does this.
- `adapter.clear` runs (because that's defined in cove code, not the
  lifecycle), but `clearMessageId` (closure-mutator wired into the real
  lifecycle's `clear`) is never invoked — hiding C1.

Recommend adding at least one integration-style test with the **real**
lifecycle (just mock the rest client) to cover the seal/flush/clear handoff.

---

## Suggestions

### S1. Stale doc comment + dead import (`dispatch.ts:2,95–96`)
- Two JSDoc comments above `freshSend`; the old one references
  `sendDurableMessageBatch` which is gone. Delete the first line.
- `COVE_TEXT_CHUNK_LIMIT` is still imported but no longer referenced anywhere
  in `dispatch.ts`. Will trip lint (unused import) — drop it or, better, use it
  to implement C2.

### S2. Redundant typing kick at dispatch start (`dispatch.ts:28, 198`)
The preamble does `restClient.sendTyping(channelId).catch(() => {})` then
`runDispatch` also calls `await typingCallbacks.onReplyStart?.()` which starts
typing again. Two typing frames at t=0 is harmless but redundant; the PR's
stated goal is "typing fires at dispatch start and maintains 5s keepalive" —
the keepalive (which is what was missing) is what `onReplyStart` gives you.
The eager `sendTyping` call is now superseded; consider removing it so the
single source of truth is the keepalive callbacks.

### S3. `liveState` not threaded across calls
The adapter call returns a `liveState` (preview-finalized, etc.) and cove
discards it. Within a single dispatch this is moot — `deliver` is invoked once
per turn. But Phase 3 in SPEC-401 says to adopt `LiveMessageState` tracking;
when you get there, capture the return and persist it so re-entrant deliveries
in the same turn observe `phase: "finalized"` and don't try to re-edit. Today
it's latent because `deliver` is called once; document this assumption (or
guard it) since a future change could re-invoke `deliver`.

### S4. `buildFinalEdit` falsy check (`dispatch.ts:113`)
```ts
buildFinalEdit: (payload) => payload.text || undefined,
```
Caller already guards `if (!text) return;` before invoking the adapter, so
`payload.text` is always truthy here. The `|| undefined` is dead. Either drop
it or, if you want defense-in-depth in case some future caller bypasses the
outer guard, keep it but with a clearer expression
(`payload.text === "" ? undefined : payload.text`) — note that the SDK's
contract is "return `undefined` to skip edit-in-place" (line 60 of the SDK
source), so the intent is right; just signal it clearly.

### S5. Test H4d's invariant check inside `mockImplementation`
```ts
restClient.editMessage.mockImplementation(async () => {
  expect(cleanupCalls).toEqual(["cleanup"]);  // assertion inside mock
  return { id: "msg-draft-1" };
});
```
Assertions inside a mock implementation are easy to misread and (depending on
Vitest's expect propagation) can produce confusing failure stacks. Prefer
capturing the timing into an array and asserting at the end of the test, same
way `callOrder` is used in H1a. Cosmetic, not blocking.

### S6. H1a `callOrder` over-asserts internal ordering
`expect(callOrder).toEqual(["send", "edit", "edit", "edit"])` — fine if you
want to lock the exact number of edit calls, but the test only made 3
streaming updates + 1 final, and the 250ms throttle in a real lifecycle could
coalesce them. With a mocked lifecycle whose `update` doesn't throttle, every
`capturedSendOrEdit` call goes through 1:1, so the assertion happens to hold.
This is another spot where mocking the lifecycle blurs what's actually being
verified — the test is really asserting "if you call the bridge N times it
calls REST N times," which is a test of `sendOrEdit`, not of the adapter.

### S7. H5a/H5b mutation of `pendingDispatches` as supersession simulation
Test uses `opts.pendingDispatches.set("ch-1", new AbortController())` to
simulate a newer dispatch arriving. Realistic, but note that in production the
new dispatch would also call `abortController.abort()` on the prior controller
(or should — actually, looking at `dispatch.ts`, the second dispatch only does
`pendingDispatches.set(...)`, never `previous.abort()`). The tests are
faithful to production behavior, but this is itself a smell: the prior
controller's `signal` is never aborted, so anything awaiting it never wakes —
relies entirely on `isCurrent()` polling. Out of scope for this PR but worth a
follow-up issue.

### S8. SPEC-401 §6.3 says to remove `draftState.final = true` — confirm intent
The PR removes the explicit line, relying on `seal()` (via the lifecycle) to
set `final`. The lifecycle's `seal` does `params.markFinal(); loop.stop();
await loop.waitForInFlight();` — so `final=true` is set BEFORE the in-flight
wait, same ordering as before. ✅ Intent preserved. Add a one-line comment in
`dispatch.ts` noting "final flag now set by `draft.seal()`" so the next
reader doesn't wonder why the explicit set is gone.

---

## Positive Notes

- **Conservative scope.** Keeping `sendOrEdit`/`editQueue`/lifecycle untouched
  and only swapping the deliver path is exactly what SPEC-401 §6.1 required
  after the #399 burn. The blast radius of this PR is well-controlled.
- **Real adapter in tests via `vi.importActual`.** This is the right pattern —
  testing through the adapter rather than mocking it out catches schema/shape
  drift when the SDK evolves. Far better than naive `vi.fn()` stubs.
- **Typing keepalive fix lives in `runDispatch`.** Putting `onReplyStart`
  inside `runDispatch` (line 198) instead of at the top means typing tracks
  the *actual* generation window, not just the dispatch envelope. The
  before/after is a real UX improvement.
- **H2a/H2b distinguish "empty progress" from "non-empty progress"** — the
  tracker contract test (`getCombinedText() === ""` → no `draft.update`) is
  precisely the kind of edge case that breaks silently in production. Good
  catch by whoever authored these.
- **`logPreviewEditFailure` wired up properly** (`dispatch.ts:116–118`),
  preserving the prior `cove: final edit failed: …` warn signal in logs. No
  silent failure mode introduced for the edit-in-place attempt itself.
- **SPEC-401.md is genuinely good.** §6 (Risks) explicitly calls out the
  failure modes from #399 and #404, the mitigation for each, and what's
  deferred to Phase 2 with test gating. That kind of risk-mapped phased plan
  is exactly what large refactors need.

---

## Path: `/home/kagura/.openclaw/workspace/code-review/reviews/cove-405-nova.md`
