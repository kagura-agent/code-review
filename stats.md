# Code Review Service — Reviewer Stats

_Last updated: 2026-06-17 08:26 (Asia/Shanghai)_

## Per-Reviewer Performance

| Reviewer | Model | Total Review Rounds | Reliability | Trend |
|----------|-------|---------------------|-------------|-------|
| 🌟 Stella | gpt-5.5 | 202 | 197/202 (98%) → | 5 failures total (#176 R1 timeout, #190 R5 late, #255 R2 miss, #278 R5 timeout, #348 R3 failed 2x). Stable. #357-#387 clean (6 PRs, 2 rounds in #387). |
| 🌠 Nova | claude-opus-4.7 | 203 | 201/203 (99%) → | Two timeouts: #352 R5, #369 R1 (re-spawned successfully). 99% across 203 rounds. Worth monitoring if frequency increases. |
| 💫 Vega | gemini-2.5-pro (was gemini-3.1-pro-preview through #356) | 198 | 179/198 (90%) → | 19 pre-#357 issues + #357-#369 all clean output. **Model switched to gemini-2.5-pro on 2026-06-15. 4 PRs with new model — reliability improved (12/12 clean output), calibration gap persists.** Not used in #387 (2-reviewer run). Idle 1 PR. |

## Dimension Strengths (per reviewer)

### 🌟 Stella (GPT-5.5)
| Dimension | Strength | Evidence |
|-----------|----------|----------|
| DB/Migration | ⭐⭐⭐ | SQLite ALTER TABLE (#168), migration ordering (#144), FK pragma-in-transaction (#178 R1 — reproduced locally), FK safety (#174), migration seq overflow (#202 R1) |
| Build Verification | ⭐⭐⭐ | Only reviewer who runs `pnpm -r build` — caught tsc failure (#165 R1), verified tests every round. #255: verified 152 server + 38 plugin tests. #261: verified server + client build |
| Security (Auth) | ⭐⭐⭐ | Ghost presence (#167), presences membership (#168), stale guildIds (#179 R1), snowflake-as-auth-token (#202 R1), bot permission bypass (#352 R1) |
| Async/Concurrency | ⭐⭐ | Async handler ordering race (#190 R5), queued side-effect race (#190 R4), auto-ack race (#192 R1) |
| Testing Gaps | ⭐⭐⭐ | Ack endpoint test coverage (#192 R1), fake test detection (#178 R2), product-impact of .catch swallowing (#192 R1) |
| Accessibility/A11y | ⭐⭐ | Focus ring WCAG violation (#191 R2), high-contrast mode (#191 R3), send button aria-label (#191 R3) |
| Lifecycle Analysis | ⭐⭐⭐ | Auto-ack dedup (#192 R3-R4), reload dedup gap (#192 R4), same-ms monotonicity (#192 R4) |
| Auth/Cookie Security | ⭐⭐⭐ | pendingToken leak (#248 R1), NODE_ENV cookie Secure (#248 R2-R3), logout doesn't close WS (#248 R3) |
| Protocol/Gateway | ⭐⭐⭐ | RESUMED abort semantics (#255 R1), WS fallback gap (#261 R1), WS session outlives expired token (#264 R5) |
| Control Flow Analysis | ⭐⭐⭐ | try/catch non-functional fix (#255 R5), stuck spinner on channel switch (#330 R3) |
| Session/Auth Lifecycle | ⭐⭐⭐ | Cookie reissue gap (#264 R3), OAuth non-atomic (#264 R4), WS session lifetime (#264 R5) |
| React Hooks Hygiene | ⭐⭐⭐ | Ref mutation during render (#278 R2, #278 R4), scrollContainerRef read during render |
| Cross-Module Verification | ⭐⭐⭐ | guild_id payload mismatch (#327 R5 — traced through 3 source files across 2 packages) |
| State Lifecycle | ⭐⭐⭐ | prepend-triggers-scroll interaction (#330 R1), stuck spinner on channel switch (#330 R3), guild scoping leak in mentions (#337 R1), edit path missing resolveMentions (#337 R1), files array flash (#352 R3), **cross-channel sidebar corruption (#356 R1 — unique find)** |
| Test Requirements | ⭐⭐⭐ | Most persistent on negative auth tests (#316 R4), delete confirmation (#331 R1), retry loses reply (#335 R1) |
| Edge Case Reasoning | ⭐⭐ | Stale cached messages freeze unread computation (#346 R3 — valid but over-scoped), banner dismissal + suppressed scroll events (#346 R2), server-side auth scope analysis (#343 R1) |
| Cross-Round Tracking | ⭐⭐⭐ | toUser() propagation gap (#348 R1 — unique find), mention key collision by display name (#348 R2), CI shell injection (#348 R2 — co-found with Nova) |
| Runtime Error Analysis | ⭐⭐ | **NEW: TimeoutError vs AbortError semantics (#352 R5 — unique find, verified locally). Rate-limit bucket gap (#352 R2). GET/DELETE filename validation (#352 R1).** |
| Config/Schema Validation | ⭐⭐ | **NEW: Plugin manifest schema missing `accounts` field (#369 R1 — consensus with Nova). Schema-runtime divergence detection.** |

**Stella's superpower:** Runs actual builds + reproduces bugs locally. Catches things pure code reading misses. Deepest lifecycle analysis. Most persistent on escalation rules. Cross-module verification. State lifecycle reasoning. Config/schema validation.
**Stella's weakness:** Sometimes over-scopes (flags out-of-PR architectural concerns as blocking). Occasionally over-strict on severity. #348 R3 multi-round failure (GPT-5.5 garbled output 2x) was single incident, not repeated in #352-#369.

### 🌠 Nova (Claude Opus 4.7)
| Dimension | Strength | Evidence |
|-----------|----------|----------|
| API Design | ⭐⭐⭐ | Breaking changes (#175), API compatibility, positional arg drift (#168), topic nullability (#174) |
| Security | ⭐⭐⭐ | IDOR (#168 R3), cross-guild leak (#143), typing indicator leak (#190 R1), snowflake-as-auth-token (#202 R1), bot permission bypass (#352 R1) |
| Architecture | ⭐⭐⭐ | Timer leak (#176 R2), event model verification (#176 R1), self-broadcast lifecycle (#179 R2), READY payload growth (#192 R1) |
| Async/Concurrency | ⭐⭐⭐ | Queued side-effect race trace (#190 R5), handler ordering (#190 R6), ack cursor monotonicity race (#192 R2) |
| Severity Calibration | ⭐⭐⭐ | Most accurately calibrates critical vs suggestion. Rarely over-flags. Best tiebreaker when others disagree |
| Accessibility/A11y | ⭐⭐⭐ | WCAG 2.4.7 (#191 R2), aria-label (#191 R1), matchMedia mobile detection (#191 R2) |
| Auth Route Analysis | ⭐⭐⭐ | PUBLIC_PATHS signup break (#248 R1), resolveUser duplication (#248 R2-R3) |
| Retry/Idempotency | ⭐⭐⭐ | Retry-After NaN (#255 R1), POST retry duplicates (#255 R2), sendTyping budget (#255 R2) |
| Session TTL/Auth | ⭐⭐⭐ | Non-sliding session design flaw (#264 R2), bot footgun (#264 R4), backfill hardcode (#264 R4) |
| Security Model Design | ⭐⭐⭐ | Token exfiltration (#294 R1 — unique), webhook permission model (#294 R1), READY payload leak (#316 R2), CHANNEL_CREATE unreachable (#316 R3) |
| UX-Level Analysis | ⭐⭐⭐ | spinner scroll jolt (#330 R2 — unique), pendingPrependRestoreRef leak (#330 R3 — unique), token redaction (#331 R1), reply state cleanup (#335 R1), mention count cap (#337 R1), self-mention highlight (#339 R1), mentionMapRef channel-switch (#339 R1), 8 unique UX/arch findings (#343 R1) |
| Feature Correctness | ⭐⭐⭐ | "Mark as Read" doesn't actually ack (#346 R1 — unique critical), unread count lies (#346 R2 — unique), pill positioning (#346 R1-R2 — escalated), "+" suffix disappears (#346 R3 — unique low-pri) |
| Regression Detection | ⭐⭐⭐ | OAuth COALESCE regression in #348 R3 — caught R2 re-introducing R1 bug. CI shell injection (#348 R2). given_name length cap (#348 R3 — unique). Ran all 246 tests locally in R4. |
| Plugin/Integration Analysis | ⭐⭐⭐ | **NEW: dispatch.ts catch-all re-swallow defeats rest-client fix (#352 R3 — unique). Regex status matching fragile (#352 R3 — unique). 30s×3 timeout on hot dispatch path (#352 R3). Size cap asymmetry 100KB/8KB (#352 R1 — unique). UntrustedStructuredContext production verification (#352 R6). 5xx CoveApiError inconsistency (#352 R4). UTF-16 vs byte measurement (#352 R1 — unique).** |
| Config/Schema Validation | ⭐⭐⭐ | **NEW: Plugin manifest schema missing `accounts` field (#369 R1 — consensus with Stella). Dead code fallback in account resolution (#369 R1 — unique). Deep SDK trace to verify resolution path.** |

**Nova's superpower:** Best calibration. Most suggestions per review, almost all actionable. **One false positive across 182 rounds (0.5% FP rate)**. Strongest on API compatibility, security model design, async lifecycle, UX-level analysis, feature correctness, regression detection, plugin integration analysis, and config/schema validation. #352 R3's dispatch re-swallow find was the most impactful unique of that PR. #369 schema blocker caught alongside Stella.
**Nova's weakness:** Two timeouts now (#352 R5, #369 R1). May indicate context length or complexity sensitivity. Still exceptional overall.

### 💫 Vega (Gemini 2.5 Pro — switched 2026-06-15, was Gemini 3.1 Pro)
| Dimension | Strength | Evidence |
|-----------|----------|----------|
| Security (Code-level) | ⭐⭐⭐ | Prototype pollution (#176 R1, unique), IDOR framing (#168 R3, clearest) |
| Async/Concurrency | ⭐⭐⭐ | Generation ID reuse via .delete() (#190 R4 — star find of entire review history) |
| Product Impact | ⭐⭐⭐ | O(N²) presence (#179 R2), own-message-causes-unread (#192 R2 — star find) |
| Input Sanitization/DoS | ⭐⭐⭐ | parseCookies URIError DoS (#248 R1), localStorage XSS remnant (#248 R2) |
| Runtime Error Detection | ⭐⭐⭐ | 204 JSON parsing retry storm (#255 R2 — star find) |
| Session TTL Edge Cases | ⭐⭐⭐ | Sliding threshold math bug (#264 R3 — unique), stale expires_at (#264 R5) |
| Framework-Level Analysis | ⭐⭐ | React 18 batching breaks scroll-restore (#330 R1 — star quality find with concrete flushSync fix) |
| Performance Regression | ⭐⭐ | O(N²) render regression (#346 R2 — all 3 found it, but Vega escalated to ❌ Major Issues). Batch message pill counter (#346 R1 — unique). No-scrollbar edge case (#346 R2 — unique) |
| OAuth/Auth Edge Cases | ⭐⭐ | OAuth COALESCE semantics (#348 R1 — unique find, user-cleared names overwritten). COALESCE regression catch (#348 R3 — co-found with Nova). |

**Vega's superpower:** Fast (~1m avg). Capable of star-quality finds when the bug is deterministic/logical (gen ID reuse #190, 204 JSON parsing #255, React 18 batching #330, OAuth COALESCE #348). Cleanest fix suggestions.
**Vega's weakness:** ⚠️ **Calibration continues deteriorating.** Four distinct failure patterns:
1. **Over-lenient** — approves Ready when real bugs exist: #330 R2 (missed spinner jolt + firstMessageIdRef), #330 R3 (missed stuck spinner), #335 R1 (missed lifecycle issues), #348 R2 (missed CI shell injection — security blind spot), **#369 R1 (missed schema/manifest blocker — cross-file validation blind spot)**
2. **Over-strict** — escalates to ❌ when ⚠️ is appropriate: #330 R4, #331 R2 (arg parsing to Critical), #346 R2, #348 R4, **#352 R3-R4 (optimization items to ❌ Major — repeated twice in same PR)**
3. **Under-verification** — doesn't check whether fixes actually work: #327 R5 (Ready when bridge non-functional), #261 R3 (premature Ready)
4. **Reliability** — increasing retry/failure rate: 2 retries + 1 complete miss in #348; retry R1 + failed-but-wrote R6 in #352
5. **Cross-file/manifest validation** — **NEW: #369 R1 — Vega approved Ready while plugin manifest schema was missing the `accounts` field. Both Stella and Nova caught this independently. This is Vega's weakest dimension.**

## Unique Find Rate (last 10 PRs: #330 through #369)

| Reviewer | Unique Finds | Total Issues Found | Unique Rate | Trend |
|----------|-------------|-------------------|-------------|-------|
| 🌟 Stella | 25 | ~193 | ~13% | → Stable. #387: extra fields stripping (R2 dissent, valid hardening follow-up). Consistent edge-case finder. |
| 🌠 Nova | 40 | ~193 | ~21% | ↑↑ Widening lead. #387: metadata schema owner + CLI usage string (2 unique). Dominant. |
| 💫 Vega | 9 | ~193 | ~5% | ↓↓ Still below 10% threshold. Not used in #387. **Below 10% for 15+ consecutive periods. 4 PRs with gemini-2.5-pro: reliability up, unique finds still low.** |

## Consensus Participation

| Reviewer | Part of 2/3+ consensus | Solo dissent (correct) | Solo dissent (noise) |
|----------|----------------------|----------------------|---------------------|
| 🌟 Stella | 87% | 21 (incl. stuck spinner #330 R3, guild_id #327 R5, toUser #348 R1, TimeoutError #352 R5, cross-channel-sidebar #356 R1, webhook-bypass #357 R4, migration-concern #357 R5) | 2 (#168 over-scope, #346 R3 over-scoped stale cache) + 1 likely FP (#357 R5 migration) |
| 🌠 Nova | 93% | 22 (incl. spinner jolt #330, Mark-as-Read #346, dispatch re-swallow #352 R3, THREAD_DELETE-dead-code #357 R2, PATCH-archive-permission #357 R3, THREAD_UPDATE-broadcast #357 R4) | 1 (#330 R5 over-cautious) |
| 💫 Vega | 75% | 11 (gen ID #190, 204 parsing #255, React 18 #330, OAuth COALESCE #348, owner_id NULL #357 R4, floating promise #367) | 12 (#261 R3, #290, #327 R5, #330 R2/R3, #331 R2, #348 R2, #352 R3-R4, #356 R1 under-detected, #357 R2 over-escalated, #357 R4 over-held, **#369 R1 under-detected**) |

## Severity Calibration

| Reviewer | Verdict matches final | Over-flags | Under-flags |
|----------|----------------------|------------|-------------|
| 🌟 Stella | 82% | 14% | 4% |
| 🌠 Nova | 94% | 4% | 2% |
| 💫 Vega | 65% | 19% | 16% (#369 R1 ✅ Ready when ⚠️ Needs Changes was correct — under-flagged schema blocker) |

## False Positive Rate (Critical flagged → later proven non-issue)

| Reviewer | False Positives | Total Criticals | FP Rate |
|----------|----------------|-----------------|---------|
| 🌟 Stella | 1 (#168 WS scoping as blocker) + 1 likely (#357 R5 migration) | ~44 | 2-5% |
| 🌠 Nova | 0 | ~51 | 0% |
| 💫 Vega | 3 (#168 R2, #290 pre-existing, #331 R2 arg parsing) | ~39 | 8% |

## Reliability History

| Reviewer | Early (#96-#145) | Mid (#155-#264) | Recent (#278-#367) | Trend |
|----------|---------------------|-----------------|--------------------|----|
| 🌟 Stella | 12/12 (100%) | 95/97 (98%) | 84/87 (97%) | → Stable |
| 🌠 Nova | 12/12 (100%) | 97/97 (100%) | 88/90 (98%) | → (two timeouts #352 R5 + #369 R1, monitoring) |
| 💫 Vega | 8/12 (67%) | 89/97 (92%) | 78/85 (92%) | → Uptick (#357 + #367 + #369 all produced output, calibration gap persists) |

## Vega Calibration Swing Pattern

**Recurring within single PRs — now confirmed across 3 PRs:**

### #330 (5 rounds)
| Round | Vega Verdict | Correct Verdict | Assessment |
|-------|-------------|-----------------|------------|
| R2 | ✅ Ready | ⚠️ Needs Changes | Over-lenient |
| R3 | ✅ Ready | ⚠️ Needs Changes | Over-lenient |
| R4 | ❌ Major Issues | ⚠️ Needs Changes | Over-strict |
| R5 | ✅ Ready | ✅ Ready | Correct |

### #352 (6 rounds)
| Round | Vega Verdict | Correct Verdict | Assessment |
|-------|-------------|-----------------|------------|
| R1 | ⚠️ Needs Changes | ⚠️ Needs Changes | ✅ Correct |
| R2 | ⚠️ Needs Changes | ⚠️ Needs Changes | ✅ Correct |
| R3 | ❌ Major Issues | ⚠️ Needs Changes | Over-strict (optimization items) |
| R4 | ❌ Major Issues | ⚠️ Needs Changes | Over-strict (same items, no learning) |
| R5 | ✅ Ready | ✅ Ready | ✅ Correct (with explicit calibration prompt) |
| R6 | ✅ Ready | ✅ Ready | ✅ Correct |

**Key insight from #352:** Vega R3-R4 repeated the same over-escalation pattern — no self-correction between rounds until explicit calibration guidance was added in R5 prompt. When guided, Vega calibrates correctly (R5-R6). Without guidance, it over-escalates or under-detects.

### #356 (2 rounds)
| Round | Vega Verdict | Correct Verdict | Assessment |
|-------|-------------|-----------------|------------|
| R1 | ✅ Ready | ⚠️ Needs Changes | Over-lenient (missed cross-channel bug) |
| R2 | ✅ Ready | ✅ Ready | ✅ Correct |

**#356 note:** Same under-detection pattern as #330 R2/R3, #335 R1, #348 R2. Vega approved Ready while a real cross-channel corruption bug existed.

### #357 (5 rounds) — first PR with gemini-2.5-pro
| Round | Vega Verdict | Correct Verdict | Assessment |
|-------|-------------|-----------------|------------|
| R1 | ⚠️ Needs Changes | ⚠️ Needs Changes | ✅ Correct |
| R2 | ❌ Major Issues | ⚠️ Needs Changes | Over-strict (N+1 + nested threads) |
| R3 | ⚠️ Needs Changes | ⚠️ Needs Changes | ✅ Correct |
| R4 | ⚠️ Needs Changes | ✅ Ready | Over-held (owner_id NULL is follow-up tier) |
| R5 | ✅ Ready | ✅ Ready | ✅ Correct |

**#357 note:** First PR with gemini-2.5-pro. Reliability improved (5/5 output). Calibration: 3/5 correct, R2 over-escalated, R4 over-held. Pattern persists from gemini-3.1-pro but slightly better (R3 and R5 correct vs previous swings). Model change has marginally improved calibration but not enough.

### #369 (3 rounds) — 4th PR with gemini-2.5-pro
| Round | Vega Verdict | Correct Verdict | Assessment |
|-------|-------------|-----------------|------------|
| R1 | ✅ Ready | ⚠️ Needs Changes | Over-lenient (missed schema blocker) |
| R2 | ❌ Major Issues | ⚠️ Needs Changes | Over-strict (same escalation pattern) |
| R3 | ✅ Ready | ✅ Ready | ✅ Correct |

**#369 note:** Classic Vega swing: R1 under-detected (approved when real schema blocker existed), R2 over-corrected to ❌ Major, R3 correct. 4th PR with gemini-2.5-pro. Same calibration swing pattern as gemini-3.1-pro. 1/3 correct verdicts this PR.

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
| #176 | cove | 2026-06-04 | R1-R3 | ✅ Ready | prototype-pollution, timer-leak |
| #178 | cove | 2026-06-04 | R1-R3 | ✅ Ready | sqlite-pragma-transaction, fake-test |
| #179 | cove | 2026-06-04 | R1-R3 | ✅ Ready | stale-auth-state, guild-lifecycle |
| #190 | cove | 2026-06-04 | R1-R7 | ✅ Ready | gen-id-reuse, async-handler-ordering |
| #191 | cove | 2026-06-04 | R1-R3 | ✅ Ready | ime-composition, focus-ring-a11y |
| #192 | cove | 2026-06-05 | R1-R4 | ✅ Ready | read-state-reload, own-message-unread |
| #202 | cove | 2026-06-05 | R1-R3 | ✅ Ready | snowflake-auth-token, migration-overflow |
| #222 | cove | 2026-06-05 | R1-R3 | ✅ Ready | stale-last-message-id, broken-clear-route |
| #240 | cove | 2026-06-05 | R1-R2 | ✅ Ready | grid-clips-input, ios-safe-area |
| #248 | cove | 2026-06-06 | R1-R4 | ✅ Ready | bff-cookie-security, parsecookies-dos |
| #249 | cove | 2026-06-06 | R1-R2 | ✅ Ready | guildless-user-stuck |
| #250 | cove | 2026-06-06 | R1 | ✅ Ready | pure-refactor |
| #251 | cove | 2026-06-06 | R1 | ✅ Ready | wire-format-defaults |
| #252 | cove | 2026-06-06 | R1-R2 | ✅ Ready | presence-mutation-bug |
| #254 | cove | 2026-06-06 | R1-R2 | ✅ Ready | hardcoded-guild-removal |
| #255 | cove | 2026-06-06 | R1-R6 | ✅ Ready | resumed-abort, 204-json-parsing, try-catch-control-flow |
| #261 | cove | 2026-06-07 | R1-R4 | ✅ Ready | retry-duplicate, ws-fallback, token-bucket |
| #263 | cove | 2026-06-07 | R1-R2 | ✅ Ready | broadcastToGuilds-optimization |
| #264 | cove | 2026-06-07 | R1-R6 | ✅ Ready | session-ttl-data-loss, sliding-threshold-math |
| #278 | cove | 2026-06-09 | R1-R5 | ✅ Ready | scroll-listener, stale-cache-clobber, ref-in-render |
| #279 | cove | 2026-06-09 | R1 | ✅ Ready | tuple-comparison-pagination |
| #281 | cove | 2026-06-10 | R1 | ⚠️ False positive | stale-description-driven false positives |
| #287 | cove | 2026-06-10 | R1-R2 | ✅ Ready | resolver-throws, guildId-leak |
| #290 | cove | 2026-06-10 | R1 | ✅ Ready | dispatch-timeout-removal |
| #294 | cove | 2026-06-10 | R1-R5 | ✅ Ready | token-exfiltration, rate-limiting, permission-model |
| #303 | cove | 2026-06-11 | R1-R2 | ✅ Ready | mobile-double-fixed |
| #308 | cove | 2026-06-11 | R1 | ✅ Ready | scrollbar-reflow |
| #314 | cove | 2026-06-11 | R1 | ✅ Ready | bot-creation-deletion |
| #316 | cove | 2026-06-11 | R1-R5 | ✅ Ready | permission-self-grant, ready-payload-leak |
| #322 | cove | 2026-06-11 | R1 | ✅ Ready | underscore-italic-word-boundary |
| #326 | cove | 2026-06-11 | R1 | ✅ Ready | underscore-italic-closing-delimiter |
| #327 | cove | 2026-06-11 | R1-R5 | ✅ Ready | send-race, guild-id-payload-mismatch |
| #329 | cove | 2026-06-12 | R1 | ✅ Ready | own-message-auto-scroll |
| #330 | cove | 2026-06-12 | R1-R5 | ✅ Ready | channel-switch-race, prepend-auto-scroll, React-18-batching, spinner-jolt, stuck-spinner |
| #331 | cove | 2026-06-12 | R1-R2 | ✅ Ready | error-handling, delete-confirmation, token-redaction |
| #335 | cove | 2026-06-12 | R1-R3 | ✅ Ready | deleted-ref-visibility, retry-loses-reply, reply-state-cleanup |
| #337 | cove | 2026-06-12 | R1-R2 | ✅ Ready | enter-trap, cursorPos-stale, guild-scoping-leak, edit-mention-resolution |
| #339 | cove | 2026-06-13 | R1-R2 | ✅ Ready | replaceAll-mention-corruption, webhook-mention-resolution, dangling-autocomplete |
| #343 | cove | 2026-06-13 | R1 | ✅ Ready | context-menu-delete, server-auth-pre-existing, a11y |
| #346 | cove | 2026-06-13 | R1-R3 | ✅ Ready | new-line-unreachable, null-read-cursor, O(N²)-render, mark-as-read-ack |
| #348 | cove | 2026-06-14 | R1-R4 | ✅ Ready | toUser-propagation, COALESCE-regression, CI-shell-injection |
| #352 | cove | 2026-06-14 | R1-R6 | ✅ Ready | bot-permission-bypass, dispatch-catch-reswallow, cove-md-timeout, UntrustedStructuredContext |
| #356 | cove | 2026-06-14 | R1-R2 | ✅ Ready | cross-channel-sidebar-corruption, unbounded-cache-lru |
| #357 | cove | 2026-06-15 | R1-R5 | ✅ Ready | thread-permission, archive-enforcement, guild-leak, message-count |
| #367 | cove | 2026-06-16 | R1 | ✅ Ready | per-channel-message-queue, FIFO-dispatch |
| #369 | cove | 2026-06-16 | R1-R3 | ✅ Ready | manifest-schema-validation, error-forwarding, multi-account-tests |
| #387 | cove | 2026-06-16 | R1-R2 | ✅ Ready | reply-to-validation, metadata-schema, test-coverage |

## Ground Truth Summary (61 merged PRs)

- **Human blind spots found by us:** 0 — human has never caught something we missed
- **Our blind spots:** 0 — human has never flagged something all 3 reviewers missed
- **Human rubber-stamp rate:** 97% — human approved without findings in 59/61 cases. Exceptions: #174 (design questions), #281 (false positive)
- **Iterative review as quality gate:** In 59/61 merged PRs, our multi-round review was the actual quality gate
- **Over-flagging instances:** 2 (#100 verdict too conservative, #281 stale PR description)
- **Multi-round PRs:** 49/61 merged PRs went through 2+ rounds. Average rounds: 2.7. Max: 7 (#190). #387 currently at R2 (open).
- **Total review rounds:** ~225 across 62 PRs (+ 1 open)
- **False-ready detection:** 4 cases (#255 R4→R5, #330 R4 Vega swing, #348 R2 Vega approved Ready while CI injection existed, #369 R1 Vega approved Ready while schema blocker existed) — self-correcting system working
- **Escalation protocol validated:** 7 cases — all led to fixes (#369 R2 escalated error swallowing + test coverage to Major)

## Actionable Notes

1. **🟡 Vega: gemini-2.5-pro evaluation — 4/5 PRs complete.** #357 (5 rounds) + #367 (1 round) + #369 (3 rounds). Results: reliability improved (12/12 clean output), calibration still weak (#369 R1 missed schema blocker, R2 over-escalated to ❌ Major Issues). Unique find rate: 2 minor uniques across 4 PRs (zero in #369). **1 more PR needed. If calibration doesn't improve, replace Vega slot.**

2. **Vega calibration prompt: add cross-file/manifest dimension.** #369 showed Vega's blind spot on schema-runtime divergence. The default prompt now has a "Config & Schema Consistency" dimension (added this reflection). Monitor whether Vega catches this class of issue going forward.

3. **Nova's second timeout (#369 R1 after #352 R5).** Two incidents now across 199 rounds. Both on plugin-related PRs. May indicate that plugin PRs with SDK tracing are context-heavy. Worth monitoring — if 3rd timeout occurs, consider adjusting Nova's timeout or context budget for plugin PRs.

4. **#281 stale-description pattern still unaddressed in prompts.** Need to add: "Verify understanding of feature matches actual code, not just PR description." Low priority since it hasn't recurred.

5. **Nova continues zero false positives across 195 rounds.** Best-calibrated reviewer. Continue using Nova's verdict as tiebreaker.

6. **Stella stable.** No issues in #367-#369. Schema/manifest validation is a confirmed strength alongside build verification.

7. **Throughput sustained.** 63 PRs (62 merged + 1 open), ~229 review rounds, 22 days. ~2.9 PRs/day, ~10.4 reviewer-rounds/day.

8. **Ground truth: human rubber-stamps 97%.** Our iterative review IS the quality gate.

9. **Nova widening gap significantly.** 20% unique find rate vs Stella 13% vs Vega 5%. Nova finds ~4× more unique issues than Vega. #369 R3: Nova and Vega both Ready, Stella dissented (over-scoped) — Nova's calibration remains best.

10. **Multi-round PR pattern emerging.** Complex feature PRs consistently need 4+ rounds. Reviewer fatigue may affect Vega most.

11. **Prompt evolved: added "Config & Schema Consistency" dimension (#8).** Triggered by #369 — Vega's miss of the manifest schema gap. This dimension was implicit before; now explicit. Should help all reviewers but especially Vega on plugin/config PRs.
