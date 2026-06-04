# Code Review Service — Reviewer Stats

_Last updated: 2026-06-04 20:26 (Asia/Shanghai)_

## Per-Reviewer Performance

| Reviewer | Model | Total Review Rounds | Reliability | Trend |
|----------|-------|---------------------|-------------|-------|
| 🌟 Stella | gpt-5.5 | 53 | 51/53 (96%) → | Stable — 1 timeout (#176 R1), 1 late (#190 R5). Otherwise 100% |
| 🌠 Nova | claude-opus-4.7 | 53 | 53/53 (100%) → | Rock solid. No failures ever |
| 💫 Vega | gemini-3.1-pro-preview | 53 | 49/53 (92%) ↑ | Improving — last 20 rounds: 19/20 (95%). Early failures dragging average |

## Dimension Strengths (per reviewer)

### 🌟 Stella (GPT-5.5)
| Dimension | Strength | Evidence |
|-----------|----------|----------|
| DB/Migration | ⭐⭐⭐ | SQLite ALTER TABLE (#168), migration ordering (#144), FK pragma-in-transaction (#178 R1 — reproduced locally), FK safety (#174) |
| Build Verification | ⭐⭐⭐ | Only reviewer who runs `pnpm -r build` — caught tsc failure (#165 R1), verified tests every round |
| Security (Auth) | ⭐⭐⭐ | Ghost presence (#167), presences membership (#168), stale guildIds (#179 R1 — rated ❌), user deletion stale sessions (#179 R3) |
| Async/Concurrency | ⭐⭐ | Async handler ordering race (#190 R5 — unique star find), queued side-effect race analysis (#190 R4) |
| Testing Gaps | ⭐⭐ | Consistently flags missing negative tests, fake test detection (#178 R2) |
| Architecture | ⭐ | WS guild scoping (#168 R5-R6) — valid but sometimes over-scopes beyond PR |

**Stella's superpower:** Runs actual builds + reproduces bugs locally. Catches things that pure code reading misses. Deepest lifecycle analysis.
**Stella's weakness:** Sometimes over-scopes (flags out-of-PR architectural concerns as blocking). Occasional timeout under heavy build.

### 🌠 Nova (Claude Opus 4.7)
| Dimension | Strength | Evidence |
|-----------|----------|----------|
| API Design | ⭐⭐⭐ | Breaking changes (#175 UUID), API compatibility, positional arg drift (#168), topic nullability (#174) |
| Security | ⭐⭐⭐ | IDOR (#168 R3), cross-guild leak (#143), SQL interpolation risk, typing indicator leak (#190 R1) |
| Architecture | ⭐⭐⭐ | Timer leak (#176 R2), event model verification (#176 R1), self-broadcast lifecycle (#179 R2), GUILD_CREATE/DELETE gap (#179 R2) |
| Async/Concurrency | ⭐⭐⭐ | Queued side-effect race trace (#190 R5), handler ordering analysis (#190 R6), dispatch.catch paths |
| Severity Calibration | ⭐⭐⭐ | Most accurately calibrates critical vs suggestion. Rarely over-flags |
| DB/Migration | ⭐⭐ | FK enforcement gaps, migration analysis. Not as deep as Stella on SQLite specifics |

**Nova's superpower:** Best calibration. Most suggestions per review, almost all actionable. Strongest on API compatibility, security, and async lifecycle analysis.
**Nova's weakness:** None significant. Occasionally verbose but content is consistently high quality.

### 💫 Vega (Gemini 3.1 Pro)
| Dimension | Strength | Evidence |
|-----------|----------|----------|
| Security (Code-level) | ⭐⭐ | Prototype pollution (#176 R1, unique find), IDOR framing (#168 R3, clearest) |
| Async/Concurrency | ⭐⭐⭐ | **Generation ID reuse via .delete()** (#190 R4 — star find of entire review history). AbortController identity design eliminated entire data structure |
| CSS/UI | ⭐⭐ | CSS duplication, hex guard, position edge case (#168 R5) |
| Product Impact | ⭐⭐ | Good user-facing consequence analysis (#176), O(N²) presence finding (#179 R2) |
| DB/Migration | ⭐⭐ | Per-guild position scoping (#174 R2, unique), FK pragma fix suggestion (#178 R1, cleanest) |
| Architecture | ⭐ | Less depth overall, but capable of architectural suggestions when engaged |

**Vega's superpower:** Fast (~1m avg). Capable of star-quality finds when the bug is deterministic/logical (gen ID reuse, prototype pollution). Cleanest fix suggestions.
**Vega's weakness:** Fewer unique finds overall. Tends to agree with consensus rather than finding novel issues. Less depth on complex lifecycle analysis.

## Unique Find Rate (last 10 PRs: #165 through #190)

| Reviewer | Unique Finds | Total Issues Found | Unique Rate | Trend |
|----------|-------------|-------------------|-------------|-------|
| 🌟 Stella | 12 | ~65 | ~18% | → Stable |
| 🌠 Nova | 18 | ~65 | ~28% | → Stable |
| 💫 Vega | 7 | ~65 | ~11% | ↑ Improving (was ~9%, gen ID reuse boosted) |

**Notable unique finds (last 10 PRs):**
- Stella: tsc build failure (#165), ghost presence (#167), WS disconnect lifecycle (#176 R3), presences bypass (#168 R4), FK pragma reproduced locally (#178 R1), stale guildIds security (#179 R1), **async handler ordering race** (#190 R5)
- Nova: UUID behavioral break (#168 R2), timer leak on teardown (#176 R2), SQL interpolation (#168 R5), typing indicator leak (#190 R1), self-broadcast on disconnect (#179 R2), GUILD_CREATE/DELETE gap (#179 R2), guild name drift (#178 R2), queued side-effect trace (#190 R5)
- Vega: Prototype pollution (#176 R1), per-guild position scoping (#174 R2), PRAGMA restoration (#168 R3), **generation ID reuse** (#190 R4 — star find), O(N²) IDENTIFY presence (#179 R2), UnhandledPromiseRejection early return (#190 R2)

## Consensus Participation

| Reviewer | Part of 2/3+ consensus | Solo dissent (correct) | Solo dissent (noise) |
|----------|----------------------|----------------------|---------------------|
| 🌟 Stella | 85% | 4 (WS scoping, presences, build-order, WS disconnect #176 R3) | 1 (WS scoping over-scope #168) |
| 🌠 Nova | 92% | 1 (ready when others flag — usually correct) | 0 |
| 💫 Vega | 82% | 2 (#125 R1 needs_changes, gen ID reuse #190 R4) | 0 |

## Severity Calibration

| Reviewer | Verdict matches final | Over-flags | Under-flags |
|----------|----------------------|------------|-------------|
| 🌟 Stella | 80% | 15% (WS scoping, build-order) | 5% |
| 🌠 Nova | 95% | 3% | 2% |
| 💫 Vega | 83% | 10% (#125 R1, #176 R2 ❌ Major, #190 R3 ❌ Major) | 7% (early misses) |

## False Positive Rate (Critical flagged → later proven non-issue)

| Reviewer | False Positives | Total Criticals | FP Rate |
|----------|----------------|-----------------|---------|
| 🌟 Stella | 1 (WS scoping as blocker for #168) | ~20 | 5% |
| 🌠 Nova | 0 | ~18 | 0% |
| 💫 Vega | 1 (#168 R2 oversized; #125 R1 over-flagged) | ~14 | 7% |

## Reliability History

| Reviewer | Early (PRs #96-#145) | Mid (#155-#167) | Recent (#168-#190) | Trend |
|----------|---------------------|-----------------|--------------------|----|
| 🌟 Stella | 12/12 (100%) | 8/8 (100%) | 31/33 (94%) | → (one timeout #176 R1, one late #190 R5) |
| 🌠 Nova | 12/12 (100%) | 8/8 (100%) | 33/33 (100%) | → |
| 💫 Vega | 8/12 (67%) | 6/8 (75%) | 29/30 (97%) | ↑ Significant improvement after prompt fixes |

## Review History

| PR | Repo | Date | Rounds | Final Verdict | Key Dimension |
|----|------|------|--------|---------------|---------------|
| #96 | cove | 2026-05-26 | R1-R3 | ✅ Ready | cors-preflight, route-ordering |
| #100 | cove | 2026-05-27 | R1 | ⚠️ Over-flagged | calibration — too conservative for context |
| #124 | cove | 2026-06-02 | R1-R6 | ✅ Ready | concurrent-edit, orphan-cleanup |
| #125 | cove | 2026-06-03 | R1-R2 | ✅ Ready | getComputedStyle, member-list-split |
| #143 | cove | 2026-06-03 | R1 | ✅ Ready | behavioral-change-detection |
| #144 | cove | 2026-06-03 | R1-R2 | ✅ Ready | migration-ordering, data-loss |
| #145 | cove | 2026-06-03 | R1-R2 | ✅ Ready | gateway-typing, breaking-auth |
| #155 | cove | 2026-06-03 | R1 | ✅ Ready | ui-polish |
| #156 | cove | 2026-06-03 | R1-R3 | ✅ Ready | xss-security, paragraph-rendering |
| #165 | cove | 2026-06-04 | R1-R2 | ✅ Ready | build-failure, hono-typing |
| #166 | cove | 2026-06-04 | R1 | ✅ Ready | migration-guard, validation |
| #167 | cove | 2026-06-04 | R1-R2 | ✅ Ready | ghost-presence, shape-mismatch |
| #168 | cove | 2026-06-04 | R1-R6 | ✅ Ready | idor, migration-safety, channel-id |
| #174 | cove | 2026-06-04 | R1-R2 | ✅ Ready | input-validation, fk-safety |
| #175 | cove | 2026-06-04 | R1-R2 | ✅ Ready | template-interpolation |
| #176 | cove | 2026-06-04 | R1-R3 | ✅ Ready | prototype-pollution, typing-coupling, silent-message-drop |
| #178 | cove | 2026-06-04 | R1-R3 | ✅ Ready | sqlite-pragma-transaction, fake-test, fk-regression |
| #179 | cove | 2026-06-04 | R1-R3 | ✅ Ready | stale-auth-state, guild-lifecycle-events |
| #190 | cove | 2026-06-04 | R1-R7 | ✅ Ready | abort-cancellation, gen-id-reuse, async-handler-ordering |

## Ground Truth Summary (17 merged PRs with ground truth)

- **Human blind spots found by us:** 0 — human has never caught something we missed
- **Our blind spots:** 0 — human has never flagged something all 3 reviewers missed
- **Human rubber-stamp rate:** 100% — human approved without findings in every case
- **Iterative review as quality gate:** In 13/17 PRs, our multi-round review was the actual quality gate (human approved final state without independent analysis)
- **Over-flagging instances:** 1 (#100 — verdict too conservative for personal project context)
- **Multi-round PRs:** 13/17 PRs went through 2+ rounds. Average rounds: 2.8. Max: 7 (#190)
- **Total review rounds:** 53 across 20 PRs (includes #96 R1 only-2-reviewer round)

## Actionable Notes

1. **✅ Vega unique find rate recovered to 11% (above 10% threshold).** The generation ID reuse find (#190 R4) is the most impactful unique find across all reviews — eliminated an entire data structure. No action needed on replacement. Monitor next 5 PRs.

2. **Stella over-scoping tendency persists but valuable:** WS disconnect (#176 R3), user deletion (#179 R3) — both are real concerns flagged as blocking when they're follow-ups. The tradeoff is worth it: Stella's strictness catches real bugs that others downgrade. Keep as-is.

3. **Nova zero false positives across 53 rounds.** Best-calibrated reviewer. Continue using Nova's verdict as tiebreaker when Stella and Vega disagree.

4. **Vega reliability trend strongly positive.** Early 67% → mid 75% → recent 97%. Prompt fixes (output constraints, re-review protocol) working. The remaining ~3% failure rate is within acceptable bounds.

5. **New dimension emerging: Async/Concurrency.** PRs #176 (emit iteration), #179 (O(N²) presence), #190 (generation ID reuse, handler ordering, queued race) — 3 consecutive PRs with async/concurrency as primary finding. All 3 reviewers can find these, but Stella (handler ordering) and Vega (gen ID reuse) had the star finds. Consider adding explicit "async ownership and cancellation" prompt dimension if pattern continues.

6. **Handler error isolation** mentioned by all 3 across #176 R2+R3, now addressed in code. Pattern did not recur in #178-#190. Resolved — no prompt action needed.

7. **SQLite migration correctness** appeared in #144, #168, #178 — 3 PRs. FK pragma, migration ordering, foreign_key_check. This is project-specific (Cove uses SQLite). No default prompt change, but if a `cove.prompt.md` is created, include SQLite-specific migration checks.

8. **PR #190 set new record:** 7 rounds, most review rounds in history. Each round produced genuine new findings. The system works — iterative review converges to quality even on complex async code. No process change needed.
