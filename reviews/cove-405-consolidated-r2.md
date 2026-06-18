# Consolidated Round 2 Review — cove PR #405

**PR:** kagura-agent/cove#405
**Round:** 2
**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 2.5 Pro)
**Date:** 2026-06-18

---

## Verdict: ⚠️ Needs Changes (1 remaining blocker)

Good progress — 2 of 3 Round 1 criticals resolved. The double-delete is fixed (`draftMessageId = undefined` after delete). The post-seal `isCurrent()` guard is partially restored in `editFinal`. But the chunking regression is still present and was locked in by a rewritten test.

---

## Round 1 Issue Status

| # | Finding | R1 Severity | R2 Status |
|---|---------|-------------|-----------|
| 1 | Lost chunking — `freshSend` uses direct `restClient.sendMessage` | Critical | **Not fixed — escalated to Blocker** |
| 2 | Double-delete on fallback | Critical | ✅ Resolved |
| 3 | Post-seal `isCurrent()` guard | Critical | ✅ Mostly resolved (editFinal now checks) |
| 4 | Dead import / stale doc | Suggestion | ✅ Resolved |
| 5 | Delete-before-send ordering | Suggestion | Not addressed |
| 6 | Tests don't exercise real lifecycle | Suggestion | Partial improvement |

---

## Blocker (1)

### Lost chunking is now frozen as "the contract" (all 3 reviewers, escalated)

`freshSend()` still calls `restClient.sendMessage(channelId, text)` directly — no chunking. Any final text > `COVE_TEXT_CHUNK_LIMIT` (4000 chars) will fail or truncate. The B3 test was **rewritten** from asserting `sendDurableMessageBatch` to asserting `restClient.sendMessage`, codifying the regression.

SPEC-401 §6.2 explicitly promises the `sendDurableMessageBatch` call path is preserved — the code no longer matches the spec.

This affects: fresh responses, fallback after edit failure, recovery from stopped previews — exactly the paths where reliability matters most.

**Required fix:** Either restore `sendDurableMessageBatch` for `freshSend` (with the #404 error-shape fix), or add explicit chunking at `COVE_TEXT_CHUNK_LIMIT`. Revert B3 to assert chunked sends.

---

## Suggestions

1. **Delete-before-send ordering** (all 3, R1 carryover) — `freshSend` deletes draft before sending replacement. If send fails, user loses both. Reorder to send-first-then-delete.

2. **Pin double-delete fix with call count assertion** (Nova) — H4b/H6c assert `deleteMessage` was called with the right args but not `toHaveBeenCalledTimes(1)`. Future changes that reintroduce double-delete won't fail any test.

3. **`editFinal` silent stale-skip leaves SDK state inconsistent** (Nova) — When `!isCurrent()`, `editFinal` resolves without throwing → SDK interprets as success → claims finalized preview that was never written. Latent today (cove doesn't read `liveState`), but worth cleaning up.

4. **`canFinalize` snapshot timing** (Nova) — Captured before `flush()`/`seal()`. If flush triggers a streaming write that errors and flips `draftState.stopped`, `canFinalize` is stale → pays one extra failing API call. Correctness intact, minor efficiency issue.

5. **Duplicate `isCurrent()` check** (Nova) — Two checks with only sync code between them on lines ~131-135. Likely leftover from intermediate refactor.

6. **SPEC-401 status** (Stella) — Still says "Phase 0 (behavioral tests only)" but PR includes Phase 1 adapter wiring.

---

## Positive Notes

- Double-delete fix is clean and surgical (`draftMessageId = undefined`)
- `editFinal` now checks `isCurrent()` — the main staleness concern is addressed
- Adapter shape cleanly maps to lifecycle surface
- `typingCallbacks.onReplyStart` in `runDispatch` is a real UX improvement
- Dropping manual `draftState.final = true` matches SPEC §6.3
- H1-H7 behavioral tests provide strong regression scaffold
