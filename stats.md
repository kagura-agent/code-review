# Code Review Service — Reviewer Stats

_Last updated: 2026-06-05 14:26 (Asia/Shanghai)_

## Per-Reviewer Performance

| Reviewer | Model | Total Review Rounds | Reliability | Trend |
|----------|-------|---------------------|-------------|-------|
| 🌟 Stella | gpt-5.5 | 61 | 59/61 (97%) → | Stable — 1 timeout (#176 R1), 1 late (#190 R5). Last 25 rounds: 25/25 (100%) |
| 🌠 Nova | claude-opus-4.7 | 61 | 61/61 (100%) → | Rock solid. No failures ever |
| 💫 Vega | gemini-3.1-pro-preview | 61 | 57/61 (93%) ↑ | Improving — last 25 rounds: 24/25 (96%). Early failures dragging average |

## Dimension Strengths (per reviewer)

### 🌟 Stella (GPT-5.5)
| Dimension | Strength | Evidence |
|-----------|----------|----------|
| DB/Migration | ⭐⭐⭐ | SQLite ALTER TABLE (#168), migration ordering (#144), FK pragma-in-transaction (#178 R1 — reproduced locally), FK safety (#174), migration seq overflow (#202 R1) |
| Build Verification | ⭐⭐⭐ | Only reviewer who runs `pnpm -r build` — caught tsc failure (#165 R1), verified tests every round |
| Security (Auth) | ⭐⭐⭐ | Ghost presence (#167), presences membership (#168), stale guildIds (#179 R1 — rated ❌), snowflake-as-auth-token (#202 R1), user deletion stale sessions (#179 R3) |
| Async/Concurrency | ⭐⭐ | Async handler ordering race (#190 R5 — unique star find), queued side-effect race analysis (#190 R4), auto-ack race on channel switch (#192 R1) |
| Testing Gaps | ⭐⭐⭐ | Ack endpoint test coverage (#192 R1), fake test detection (#178 R2), product-impact of .catch swallowing (#192 R1) |
| Architecture | ⭐ | WS guild scoping (#168 R5-R6) — valid but sometimes over-scopes beyond PR |
| Accessibility/A11y | ⭐⭐ | Focus ring WCAG violation (#191 R2), high-contrast mode note (#191 R3), send button aria-label (#191 R3) |
| Lifecycle Analysis | ⭐⭐⭐ | Auto-ack dedup across mounts (#192 R3-R4), reload dedup gap (#192 R4), same-ms monotonicity (#192 R4) |

**Stella's superpower:** Runs actual builds + reproduces bugs locally. Catches things that pure code reading misses. Deepest lifecycle analysis. Most persistent on escalation rules.
**Stella's weakness:** Sometimes over-scopes (flags out-of-PR architectural concerns as blocking). Strictest on escalation — same-ms monotonicity (#192 R4) flagged when practically harmless.

### 🌠 Nova (Claude Opus 4.7)
| Dimension | Strength | Evidence |
|-----------|----------|----------|
| API Design | ⭐⭐⭐ | Breaking changes (#175 UUID), API compatibility, positional arg drift (#168), topic nullability (#174) |
| Security | ⭐⭐⭐ | IDOR (#168 R3), cross-guild leak (#143), SQL interpolation risk, typing indicator leak (#190 R1), snowflake-as-auth-token (#202 R1) |
| Architecture | ⭐⭐⭐ | Timer leak (#176 R2), event model verification (#176 R1), self-broadcast lifecycle (#179 R2), GUILD_CREATE/DELETE gap (#179 R2), READY payload growth (#192 R1) |
| Async/Concurrency | ⭐⭐⭐ | Queued side-effect race trace (#190 R5), handler ordering analysis (#190 R6), dispatch.catch paths, ack cursor monotonicity race (#192 R2) |
| Severity Calibration | ⭐⭐⭐ | Most accurately calibrates critical vs suggestion. Rarely over-flags. Best tiebreaker when others disagree |
| DB/Migration | ⭐⭐ | FK enforcement gaps, migration analysis, CAST bypass (#202 R1). Not as deep as Stella on SQLite specifics |
| Internationalization | ⭐⭐ | IME composition guard (#191 R1), CJK user impact analysis |
| Accessibility/A11y | ⭐⭐⭐ | WCAG 2.4.7 citation (#191 R2), aria-label (#191 R1), useLayoutEffect correctness (#191 R2), matchMedia mobile detection (#191 R2) |
| Code Hygiene | ⭐⭐ | Dead code detection (getAllForUser #192 R2, ReadStateRow alias #192 R2), test mock accuracy (#192 R4) |

**Nova's superpower:** Best calibration. Most suggestions per review, almost all actionable. Strongest on API compatibility, security, accessibility, and async lifecycle analysis. Zero false positives across 61 rounds.
**Nova's weakness:** None significant. Occasionally verbose but content is consistently high quality.

### 💫 Vega (Gemini 3.1 Pro)
| Dimension | Strength | Evidence |
|-----------|----------|----------|
| Security (Code-level) | ⭐⭐⭐ | Prototype pollution (#176 R1, unique find), IDOR framing (#168 R3, clearest), snowflake-as-auth-token (#202 R1) |
| Async/Concurrency | ⭐⭐⭐ | **Generation ID reuse via .delete()** (#190 R4 — star find of entire review history). AbortController identity design eliminated entire data structure |
| CSS/UI | ⭐⭐ | CSS duplication, hex guard, position edge case (#168 R5) |
| Product Impact | ⭐⭐⭐ | Good user-facing consequence analysis (#176), O(N²) presence finding (#179 R2), **own-message-causes-unread** (#192 R2 — star find, only reviewer to catch) |
| DB/Migration | ⭐⭐ | Per-guild position scoping (#174 R2, unique), FK pragma fix suggestion (#178 R1, cleanest), migration seq overflow (#202 R1) |
| Edge Case Detection | ⭐⭐⭐ | Own-message unread (#192 R2), multi-device sync gap (#192 R2-R3), deleted-message false unread (#192 R3-R4, persistent tracking) |
| Mobile/UX | ⭐⭐ | Mobile Enter behavior (#191 R1), resize jitter (#191 R1 — unique suggestion) |

**Vega's superpower:** Fast (~1m avg). Capable of star-quality finds when the bug is deterministic/logical (gen ID reuse #190, own-message-unread #192). Cleanest fix suggestions. Excellent edge-case tenacity (deleted-message tracked across 3 rounds).
**Vega's weakness:** Fewer unique finds overall but improving. Strictest severity escalation (#191 R2 — ❌ Major for all 3 issues, #192 R3 — ❌ Major). Less depth on complex lifecycle analysis.

## Unique Find Rate (last 10 PRs: #174 through #202)

| Reviewer | Unique Finds | Total Issues Found | Unique Rate | Trend |
|----------|-------------|-------------------|-------------|-------|
| 🌟 Stella | 12 | ~68 | ~18% | → Stable |
| 🌠 Nova | 18 | ~68 | ~26% | → Stable |
| 💫 Vega | 9 | ~68 | ~13% | ↑ Improving (was 11%) |

**Notable unique finds (last 10 PRs):**
- Stella: FK-off try/finally (#174), build-order dependency (#175), WS disconnect lifecycle (#176 R3), FK pragma reproduced locally (#178 R1), **async handler ordering race** (#190 R5), high-contrast mode (#191 R3), auto-ack dedup mount reset (#192 R3), same-ms monotonicity (#192 R4), clock rollback in generator (#202)
- Nova: topic nullability breaking change (#174), template string bug (#175), timer leak on teardown (#176 R2), guild name drift (#178 R2), typing indicator leak (#190 R1), queued side-effect trace (#190 R5), **IME composition guard** (#191 R1), WCAG 2.4.7 (#191 R2), READY payload growth (#192 R1), ack write amplification (#192 R2), test mock accuracy (#192 R4), CAST index bypass (#202), channel migration ordering (#202)
- Vega: Prototype pollution (#176 R1), **generation ID reuse** (#190 R4 — star find), O(N²) IDENTIFY presence (#179 R2), resize jitter (#191 R1), **own-message-causes-unread** (#192 R2 — star find), multi-device sync gap (#192 R2), deleted-message edge case (#192 R3-R4), API input validation schemas (#202)

## Consensus Participation

| Reviewer | Part of 2/3+ consensus | Solo dissent (correct) | Solo dissent (noise) |
|----------|----------------------|----------------------|---------------------|
| 🌟 Stella | 85% | 5 (WS scoping, presences, build-order, WS disconnect #176 R3, auto-ack dedup #192 R4) | 1 (WS scoping over-scope #168) |
| 🌠 Nova | 92% | 1 (ready when others flag — usually correct) | 0 |
| 💫 Vega | 84% | 3 (#125 R1 needs_changes, gen ID reuse #190 R4, own-message-unread #192 R2) | 0 |

## Severity Calibration

| Reviewer | Verdict matches final | Over-flags | Under-flags |
|----------|----------------------|------------|-------------|
| 🌟 Stella | 79% | 16% (WS scoping, build-order, same-ms monotonicity) | 5% |
| 🌠 Nova | 95% | 3% | 2% |
| 💫 Vega | 81% | 13% (#125 R1, #176 R2, #190 R3, #191 R2 — all ❌ Major over-escalation) | 6% |

## False Positive Rate (Critical flagged → later proven non-issue)

| Reviewer | False Positives | Total Criticals | FP Rate |
|----------|----------------|-----------------|---------|
| 🌟 Stella | 1 (WS scoping as blocker for #168) | ~23 | 4% |
| 🌠 Nova | 0 | ~21 | 0% |
| 💫 Vega | 1 (#168 R2 oversized; #125 R1 over-flagged) | ~17 | 6% |

## Reliability History

| Reviewer | Early (PRs #96-#145) | Mid (#155-#167) | Recent (#168-#202) | Trend |
|----------|---------------------|-----------------|--------------------|----|
| 🌟 Stella | 12/12 (100%) | 8/8 (100%) | 39/41 (95%) | → (one timeout #176 R1, one late #190 R5) |
| 🌠 Nova | 12/12 (100%) | 8/8 (100%) | 41/41 (100%) | → |
| 💫 Vega | 8/12 (67%) | 6/8 (75%) | 37/38 (97%) | ↑ Significant improvement after prompt fixes |

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
| #191 | cove | 2026-06-04 | R1-R3 | ✅ Ready | ime-composition, focus-ring-a11y, mobile-multiline |
| #192 | cove | 2026-06-05 | R1-R4 | ✅ Ready | read-state-reload, own-message-unread, dispatch-monotonicity |
| #202 | cove | 2026-06-05 | R1 (open) | ❌ Major Issues | snowflake-auth-token, migration-overflow, index-bypass |

## Ground Truth Summary (22 merged PRs with ground truth)

- **Human blind spots found by us:** 0 — human has never caught something we missed
- **Our blind spots:** 0 — human has never flagged something all 3 reviewers missed
- **Human rubber-stamp rate:** 95% — human approved without findings in 21/22 cases. Exception: #174 where human asked design-level questions while our review caught code-level safety. Complementary perspectives.
- **Iterative review as quality gate:** In 18/22 PRs, our multi-round review was the actual quality gate (human approved final state without independent analysis)
- **Over-flagging instances:** 1 (#100 — verdict too conservative for personal project context)
- **Multi-round PRs:** 18/22 PRs went through 2+ rounds. Average rounds: 2.8. Max: 7 (#190)
- **Total review rounds:** 61 across 23 PRs (includes open #202)

## Actionable Notes

1. **✅ Vega unique find rate improved to 13% (comfortably above 10% threshold).** Two star finds in last 5 PRs: gen ID reuse (#190 R4) and own-message-causes-unread (#192 R2). Vega is proving most valuable for product-impact edge cases.

2. **Stella lifecycle analysis confirmed as top dimension:** PR #192 R3-R4 showed deepest analysis of auto-ack dedup across mounts, reload gaps, and same-ms monotonicity. No other reviewer tracks these persistent lifecycle edge cases as tenaciously.

3. **Nova zero false positives across 61 rounds.** Best-calibrated reviewer. Continue using Nova's verdict as tiebreaker when Stella and Vega disagree.

4. **Vega reliability trend strongly positive.** Early 67% → mid 75% → recent 97%. Last 25 rounds: 24/25 (96%). Prompt fixes working. Remaining ~3% is acceptable.

5. **Vega severity over-escalation pattern persists but not actionable yet.** 4 instances of ❌ Major when consolidated verdict was ⚠️ or ✅ (#125, #176, #190, #191). Monitor — if it causes merge delays, consider prompt guidance on severity thresholds.

6. **PR #192 validated multi-model review value:** Vega R2 found own-message-unread bug that both Stella and Nova missed. This alone justified the 3-reviewer architecture.

7. **Accessibility/A11y dimension:** Only seen in #191. Not adding to default prompt yet — need 2+ PRs to establish pattern.

8. **NEW: PR #202 security finding (snowflake-as-auth-token)** is the most severe finding since XSS in #156. All 3 reviewers caught it unanimously — security detection prompt is working well across all models.

9. **SQLite migration correctness** appeared in #144, #168, #178, #202 — 4 PRs now. Still project-specific (cove uses SQLite). No default prompt change needed.

10. **Stella's clock rollback find (#202)** is a unique depth contribution — only she analyzed the generator's temporal safety properties. Confirms her strength in deterministic-system analysis.
