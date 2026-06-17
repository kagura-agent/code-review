# Run Record: cove #399

**Date:** 2026-06-17
**PR:** refactor(plugin): adopt SDK outbound adapter framework (#398)
**Round:** 1
**Verdict:** ⚠️ Needs Changes (2/3)

## Reviewer Verdicts

| Reviewer | Model | Verdict | Critical Findings | Unique Finds |
|----------|-------|---------|-------------------|--------------|
| 🌟 Stella | GPT-5.5 | ⚠️ Needs Changes | 3 | Peer dependency range too low |
| 🌠 Nova | Claude Opus 4.7 | ⚠️ Needs Changes | 5 | C5 error recovery loss, detailed test analysis |
| 💫 Vega | Gemini 2.5 Pro | ✅ Ready | 0 | None |

## Consensus Findings (Stella + Nova)

1. **Dead adapter code** — `coveMessageAdapter` created but never used/attached
2. **Draft streaming silently removed** — user-visible regression, contradicts "no behavior change" claim
3. **Tool progress no-op** — `onProgressUpdate` is empty comment, `getCombinedText()` never read
4. **Tests don't test changed behavior** — only assert callback existence, never invoke deliver/partial

## Key Observations

- This is a "claim vs reality" PR: description says SDK adapter is wired, code shows manual loop remains
- Vega gave a completely superficial review — missed all critical issues, praised test quality without reading test assertions
- Nova provided the deepest analysis with concrete code references and behavior table
- Stella caught the peer dependency issue that Nova missed

## Verification

- Stella: 100% file references verified
- Nova: 85% (dispatch-behavior.test.ts unverified — new file in PR, valid)
- Vega: 50% — shallow engagement with codebase

## Process Notes

- FlowForge workflow ran smoothly
- plan-review.sh correctly identified as small PR (5 files), no triage needed
- All reviewers spawned in parallel, completed within ~11 minutes

---

# Round 2

**Date:** 2026-06-17
**Verdict:** ⚠️ Needs Changes (3/3)

## R1 Resolution

| Issue | Status |
|-------|--------|
| C1 Dead adapter | ✅ Resolved |
| C2 Draft streaming | ⚠️ Partially — new serialization bug |
| C3 Tool progress | ✅ Resolved |
| C4 Tests | ❌ Not addressed — escalated |
| C5 Error recovery | ✅ Resolved |

## New Critical Findings (R2)

1. **N1: editQueue serialization broken** — `const editQueue = Promise.resolve()` never reassigned, concurrent partials run in parallel instead of serial. Causes duplicate drafts, orphaned messages. (Stella + Nova consensus)
2. **N2: finalizeDraft races with sendOrEdit** — reads draftState without awaiting editQueue, late partials can overwrite final answer. (Stella + Nova consensus)
3. **C4 escalated** — tests still only assert callbacks exist, never invoke deliver/partial. All 3 reviewers agree.

## Reviewer Performance

| Reviewer | Verdict | Key Contribution |
|----------|---------|------------------|
| 🌟 Stella | ❌ Major Issues | Found editQueue race + finalizeDraft drops final on draft failure |
| 🌠 Nova | ⚠️ Needs Changes | Found editQueue race + finalizeDraft race + coveOutbound half-dead + concrete fix code |
| 💫 Vega | ⚠️ Needs Changes | Found C4 testing gap but missed editQueue race entirely |

## Vega Assessment (R2)

Improvement over R1: changed verdict from ✅ Ready to ⚠️ Needs Changes. Found testing gap (C4). But still missed the most critical finding (editQueue race) that both Stella and Nova caught. Vega's review was surface-level on the new draft code — didn't trace the `const` vs `let` issue or the race condition.

## Observations

- The R2 fix introduced a regression (N1/N2) that the "behavioral tests" can't detect — proving C4's point
- Nova provided the most actionable fix with exact code and the `finalizeDraft` interlock detail
- Pattern: "refactor that claims to restore behavior" → subtle ordering bugs → only caught by reviewers who trace concurrent execution paths

---

# Round 3

**Date:** 2026-06-17
**Verdict:** ⚠️ Needs Changes (2/3)

## R1+R2 Resolution

| Issue | Status |
|-------|--------|
| C1 Dead adapter | ✅ Resolved |
| C2 Draft streaming | ✅ Resolved — createFinalizableDraftLifecycle restored |
| C3 Tool progress | ✅ Resolved |
| C4 Tests | 🔴 **Blocker — 3rd round unaddressed** |
| C5 Error recovery | ✅ Resolved |
| N1 editQueue race | ✅ Resolved |
| N2 finalizeDraft race | ✅ Mostly resolved |
| M2 onCompactionStart | ✅ Resolved |

## New/Escalated Findings (R3)

1. **C4 → Blocker** — 3rd round, zero new test assertions on changed paths. Stella + Nova consensus.
2. **N6 (High)** — Final editMessage not enqueued onto editQueue, races with late partials. Nova unique.
3. **N2-depth (Medium)** — sendOrEdit guard `stopped && !final` should be `final || stopped`. Nova unique.
4. **N4 escalated (High)** — coveOutbound chunkerMode/deliveryCapabilities still not in base.outbound. Stella + Nova.
5. **N5 held (High)** — Chunk limit duplicated in 2 files. Stella + Nova.
6. **Preview clamp suffix** — 41 chars not 30, can exceed 4000. Stella + Nova (L4).

## Reviewer Performance (R3)

| Reviewer | Verdict | Key Contribution |
|----------|---------|------------------|
| 🌟 Stella | ⚠️ Needs Changes | Preview suffix math, N4/N5 escalation, C4 blocker |
| 🌠 Nova | ⚠️ Needs Changes | N6 final edit race, N2-depth guard fix, concrete 5-test minimum, anti-confirmation note |
| 💫 Vega | ✅ LGTM | Claimed all issues resolved incl C4 — wrong. Missed N6, N4, N5, suffix bug. |

## Vega Assessment (R3)

Third consecutive round of Vega under-detecting. R1: ✅ Ready with 0 findings (5 critical existed). R2: ⚠️ Needs Changes but missed editQueue race. R3: ✅ LGTM, claimed C4 resolved (it isn't — tests unchanged), missed N6/N4/N5/suffix. Vega's review is actively misleading — it tells the author everything is fine when it isn't.

**Vega evaluation verdict: REPLACE.** 6 PRs with gemini-2.5-pro, calibration has not improved. Unique find rate <5%, false-ready rate >60% in recent rounds.
