# Consolidated Review — cove PR #405

**PR:** kagura-agent/cove#405
**Title:** refactor(plugin): adopt SDK delivery adapter + typing keepalive (#401)
**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 2.5 Pro)
**Date:** 2026-06-18

---

## Verdict: ⚠️ Needs Changes

The adapter wiring is architecturally sound and the conservative migration approach (keeping `sendOrEdit`/`editQueue`/lifecycle untouched, only swapping `deliver()`) is exactly right after the PR #399 burn. The typing keepalive fix is a real UX improvement. However, three issues need resolution before merge.

---

## Critical Issues

### 1. Lost chunking for long messages (all 3 reviewers)

`freshSend()` now uses `restClient.sendMessage(channelId, text)` directly, replacing `sendDurableMessageBatch` with `formatting: { textLimit: COVE_TEXT_CHUNK_LIMIT }`. Messages exceeding 4000 chars will fail or truncate. The `editFinal` path has the same issue.

`COVE_TEXT_CHUNK_LIMIT` is still imported but now unused — confirms this is unintentional.

**Fix options:**
- Hand-roll chunking in `freshSend` splitting at `COVE_TEXT_CHUNK_LIMIT`
- Restore `sendDurableMessageBatch` but fix the silent-failure error shape from #404
- At minimum, add a test with text > 4000 chars to lock down the intended behavior

### 2. Double-delete of draft on fallback path (Stella + Nova, Vega corroborates)

When `editFinal` fails and the adapter falls back:
1. `freshSend()` deletes `draftMessageId` then sends
2. SDK's `finally` block calls `adapter.clear()` which deletes the same `draftMessageId` again → 404 warn noise

`freshSend` never nulls `draftMessageId` after deletion, so `adapter.clear` sees it as still present.

**Fix:** Either null `draftMessageId` in `freshSend` after deletion, or remove the manual delete from `freshSend` and let `adapter.clear` own it exclusively.

### 3. Post-seal `isCurrent()` guard lost inside adapter (Stella)

The old `deliver()` checked `isCurrent()` both before and after `await draft.seal()`. The new code checks once before entering `deliverWithFinalizableLivePreviewAdapter()`, but the SDK then awaits `flush`/`seal` and calls `editFinal` without a staleness re-check. If a dispatch is superseded during seal, `editFinal` can still fire on a stale context.

**Fix:** Have `editFinal` and `deliverNormally` check `isCurrent()` internally and no-op when stale.

---

## Suggestions

1. **Stale doc comment + dead import** — Two JSDoc comments above `freshSend`; old one references removed `sendDurableMessageBatch`. `COVE_TEXT_CHUNK_LIMIT` import is now unused.

2. **Redundant typing kick** — Preamble does `restClient.sendTyping()` then `runDispatch` calls `onReplyStart()` which starts typing again. The eager call is now superseded by the keepalive.

3. **SPEC-401 status/descriptions out of date** — §Status says "Phase 0 (behavioral tests only, no implementation changes)" but this PR includes Phase 1. §6.2 says Phase 1 preserves `sendDurableMessageBatch` but the diff removes it.

4. **Tests should exercise real lifecycle for seal/flush/clear** — The mocked lifecycle's no-op `seal`/`flush`/`clear` means the real seal→final flag, flush→drain, and clear→null-ID contracts aren't validated. At least one integration test with the real lifecycle (mock only REST client) would catch C2's double-delete.

5. **`buildFinalEdit` dead branch** — `payload.text || undefined` is always truthy due to the outer `if (!text) return` guard. Harmless but misleading.

6. **`freshSend` delete-before-send ordering** — Currently deletes draft before sending replacement. If the replacement send fails, user loses both draft and final. Previous code sent first, then deleted. Consider preserving send-first ordering.

---

## Positive Notes

- **Conservative scope** — keeping `sendOrEdit`/`editQueue`/lifecycle untouched and only swapping deliver is exactly the right blast radius after #399.
- **Real adapter via `vi.importActual`** — testing through the actual SDK adapter rather than mocking it catches schema drift. Good pattern.
- **Typing keepalive in `runDispatch`** — putting `onReplyStart` inside `runDispatch` tracks the actual generation window, not the dispatch envelope. Real UX improvement.
- **`logPreviewEditFailure` wired correctly** — preserves the `cove: final edit failed` warn signal with no silent failure mode for the edit-in-place attempt.
- **SPEC-401.md is excellent** — risk-mapped phased plan with failure mode analysis from #399 and #404. This is how large refactors should be documented.
