# Run Record — cove #405

**Date:** 2026-06-18
**Repo:** kagura-agent/cove
**PR:** #405
**Title:** refactor(plugin): adopt SDK delivery adapter + typing keepalive (#401)
**Verdict:** ⚠️ Needs Changes

## Reviewer Verdicts
- 🌟 Stella (GPT-5.5): ⚠️ Needs Changes — 3 critical, 4 suggestions
- 🌠 Nova (Claude Opus 4.7): ⚠️ Needs Changes — 3 critical, 8 suggestions
- 💫 Vega (Gemini 2.5 Pro): ⚠️ Needs Changes — 1 critical, 1 suggestion

## Consensus Findings (2+ reviewers)
1. **Lost chunking** (all 3) — `sendDurableMessageBatch` removal drops auto-chunking for messages > COVE_TEXT_CHUNK_LIMIT
2. **Double-delete on fallback** (Stella + Nova + Vega) — `freshSend` deletes draft, then SDK `adapter.clear()` deletes again
3. **Test coverage gaps** (Stella + Nova) — mocked lifecycle means real seal/flush/clear contracts untested

## Unique Findings
- Stella: Post-seal `isCurrent()` guard lost inside adapter — stale dispatch can fire `editFinal`
- Nova: `freshSend` delete-before-send ordering regression — previous code sent first
- Nova: `buildFinalEdit` dead branch, redundant typing kick, SPEC status stale

## Round 2 (2026-06-18)

### R1 Issue Resolution
- ✅ Double-delete fixed (`draftMessageId = undefined` after delete)
- ✅ Post-seal `isCurrent()` guard restored in `editFinal`
- ✅ Dead import/stale doc cleaned up
- ❌ Lost chunking — not fixed, B3 test rewritten to lock in regression

### R2 Verdict: ⚠️ Needs Changes (1 blocker)
- Blocker: Lost chunking (all 3 reviewers, escalated from R1)
- Suggestions: delete-before-send ordering, pin call count, editFinal stale-skip, SPEC status

### Reviewer Notes
- Stella: Escalated chunking to ❌ Major Issues
- Nova: Most detailed trace through SDK adapter; identified canFinalize snapshot timing, duplicate isCurrent check
- Vega: Crashed on first R1 spawn (0 tokens, 2s runtime); retry worked. R2 attempted to raise new Critical C3 (freshSend always deletes draft) but this is guarded by `if (draftMessageId)` — false positive

## Ground Truth
- **Human reviewer:** daniyuu
- **Human verdict:** approved (2x APPROVED reviews)
- **Human findings:** none — approved after author justified chunking deferral to #406
- **Our accuracy:** correct — R1 caught 3 real criticals, R2 correctly held on chunking blocker
- **Author response:** accepted 2/3 fixes (double-delete, post-seal guard), justified deferring chunking (SDK `sendDurableMessageBatch` callback not firing in production). Tracked as #406 item 1.
- **Outcome:** merged 2026-06-18T09:26Z with known limitation. Review process worked as intended — blocker identified, trade-off made explicitly, follow-up tracked.
- **Vega assessment:** R1 crash + retry (reliability concern), R2 false positive C3 (guarded code). Mixed performance.
