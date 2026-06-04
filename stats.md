# Code Review Service — Reviewer Stats

_Last updated: 2026-06-04 14:34 (Asia/Shanghai)_

## Per-Reviewer Performance

| Reviewer | Model | Total Review Rounds | Reliability | Trend |
|----------|-------|---------------------|-------------|-------|
| 🌟 Stella | gpt-5.5 | 38 | 37/38 (97%) → | Stable — 1 timeout (#176 R1), otherwise 100% |
| 🌠 Nova | claude-opus-4.7 | 38 | 38/38 (100%) → | Rock solid. No failures ever |
| 💫 Vega | gemini-3.1-pro-preview | 38 | 34/38 (89%) ↑ | Improving — last 15 rounds: 14/15 (93%). Early failures (#96, #145 R1, #156 R1) dragging average |

## Dimension Strengths (per reviewer)

### 🌟 Stella (GPT-5.5)
| Dimension | Strength | Evidence |
|-----------|----------|----------|
| DB/Migration | ⭐⭐⭐ | SQLite ALTER TABLE edge cases (#168 R1-R2), migration ordering (#144), FK safety (#174) |
| Build Verification | ⭐⭐⭐ | Only reviewer who runs `pnpm -r build` — caught tsc failure (#165 R1), verified tests every round |
| Security (Auth) | ⭐⭐ | Ghost presence (#167), presences membership (#168 R4-R5), WS lifecycle (#176 R3) |
| Testing Gaps | ⭐⭐ | Consistently flags missing negative tests, test coverage gaps |
| Architecture | ⭐ | WS guild scoping (#168 R5-R6) — valid but sometimes over-scopes beyond PR |
| API Design | ⭐ | Less depth than Nova on API compatibility |

**Stella's superpower:** Runs actual builds. Catches things that pure code reading misses.
**Stella's weakness:** Sometimes over-scopes (flags out-of-PR architectural concerns as blocking).

### 🌠 Nova (Claude Opus 4.7)
| Dimension | Strength | Evidence |
|-----------|----------|----------|
| API Design | ⭐⭐⭐ | Breaking changes (#175 UUID), API compatibility, positional arg drift (#168), topic nullability (#174) |
| Security | ⭐⭐⭐ | IDOR (#168 R3), cross-guild leak (#143), SQL interpolation risk |
| Architecture | ⭐⭐⭐ | Timer leak (#176 R2), event model verification (#176 R1), behavioral change detection (#143) |
| Severity Calibration | ⭐⭐⭐ | Most accurately calibrates critical vs suggestion. Rarely over-flags |
| DB/Migration | ⭐⭐ | FK enforcement gaps, migration analysis. Not as deep as Stella on SQLite specifics |
| Testing | ⭐⭐ | Good at identifying what to test, less focused on running tests |

**Nova's superpower:** Best calibration. Most suggestions per review, almost all actionable. Strongest on API compatibility and security.
**Nova's weakness:** None significant. Occasionally verbose but content is consistently high quality.

### 💫 Vega (Gemini 3.1 Pro)
| Dimension | Strength | Evidence |
|-----------|----------|----------|
| Security (Code-level) | ⭐⭐ | Prototype pollution (#176 R1, unique find), IDOR framing (#168 R3, clearest) |
| CSS/UI | ⭐⭐ | CSS duplication, hex guard, position edge case (#168 R5) |
| Product Impact | ⭐⭐ | Good user-facing consequence analysis (#176) |
| DB/Migration | ⭐ | Per-guild position scoping (#174 R2, unique find) |
| Architecture | ⭐ | Less depth, tends to agree with consensus rather than finding novel issues |
| Testing | ⭐ | Identifies test gaps but less systematically than others |

**Vega's superpower:** Fast (~1m avg). Unique code-level security finds (prototype pollution). Good product impact analysis.
**Vega's weakness:** Least depth overall. Fewer unique finds. Historically unreliable (improving).

## Unique Find Rate (last 10 PRs: #155 through #176)

| Reviewer | Unique Finds | Total Issues Found | Unique Rate | Trend |
|----------|-------------|-------------------|-------------|-------|
| 🌟 Stella | 8 | ~45 | ~18% | → Stable |
| 🌠 Nova | 12 | ~45 | ~27% | → Stable |
| 💫 Vega | 4 | ~45 | ~9% | ↑ Improving (was ~5%) |

**Notable unique finds (last 10 PRs):**
- Stella: tsc build failure (#165), ghost presence (#167), WS disconnect lifecycle (#176 R3), presences bypass (#168 R4)
- Nova: UUID behavioral break (#168 R2), timer leak on teardown (#176 R2), getDefaultId fallback (#168 R3), SQL interpolation (#168 R5)
- Vega: Prototype pollution (#176 R1), per-guild position scoping (#174 R2), PRAGMA restoration (#168 R3), GATEWAY_DISCONNECT suggestion (#176 R3)

## Consensus Participation

| Reviewer | Part of 2/3+ consensus | Solo dissent (correct) | Solo dissent (noise) |
|----------|----------------------|----------------------|---------------------|
| 🌟 Stella | 85% | 3 (WS scoping, presences, build-order) | 1 (WS scoping over-scope) |
| 🌠 Nova | 90% | 1 (ready when others flag — usually correct) | 0 |
| 💫 Vega | 80% | 1 (#125 R1 needs_changes — validated in R2) | 0 |

## Severity Calibration

| Reviewer | Verdict matches final | Over-flags | Under-flags |
|----------|----------------------|------------|-------------|
| 🌟 Stella | 80% | 15% (WS scoping, build-order) | 5% |
| 🌠 Nova | 95% | 3% | 2% |
| 💫 Vega | 82% | 10% (#125 R1, #176 R2 ❌ Major) | 8% (early misses) |

## False Positive Rate (Critical flagged → later proven non-issue)

| Reviewer | False Positives | Total Criticals | FP Rate |
|----------|----------------|-----------------|---------|
| 🌟 Stella | 1 (WS scoping as blocker for #168) | ~15 | 7% |
| 🌠 Nova | 0 | ~12 | 0% |
| 💫 Vega | 1 (#168 R2 oversized = unusable; #125 R1 over-flagged) | ~10 | 10% |

## Reliability History

| Reviewer | Early (PRs #96-#145) | Mid (#155-#167) | Recent (#168-#176) | Trend |
|----------|---------------------|-----------------|--------------------|----|
| 🌟 Stella | 12/12 (100%) | 8/8 (100%) | 17/18 (94%) | → (one timeout, explained by build overhead) |
| 🌠 Nova | 12/12 (100%) | 8/8 (100%) | 18/18 (100%) | → |
| 💫 Vega | 8/12 (67%) | 6/8 (75%) | 14/15 (93%) | ↑ Significant improvement after prompt fixes |

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
| #176 | cove | 2026-06-04 | R1-R3 | ⚠️ Open | event-model, typing-coupling, tests |

## Ground Truth Summary (13 merged PRs with ground truth)

- **Human blind spots found by us:** 0 — human has never caught something we missed
- **Our blind spots:** 0 — human has never flagged something all 3 reviewers missed
- **Human rubber-stamp rate:** 100% — human approved without findings in every case
- **Iterative review as quality gate:** In 8/13 PRs, our multi-round review was the actual quality gate (human approved final state without independent analysis)
- **Over-flagging instances:** 1 (#100 — verdict too conservative for personal project context)

## Actionable Notes

1. **⚠️ Vega unique find rate at 9% (borderline 10% threshold).** Last 5 PRs show improvement (prototype pollution, position scoping). Monitor next 5 PRs — if rate drops below 10% across 10+ reviews, consider prompt tuning or model swap.

2. **Stella over-scoping:** Tends to flag architectural concerns outside PR scope as blocking. Consider adding prompt guidance: "if the concern pre-dates this PR and the PR doesn't make it worse, classify as suggestion not critical."

3. **Nova zero false positives.** Best-calibrated reviewer. Consider Nova's verdict as tiebreaker when Stella and Vega disagree.

4. **Vega reliability trend is positive.** Early failures (67%) → recent 93%. Prompt fixes (output constraints, re-review protocol) working. No action needed currently.

5. **Handler error isolation** mentioned by all 3 across #176 R2+R3. If it appears in next PR, escalate to default prompt as a required check dimension.
