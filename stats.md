# Code Review Service — Reviewer Stats

_Last updated: 2026-06-06 20:26 (Asia/Shanghai)_

## Per-Reviewer Performance

| Reviewer | Model | Total Review Rounds | Reliability | Trend |
|----------|-------|---------------------|-------------|-------|
| 🌟 Stella | gpt-5.5 | 73 | 71/73 (97%) → | Stable — 1 timeout (#176 R1), 1 late (#190 R5). Last 29 rounds: 29/29 (100%) |
| 🌠 Nova | claude-opus-4.7 | 73 | 73/73 (100%) → | Rock solid. No failures ever |
| 💫 Vega | gemini-3.1-pro-preview | 73 | 69/73 (95%) ↑ | Improving — last 29 rounds: 29/29 (100%). Early failures dragging average |

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
| Auth/Cookie Security | ⭐⭐⭐ | pendingToken leaked to JS (#248 R1), NODE_ENV cookie Secure flag (#248 R2-R3), logout doesn't close WS (#248 R3), local dev NODE_ENV (#248 R3) |

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
| Auth Route Analysis | ⭐⭐⭐ | PUBLIC_PATHS signup break (#248 R1 — unique find), resolveUser duplication escalation (#248 R2-R3), cookie attribute assertions (#248 R3), CORS credentials concern (#248 R3) |

**Nova's superpower:** Best calibration. Most suggestions per review, almost all actionable. Strongest on API compatibility, security, accessibility, and async lifecycle analysis. Zero false positives across 73 rounds.
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
| Input Sanitization/DoS | ⭐⭐⭐ | parseCookies URIError DoS (#248 R1 — unique find), localStorage XSS remnant (#248 R2 — unique find) |

**Vega's superpower:** Fast (~1m avg). Capable of star-quality finds when the bug is deterministic/logical (gen ID reuse #190, own-message-unread #192). Cleanest fix suggestions. Excellent edge-case tenacity (deleted-message tracked across 3 rounds). Strong on input sanitization/DoS vectors.
**Vega's weakness:** Fewer unique finds overall but improving. Strictest severity escalation (#191 R2 — ❌ Major for all 3 issues, #192 R3 — ❌ Major). Less depth on complex lifecycle analysis.

## Unique Find Rate (last 10 PRs: #179 through #248)

| Reviewer | Unique Finds | Total Issues Found | Unique Rate | Trend |
|----------|-------------|-------------------|-------------|-------|
| 🌟 Stella | 14 | ~90 | ~16% | → Stable |
| 🌠 Nova | 15 | ~90 | ~17% | → Stable |
| 💫 Vega | 13 | ~90 | ~14% | ↑ Improving |

**Notable unique finds (last 10 PRs):**
- Stella: **async handler ordering race** (#190 R5), auto-ack dedup mount reset (#192 R3), same-ms monotonicity (#192 R4), clock rollback in generator (#202), global idMap collision (#202 R2), **client clear button 404** (#222 R1), MESSAGE_DELETE_BULK allowlist gap (#222 R2), mobile sidebar scroll overlap (#240 R2), logout doesn't close WS (#248 R3), local dev NODE_ENV gap (#248 R3)
- Nova: queued side-effect trace (#190 R5), **IME composition guard** (#191 R1), WCAG 2.4.7 (#191 R2), READY payload growth (#192 R1), CAST index bypass (#202), channel migration ordering (#202), V3→V4 silent orphan drops (#202 R2), email UNIQUE constraint (#202 R2), CHANNEL_DELETE missing guild_id (#222 R1), mobile sidebar safe-area padding (#240 R2), **PUBLIC_PATHS signup break** (#248 R1), cookie attribute test assertions (#248 R3)
- Vega: **generation ID reuse** (#190 R4 — star find), **own-message-causes-unread** (#192 R2 — star find), deleted-message edge case (#192 R3-R4), API input validation schemas (#202), **@me alias breaks ownership** (#222 R2), safe-area background gap (#240 R1), getComputedStyle render race (#240 R2), **parseCookies URIError DoS** (#248 R1), **localStorage XSS remnant** (#248 R2)

## Consensus Participation

| Reviewer | Part of 2/3+ consensus | Solo dissent (correct) | Solo dissent (noise) |
|----------|----------------------|----------------------|---------------------|
| 🌟 Stella | 85% | 5 (WS scoping, presences, build-order, WS disconnect #176 R3, auto-ack dedup #192 R4) | 1 (WS scoping over-scope #168) |
| 🌠 Nova | 93% | 2 (ready when others flag, PUBLIC_PATHS #248 R1 — correct) | 0 |
| 💫 Vega | 85% | 5 (#125 R1, gen ID reuse #190 R4, own-message-unread #192 R2, parseCookies DoS #248 R1, localStorage XSS #248 R2) | 0 |

## Severity Calibration

| Reviewer | Verdict matches final | Over-flags | Under-flags |
|----------|----------------------|------------|-------------|
| 🌟 Stella | 80% | 15% (WS scoping, build-order, same-ms monotonicity) | 5% |
| 🌠 Nova | 95% | 3% | 2% |
| 💫 Vega | 82% | 12% (#125 R1, #176 R2, #190 R3, #191 R2 — ❌ Major over-escalation) | 6% |

## False Positive Rate (Critical flagged → later proven non-issue)

| Reviewer | False Positives | Total Criticals | FP Rate |
|----------|----------------|-----------------|---------|
| 🌟 Stella | 1 (WS scoping as blocker for #168) | ~25 | 4% |
| 🌠 Nova | 0 | ~23 | 0% |
| 💫 Vega | 1 (#168 R2 oversized; #125 R1 over-flagged) | ~19 | 5% |

## Reliability History

| Reviewer | Early (PRs #96-#145) | Mid (#155-#167) | Recent (#168-#240) | Trend |
|----------|---------------------|-----------------|--------------------|----|
| 🌟 Stella | 12/12 (100%) | 8/8 (100%) | 51/53 (96%) | → (one timeout #176 R1, one late #190 R5) |
| 🌠 Nova | 12/12 (100%) | 8/8 (100%) | 53/53 (100%) | → |
| 💫 Vega | 8/12 (67%) | 6/8 (75%) | 49/50 (98%) | ↑ Significant improvement after prompt fixes |

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
| #202 | cove | 2026-06-05 | R1-R3 | ✅ Ready | snowflake-auth-token, migration-overflow, index-bypass |
| #222 | cove | 2026-06-05 | R1-R3 | ✅ Ready | stale-last-message-id, broken-clear-route, bulk-delete-allowlist |
| #240 | cove | 2026-06-05 | R1-R2 | ✅ Ready | grid-clips-input, ios-safe-area, token-semantics |
| #248 | cove | 2026-06-06 | R1-R4 | ✅ Ready | bff-cookie-security, public-paths-break, parsecookies-dos, localstorage-xss |

## Ground Truth Summary (26 merged PRs with ground truth)

- **Human blind spots found by us:** 0 — human has never caught something we missed
- **Our blind spots:** 0 — human has never flagged something all 3 reviewers missed
- **Human rubber-stamp rate:** 96% — human approved without findings in 25/26 cases. Exception: #174 where human asked design-level questions while our review caught code-level safety. Complementary perspectives.
- **Iterative review as quality gate:** In 22/26 PRs, our multi-round review was the actual quality gate (human approved final state without independent analysis)
- **Over-flagging instances:** 1 (#100 — verdict too conservative for personal project context)
- **Multi-round PRs:** 22/26 PRs went through 2+ rounds. Average rounds: 2.7. Max: 7 (#190)
- **Total review rounds:** 73 across 26 PRs

## Actionable Notes

1. **✅ Vega unique find rate improving to 14% (above 10% threshold).** @me alias find (#222 R2) and getComputedStyle race (#240 R2) show continued value in edge-case detection. Star finds remain the high-water mark.

2. **Stella client-side regression detection confirmed as emerging dimension:** #222 R1 found client clear button 404 + MESSAGE_DELETE_BULK not handled — both client regressions from server-side refactoring. Nova/Vega missed these entirely. Stella's build-verification approach catches cross-boundary breaks.

3. **Nova zero false positives across 69 rounds.** Best-calibrated reviewer. Continue using Nova's verdict as tiebreaker when Stella and Vega disagree.

4. **Vega reliability now 100% in last 25 rounds.** Early 67% → mid 75% → recent 100%. Prompt fixes fully effective. No longer needs monitoring.

5. **Vega severity over-escalation:** Notably in #222 R1, Vega approved (✅ Ready) while missing stale last_message_id — the opposite pattern (under-flagging). This balances the earlier over-escalation instances. May indicate inconsistent severity calibration rather than systematic bias in one direction.

6. **PR #222 validated cross-boundary review value:** Stella R1 found that server-side route deletion broke the client clear button — a regression from the #192 read-state work. This is a unique contribution that code-reading-only reviewers miss.

7. **CSS/UI dimension expanding:** #240 is the second CSS-focused PR (after #191). All 3 reviewers caught the grid-clips-input issue unanimously. Vega contributed safe-area background gap. Consider adding UI/layout to default prompt dimensions.

8. **PR #202 security finding (snowflake-as-auth-token)** — most severe finding since XSS in #156. All 3 reviewers caught it unanimously. Security detection prompt working well.

9. **SQLite migration correctness** appeared in #144, #168, #178, #202 — 4 PRs now. Still project-specific (cove uses SQLite). No default prompt change needed.

10. **Stella's global idMap collision (#202 R2)** — unique cross-table reasoning that prevented data corruption during migration. Confirms her strength in systematic data-flow analysis.

11. **All 3 open PRs from 2026-06-05 merged same day.** Total 8 rounds across 3 PRs. Review→merge pipeline running at full speed. Average time from first review to merge: ~3h.

12. **PR #248 (OAuth token leak — BFF pattern) merged 2026-06-06.** 4-round security review. All 3 reviewers contributed unique finds: Nova caught PUBLIC_PATHS signup break, Vega caught parseCookies DoS + localStorage XSS remnant, Stella caught NODE_ENV + WS lifecycle gaps. Security checklist all-green. Best security PR review to date.

13. **#248 validates all-reviewer security coverage:** Each reviewer found a distinct security vector — Nova (auth routing), Vega (input sanitization + XSS), Stella (deployment config + lifecycle). No single reviewer would have caught all issues. Multi-reviewer approach justified for security PRs.

14. **Vega input sanitization emerging as new strength dimension.** parseCookies URIError DoS (#248) + localStorage XSS remnant — both unique finds with concrete exploit paths. Added "Input Sanitization/DoS" to Vega's dimension profile.
