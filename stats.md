# Code Review Service - Reviewer Stats


_Last updated: 2026-07-23 02:30 (Asia/Shanghai)_

## Per-Reviewer Performance

| Reviewer | Model | Total Review Rounds | Reliability | Trend |
|----------|-------|---------------------|-------------|-------|
| 🌟 Stella | gpt-5.5 | 242 | 236/242 (98%) → | 6 failures total. #411-#460: all clean output. Stable. |
| 🌠 Nova | claude-opus-4.7 | 244 | 241/244 (99%) → | Three timeouts total (#352 R5, #369 R1, #400 R2). #411-#460: all clean. |
| 💫 Vega | gemini-2.5-pro (was gemini-3.1-pro-preview through #356) | 239 | 219/239 (92%) → | #411-#460: all clean output. 26th post-switch PR. |

_Note: #447 merged 2026-07-03T07:27Z. Human approved without comments._
_#450 (fix: ConnectionBanner) and #453 (feat: webhook guidance) merged 2026-07-07 — small PRs, human-approved without code review service._
_#455 (chore: remove cove-webhook skill) closed without merge 2026-07-08._
_#457 merged 2026-07-09T04:17Z — 3/3 unanimous Ready. Human approved without comments._
_#459 (fix: groupAllowFrom schema) merged 2026-07-14T06:15Z — small config fix, human-approved without code review service._
_#456 (feat: cove-ops skill update) merged 2026-07-15T05:38Z — skill file update, no code review service run._
_#460 opened 2026-07-15 — R1: 3/3 unanimous Approve. Cross-channel messaging API (548+, 17-). Still awaiting human review (8 days, no activity since 2026-07-16)._
_Closed without merge: #422 (fix: silent reply loss diagnostics — closed 2026-07-09, superseded by #457)._

## Dimension Strengths (per reviewer)

### 🌟 Stella (GPT-5.5)
| Dimension | Strength | Evidence |
|-----------|----------|----------|
| DB/Migration | ⭐⭐⭐ | SQLite ALTER TABLE (#168), migration ordering (#144), FK pragma-in-transaction (#178 R1 - reproduced locally), FK safety (#174), migration seq overflow (#202 R1) |
| Build Verification | ⭐⭐⭐ | Only reviewer who runs `pnpm -r build` - caught tsc failure (#165 R1), verified tests every round. #255: verified 152 server + 38 plugin tests. #261: verified server + client build |
| Security (Auth) | ⭐⭐⭐ | Ghost presence (#167), presences membership (#168), stale guildIds (#179 R1), snowflake-as-auth-token (#202 R1), bot permission bypass (#352 R1), missing-security-tests-as-Critical (#432 R1) |
| Async/Concurrency | ⭐⭐ | Async handler ordering race (#190 R5), queued side-effect race (#190 R4), auto-ack race (#192 R1) |
| Testing Gaps | ⭐⭐⭐ | Ack endpoint test coverage (#192 R1), fake test detection (#178 R2), product-impact of .catch swallowing (#192 R1) |
| Accessibility/A11y | ⭐⭐ | Focus ring WCAG violation (#191 R2), high-contrast mode (#191 R3), send button aria-label (#191 R3) |
| Lifecycle Analysis | ⭐⭐⭐ | Auto-ack dedup (#192 R3-R4), reload dedup gap (#192 R4), same-ms monotonicity (#192 R4) |
| Auth/Cookie Security | ⭐⭐⭐ | pendingToken leak (#248 R1), NODE_ENV cookie Secure (#248 R2-R3), logout doesn't close WS (#248 R3) |
| Protocol/Gateway | ⭐⭐⭐ | RESUMED abort semantics (#255 R1), WS fallback gap (#261 R1), WS session outlives expired token (#264 R5) |
| Control Flow Analysis | ⭐⭐⭐ | try/catch non-functional fix (#255 R5), stuck spinner on channel switch (#330 R3) |
| Session/Auth Lifecycle | ⭐⭐⭐ | Cookie reissue gap (#264 R3), OAuth non-atomic (#264 R4), WS session lifetime (#264 R5) |
| React Hooks Hygiene | ⭐⭐⭐ | Ref mutation during render (#278 R2, #278 R4), scrollContainerRef read during render |
| Cross-Module Verification | ⭐⭐⭐ | guild_id payload mismatch (#327 R5 - traced through 3 source files across 2 packages) |
| State Lifecycle | ⭐⭐⭐ | prepend-triggers-scroll interaction (#330 R1), stuck spinner on channel switch (#330 R3), guild scoping leak in mentions (#337 R1), edit path missing resolveMentions (#337 R1), files array flash (#352 R3), **cross-channel sidebar corruption (#356 R1 - unique find)** |
| Test Requirements | ⭐⭐⭐ | Most persistent on negative auth tests (#316 R4), delete confirmation (#331 R1), retry loses reply (#335 R1) |
| Edge Case Reasoning | ⭐⭐ | Stale cached messages freeze unread computation (#346 R3 - valid but over-scoped), banner dismissal + suppressed scroll events (#346 R2), server-side auth scope analysis (#343 R1) |
| Cross-Round Tracking | ⭐⭐⭐ | toUser() propagation gap (#348 R1 - unique find), mention key collision by display name (#348 R2), CI shell injection (#348 R2 - co-found with Nova) |
| Runtime Error Analysis | ⭐⭐ | **NEW: TimeoutError vs AbortError semantics (#352 R5 - unique find, verified locally). Rate-limit bucket gap (#352 R2). GET/DELETE filename validation (#352 R1).** |
| Config/Schema Validation | ⭐⭐ | **NEW: Plugin manifest schema missing `accounts` field (#369 R1 - consensus with Nova). Schema-runtime divergence detection.** |

**Stella's superpower:** Runs actual builds + reproduces bugs locally. Catches things pure code reading misses. Deepest lifecycle analysis. Most persistent on escalation rules. Cross-module verification. State lifecycle reasoning. Config/schema validation.
**Stella's weakness:** Sometimes over-scopes (flags out-of-PR architectural concerns as blocking). Occasionally over-strict on severity. **New: large-diff timeout pattern** - timed out on #400 R1 (2300 lines, 15min) after being stable on smaller PRs. GPT-5.5 may need longer timeout or diff-splitting for PRs >2000 lines.

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
| Security Model Design | ⭐⭐⭐ | Token exfiltration (#294 R1 - unique), webhook permission model (#294 R1), READY payload leak (#316 R2), CHANNEL_CREATE unreachable (#316 R3) |
| UX-Level Analysis | ⭐⭐⭐ | spinner scroll jolt (#330 R2 - unique), pendingPrependRestoreRef leak (#330 R3 - unique), token redaction (#331 R1), reply state cleanup (#335 R1), mention count cap (#337 R1), self-mention highlight (#339 R1), mentionMapRef channel-switch (#339 R1), 8 unique UX/arch findings (#343 R1) |
| Feature Correctness | ⭐⭐⭐ | "Mark as Read" doesn't actually ack (#346 R1 - unique critical), unread count lies (#346 R2 - unique), pill positioning (#346 R1-R2 - escalated), "+" suffix disappears (#346 R3 - unique low-pri) |
| Regression Detection | ⭐⭐⭐ | OAuth COALESCE regression in #348 R3 - caught R2 re-introducing R1 bug. CI shell injection (#348 R2). given_name length cap (#348 R3 - unique). Ran all 246 tests locally in R4. |
| Plugin/Integration Analysis | ⭐⭐⭐ | **NEW: dispatch.ts catch-all re-swallow defeats rest-client fix (#352 R3 - unique). Regex status matching fragile (#352 R3 - unique). 30s×3 timeout on hot dispatch path (#352 R3). Size cap asymmetry 100KB/8KB (#352 R1 - unique). UntrustedStructuredContext production verification (#352 R6). 5xx CoveApiError inconsistency (#352 R4). UTF-16 vs byte measurement (#352 R1 - unique).** |
| Config/Schema Validation | ⭐⭐⭐ | **NEW: Plugin manifest schema missing `accounts` field (#369 R1 - consensus with Stella). Dead code fallback in account resolution (#369 R1 - unique). Deep SDK trace to verify resolution path.** |

**Nova's superpower:** Best calibration. Most suggestions per review, almost all actionable. Strongest on API compatibility, security model design, async lifecycle, UX-level analysis, feature correctness, regression detection, plugin integration analysis, and config/schema validation. #352 R3's dispatch re-swallow find was the most impactful unique of that PR. #369 schema blocker caught alongside Stella. #432 R1: detailed attack scenario for bulk position escalation was the session's star security find.
**Nova's weakness:** Three timeouts now (#352 R5, #369 R1, #400 R2 - 49 tool calls without writing output). All on large/complex PRs. **#400 R1 had 2 false positives** (hallucinated SDK types from naming conventions) - first FP record for Nova. Still exceptional overall but large-diff handling needs attention.

### 💫 Vega (Gemini 2.5 Pro - switched 2026-06-15, was Gemini 3.1 Pro)
| Dimension | Strength | Evidence |
|-----------|----------|----------|
| Security (Code-level) | ⭐⭐⭐ | Prototype pollution (#176 R1, unique), IDOR framing (#168 R3, clearest) |
| Async/Concurrency | ⭐⭐⭐ | Generation ID reuse via .delete() (#190 R4 - star find of entire review history) |
| Product Impact | ⭐⭐⭐ | O(N2) presence (#179 R2), own-message-causes-unread (#192 R2 - star find) |
| Input Sanitization/DoS | ⭐⭐⭐ | parseCookies URIError DoS (#248 R1), localStorage XSS remnant (#248 R2) |
| Runtime Error Detection | ⭐⭐⭐ | 204 JSON parsing retry storm (#255 R2 - star find) |
| Session TTL Edge Cases | ⭐⭐⭐ | Sliding threshold math bug (#264 R3 - unique), stale expires_at (#264 R5) |
| Framework-Level Analysis | ⭐⭐ | React 18 batching breaks scroll-restore (#330 R1 - star quality find with concrete flushSync fix) |
| Performance Regression | ⭐⭐ | O(N2) render regression (#346 R2 - all 3 found it, but Vega escalated to ❌ Major Issues). Batch message pill counter (#346 R1 - unique). No-scrollbar edge case (#346 R2 - unique) |
| OAuth/Auth Edge Cases | ⭐⭐ | OAuth COALESCE semantics (#348 R1 - unique find, user-cleared names overwritten). COALESCE regression catch (#348 R3 - co-found with Nova). |

**Vega's superpower:** Fast (~1m avg). Capable of star-quality finds when the bug is deterministic/logical (gen ID reuse #190, 204 JSON parsing #255, React 18 batching #330, OAuth COALESCE #348). Cleanest fix suggestions. **#400: best performer** - only reviewer to correctly verify SDK types and catch that C1/C2 were hallucinations.
**Vega's weakness:** ⚠️ **Calibration pattern is inconsistent rather than consistently bad.** Five distinct failure modes:
1. **Over-lenient** - approves Ready when real bugs exist: #330 R2-R3, #335 R1, #348 R2, #369 R1, **#399 R1 (0 findings when 5 criticals existed)**
2. **Over-strict** - escalates to ❌ when ⚠️ is appropriate: #330 R4, #331 R2, #346 R2, #348 R4, #352 R3-R4
3. **Under-verification** - doesn't check whether fixes actually work: #327 R5, #261 R3
4. **Reliability** - crash/retry incidents: #348, #352, **#405 R1 (0 tokens, 2s crash, retry worked)**
5. **False positives on new code** - **#405 R2: raised false Critical C3 (freshSend always deletes draft) when code was guarded by `if(draftMessageId)`**
6. **Bright spots** - **#400 was Vega's best PR**: correctly caught that C1/C2 were reviewer hallucinations, verified SDK source, gave accurate Ready verdict when Stella+Nova both timed out. Shows Vega can be the most accurate reviewer when verification is the key skill.**

## Unique Find Rate (last 16 reviewed PRs: #409 through #460)

| Reviewer | Unique Finds | Total Issues Found | Unique Rate | Trend |
|----------|-------------|-------------------|-------------|-------|
| 🌟 Stella | 16 | ~95 | ~17% | → Stable. draft-deletion (#410), run-scoped-temp (#411), actionlint+regression-tests (#413), adapter-not-registered-scope (#418 R2), missing-security-tests-as-Critical (#432 R1), color-to-hex+abort-controller (#435 R1), section-level-gating (#435 R2), features-hardcode (#437 R1), shell-injection (#447 R1), message.id-gaps (#457), transaction-atomicity+WebhookType-export (#460 R1). Consistent edge-case finder. |
| 🌠 Nova | 22 | ~95 | ~23% | ↑ Still dominant. 5 unique in #410. pipefail (#411), WEBHOOK_URL validation (#413), outer-finally-test (#417), result-schema-mismatch+dead-import (#418), bulk-position-escalation-attack-scenario (#432 R1), permission-group-mismatch+SEND_TTS (#435 R1), M3-analysis (#435 R2), name-validation-dupe+channel-type-magic+error-swallowing (#437 R1), ghost-guilds-on-login (#447 R1), log-sequence+lazy-logger (#457), thread_id-validation+execute-defense-in-depth (#460 R1). |
| 💫 Vega | 10 | ~95 | ~11% | → Stable recovery on frontend. #435-#437: sustained frontend recovery. #460: correct unanimous Approve with 1 unique (avatar_url format). #457: 0 unique (thinnest review). #447 R1: approved Ready when 5 criticals existed — backend/security under-detection persists. Frontend/API: good. Backend/security: unreliable. |

## Consensus Participation

| Reviewer | Part of 2/3+ consensus | Solo dissent (correct) | Solo dissent (noise) |
|----------|----------------------|----------------------|---------------------|
| 🌟 Stella | 87% | 23 (incl. stuck spinner #330 R3, guild_id #327 R5, toUser #348 R1, TimeoutError #352 R5, cross-channel-sidebar #356 R1, webhook-bypass #357 R4, migration-concern #357 R5, adapter-scope #418 R2, features-hardcode #437 R1) | 2 (#168 over-scope, #346 R3 over-scoped stale cache) + 1 likely FP (#357 R5 migration) |
| 🌠 Nova | 93% | 26 (incl. spinner jolt #330, Mark-as-Read #346, dispatch re-swallow #352 R3, THREAD_DELETE-dead-code #357 R2, PATCH-archive-permission #357 R3, THREAD_UPDATE-broadcast #357 R4, result-schema-mismatch #418 R1, dead-import #418 R2, name-validation-dupe+channel-type-magic+error-swallowing #437 R1) | 1 (#330 R5 over-cautious) |
| 💫 Vega | 73% | 13 (gen ID #190, 204 parsing #255, React 18 #330, OAuth COALESCE #348, owner_id NULL #357 R4, floating promise #367, mobile-responsiveness+cascade-comment #437 R1) | 15 (#261 R3, #290, #327 R5, #330 R2/R3, #331 R2, #348 R2, #352 R3-R4, #356 R1 under-detected, #357 R2 over-escalated, #357 R4 over-held, #369 R1 under-detected, #418 R1+R2 under-detected, **#447 R1 under-detected**) |

## Severity Calibration

| Reviewer | Verdict matches final | Over-flags | Under-flags |
|----------|----------------------|------------|-------------|
| 🌟 Stella | 82% | 14% | 4% |
| 🌠 Nova | 94% | 4% | 2% |
| 💫 Vega | 62% | 19% | 19% (#369 R1 ✅ Ready when ⚠️ Needs Changes was correct; #418 R1+R2 ✅ Ready when ⚠️ Needs Changes was correct; **#447 R1 ✅ Ready when ❌ Needs Changes was correct - missed 5 security criticals**) |

## False Positive Rate (Critical flagged → later proven non-issue)

| Reviewer | False Positives | Total Criticals | FP Rate |
|----------|----------------|-----------------|---------|
| 🌟 Stella | 1 (#168 WS scoping as blocker) + 1 likely (#357 R5 migration) | ~46 | 2-4% |
| 🌠 Nova | 2 (#400 R1 C1/C2 SDK type hallucinations) | ~55 | 4% |
| 💫 Vega | 4 (#168 R2, #290 pre-existing, #331 R2 arg parsing, #405 R2 C3 false critical) | ~44 | 9% |

## Reliability History

| Reviewer | Early (#96-#145) | Mid (#155-#264) | Recent (#278-#437) | Trend |
|----------|---------------------|-----------------|--------------------|----|
| 🌟 Stella | 12/12 (100%) | 95/97 (98%) | 113/117 (97%) | → Stable. #411-#437 R3: all clean. Large-diff sensitivity on >2000 lines. |
| 🌠 Nova | 12/12 (100%) | 97/97 (100%) | 116/119 (97%) | → Stable. #411-#437 R3: all clean. Nova R2 over-escalated suggestions mechanically (calibrated in consolidation). |
| 💫 Vega | 8/12 (67%) | 89/97 (92%) | 107/114 (94%) | → Stable output. #411-#437 R3: all clean. 22nd post-switch PR. |

## Vega Calibration Swing Pattern

**Recurring within single PRs - now confirmed across 3 PRs:**

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

**Key insight from #352:** Vega R3-R4 repeated the same over-escalation pattern - no self-correction between rounds until explicit calibration guidance was added in R5 prompt. When guided, Vega calibrates correctly (R5-R6). Without guidance, it over-escalates or under-detects.

### #356 (2 rounds)
| Round | Vega Verdict | Correct Verdict | Assessment |
|-------|-------------|-----------------|------------|
| R1 | ✅ Ready | ⚠️ Needs Changes | Over-lenient (missed cross-channel bug) |
| R2 | ✅ Ready | ✅ Ready | ✅ Correct |

**#356 note:** Same under-detection pattern as #330 R2/R3, #335 R1, #348 R2. Vega approved Ready while a real cross-channel corruption bug existed.

### #357 (5 rounds) - first PR with gemini-2.5-pro
| Round | Vega Verdict | Correct Verdict | Assessment |
|-------|-------------|-----------------|------------|
| R1 | ⚠️ Needs Changes | ⚠️ Needs Changes | ✅ Correct |
| R2 | ❌ Major Issues | ⚠️ Needs Changes | Over-strict (N+1 + nested threads) |
| R3 | ⚠️ Needs Changes | ⚠️ Needs Changes | ✅ Correct |
| R4 | ⚠️ Needs Changes | ✅ Ready | Over-held (owner_id NULL is follow-up tier) |
| R5 | ✅ Ready | ✅ Ready | ✅ Correct |

**#357 note:** First PR with gemini-2.5-pro. Reliability improved (5/5 output). Calibration: 3/5 correct, R2 over-escalated, R4 over-held. Pattern persists from gemini-3.1-pro but slightly better (R3 and R5 correct vs previous swings). Model change has marginally improved calibration but not enough.

### #369 (3 rounds) - 4th PR with gemini-2.5-pro
| Round | Vega Verdict | Correct Verdict | Assessment |
|-------|-------------|-----------------|------------|
| R1 | ✅ Ready | ⚠️ Needs Changes | Over-lenient (missed schema blocker) |
| R2 | ❌ Major Issues | ⚠️ Needs Changes | Over-strict (same escalation pattern) |
| R3 | ✅ Ready | ✅ Ready | ✅ Correct |

**#369 note:** Classic Vega swing: R1 under-detected (approved when real schema blocker existed), R2 over-corrected to ❌ Major, R3 correct. 4th PR with gemini-2.5-pro. Same calibration swing pattern as gemini-3.1-pro. 1/3 correct verdicts this PR.

### #405 (2 rounds) - 7th PR with gemini-2.5-pro
| Round | Vega Verdict | Correct Verdict | Assessment |
|-------|-------------|-----------------|------------|
| R1 | ⚠️ Needs Changes | ⚠️ Needs Changes | ✅ Correct (crashed first attempt, retry worked) |
| R2 | ⚠️ Needs Changes | ⚠️ Needs Changes | Partially correct - found C4 testing gap but raised false C3 |

**#405 note:** R1 crash (0 tokens, 2s) but retry produced valid output matching other reviewers. R2 raised false positive C3 (freshSend always deletes draft - guarded by `if(draftMessageId)`). Missed editQueue race (Stella+Nova consensus). 1/2 correct (R1 correct, R2 partially). Reliability: crash + retry is a concern.

### #418 (2 rounds) - 13th PR with gemini-2.5-pro
| Round | Vega Verdict | Correct Verdict | Assessment |
|-------|-------------|-----------------|------------|
| R1 | ✅ Ready | ⚠️ Needs Changes | Over-lenient (missed `media: true` capability lie - primary blocking issue) |
| R2 | ✅ Ready | ⚠️ Needs Changes | Over-lenient (missed `?.` silent no-op - same failure class as R1 C1) |

**#418 note:** Vega approved Ready BOTH rounds while real blocking issues existed. R1: missed the `media: true` capability contract violation (2/3 consensus blocker). R2: missed the `?.` silent no-op (Stella+Nova both caught it). This is the same under-detection pattern as #335 R1, #356 R1, #369 R1, #399 R1 - Vega consistently fails to catch contract/correctness issues on refactoring PRs. 0/2 correct verdicts this PR. Pattern now confirmed across 6+ PRs.

### #400 (2 rounds) - Vega best performance
| Round | Vega Verdict | Correct Verdict | Assessment |
|-------|-------------|-----------------|------------|
| R1 | ❌ Major Issues | ⚠️ Needs Changes | Over-strict (but C1/C2 hallucinations were shared by Nova too) |
| R2 | ✅ Ready | ✅ Ready | ✅ Correct - **only reviewer to verify SDK types** |

**#400 note:** Vega's best PR. R1: over-escalated to ❌ but the C1/C2 findings were shared hallucinations (Nova had them too). R2: Vega was the only reviewer to actually check SDK source code and correctly verify the author's dispute. Both Stella and Nova timed out on R2. Vega's strength: verification against source when guided to check. Weakness: still can't originate findings on complex diffs.

### #435 (2 rounds) - Vega performs well
| Round | Vega Verdict | Correct Verdict | Assessment |
|-------|-------------|-----------------|------------|
| R1 | ⚠️ Needs Changes | ⚠️ Needs Changes | ✅ Correct |
| R2 | ⚠️ Needs Changes | ⚠️ Needs Changes | ✅ Correct |

**#435 note:** Vega's best PR since #400. All verdicts correct across 4 rounds (ChannelPermissionsEditor overwrite flow gap, stale state after save, mouseenter/leave hover bug, move-up arrow at hierarchy ceiling). Notable: found an implementation UX issue (move-up arrow at hierarchy ceiling → 403) that neither Stella nor Nova caught. R3: approved Ready while Stella+Nova still had concerns (M2 gateway overwrite) but those were correctly downgraded to non-blocking suggestions by R4. First PR since #400 where Vega contributed genuinely novel finds rather than echoing consensus. Pattern: Vega performs better on frontend/UI code than backend/security reviews.

### #447 (2 rounds) - Vega under-detects security (again)
| Round | Vega Verdict | Correct Verdict | Assessment |
|-------|-------------|-----------------|------------|
| R1 | ✅ Ready | ❌ Needs Changes | Over-lenient (missed 5 criticals: auth bypass, token rotation attack, admin label, shell injection, no tests) |
| R2 | ✅ Ready | ✅ Ready | ✅ Correct |

**#447 note:** Vega approved Ready on R1 when 5 Critical security issues existed (no authorization on invite-agent, token rotation attack, "Server Admin" label mismatch, shell injection in agent name, zero tests). Same backend/security under-detection pattern as #369 R1, #399 R1, #418 R1+R2. On frontend PRs (#435, #437) Vega calibrates well; on security-sensitive endpoints, consistently misses blocking issues. 23rd PR with gemini-2.5-pro. R2 correctly approved after all fixes — Vega's R2 calibration is fine. The problem is R1 security detection.

## Review History

| PR | Repo | Date | Rounds | Final Verdict | Key Dimension |
|----|------|------|--------|---------------|---------------|
| #96 | cove | 2026-05-26 | R1-R3 | ✅ Ready | cors-preflight, route-ordering |
| #100 | cove | 2026-05-27 | R1 | ⚠️ Over-flagged | calibration - too conservative for context |
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
| #346 | cove | 2026-06-13 | R1-R3 | ✅ Ready | new-line-unreachable, null-read-cursor, O(N2)-render, mark-as-read-ack |
| #348 | cove | 2026-06-14 | R1-R4 | ✅ Ready | toUser-propagation, COALESCE-regression, CI-shell-injection |
| #352 | cove | 2026-06-14 | R1-R6 | ✅ Ready | bot-permission-bypass, dispatch-catch-reswallow, cove-md-timeout, UntrustedStructuredContext |
| #356 | cove | 2026-06-14 | R1-R2 | ✅ Ready | cross-channel-sidebar-corruption, unbounded-cache-lru |
| #357 | cove | 2026-06-15 | R1-R5 | ✅ Ready | thread-permission, archive-enforcement, guild-leak, message-count |
| #367 | cove | 2026-06-16 | R1 | ✅ Ready | per-channel-message-queue, FIFO-dispatch |
| #369 | cove | 2026-06-16 | R1-R3 | ✅ Ready | manifest-schema-validation, error-forwarding, multi-account-tests |
| #387 | cove | 2026-06-16 | R1-R2 | ⏹️ Closed (spec revision) | reply-to-validation, metadata-schema, test-coverage |
| #399 | cove | 2026-06-17 | R1-R3 | ⏹️ Closed (rewrite as #400) | dead-adapter-code, draft-streaming-removed, editQueue-race, tests-dont-test-changes, no-error-recovery |
| #400 | cove | 2026-06-18 | R1-R2 | ✅ Ready | SDK-type-hallucination, fallback-resendsFullText, delete-before-send, method-binding |
| #405 | cove | 2026-06-18 | R1-R2 | ✅ Ready (1 blocker deferred) | lost-chunking, double-delete-draft, post-seal-staleness, typing-keepalive |
| #408 | cove | 2026-06-18 | R1-R2 | ✅ Ready (2:1 split) | no-op-cancels-deploy-race, per-job-concurrency, atomic-publish-deferred | Merged 2026-06-18 |
| #409 | cove | 2026-06-19 | R1 | ✅ Ready (3/3 unanimous) | sdk-progress-compositor, editQueue-removal-safe, fallback-model-resilience | Merged 2026-06-19 |
| #410 | cove | 2026-06-20 | R1 | ✅ Ready (2/3) | durable-batch-chunking, draft-deletion-ordering, session-context-completeness | Merged 2026-06-21 |
| #411 | cove | 2026-06-22 | R1 | ✅ Ready (3/3) | dotfile-semantics, concurrency-coupling, tar-pipe-ci-fix | Merged 2026-06-22 |
| #413 | cove | 2026-06-22 | R1-R2 | ✅ Ready (3/3 R2) | github-output-injection, shell-injection-mitigation, random-delimiter | Merged 2026-06-22 |
| #417 | cove | 2026-06-22 | R1 | ✅ Ready (3/3) | typing-cleanup-finally-block, sdk-idempotency-verification | Merged 2026-06-22 |
| #418 | cove | 2026-06-22 | R1-R3 | ✅ Ready (3/3) | media-capability-lie, sendText-silent-noop, dead-import | Merged 2026-06-23T03:13Z |
| #423 | cove | 2026-06-23 | R1 | ✅ Ready (3/3 unanimous) | sdk-queue-adoption, attachment-defense, queue-depth-race | Merged 2026-06-23T08:55Z |
| #424 | cove | 2026-06-23 | R1 | ✅ Ready (Kagura quick review) | attachment-preservation-single-entry-flush | Merged 2026-06-23 |
| #429 | cove | 2026-06-24 | R1-R4 | ✅ Ready (3/3 R4) | CHANNEL_DELETE-race, thread-fetch-loop, ThreadPanel-fetch-loop, React-185-loop | Merged 2026-06-25 |
| #431 | cove | 2026-06-25 | R1 | ✅ Ready (3/3 unanimous) | ci-notify-approve, jq-secure-json, head-1-fix | Merged 2026-06-25 |
| #432 | cove | 2026-06-25 | R1-R2 | ✅ Ready (2/3) | bulk-position-privilege-escalation, dispatcher-fail-open, cross-guild-access | Merged 2026-06-25 |
| #435 | cove | 2026-06-25 | R1-R4 | ✅ Ready (3/3 R4 unanimous) | member-data-corruption, permission-bypass, gear-gate, zustand-selector-stability, TDZ-crash | Merged 2026-06-26. 4-round code review + 2-round spec review + 4 QA iterations. Most comprehensive single-PR coverage. |
| #437 | cove | 2026-06-29 | R1-R3 | ✅ Ready (3/3 R3 unanimous) | non-atomic-guild-create, guild-create-missing-channels-roles, icon-validation, double-navigation | 3-round review. R1: 2 criticals. R2: icon escalated. R3: all resolved. |
| #447 | cove | 2026-07-02 | R1-R2 | ✅ Ready (2/3) | invite-agent-auth, token-rotation-attack, shell-injection, fre-subscribe-race | R1: 5 criticals (auth, token takeover, admin label, shell injection, no tests). R2: All fixed. Vega under-detected R1 (Ready when 5 criticals). Merged 2026-07-03T07:27Z. |
| #450 | cove | 2026-07-07 | — | ✅ Human-only | hide-ConnectionBanner-when-connected | Small fix (47+57 lines). Human approved, no code review service run. |
| #453 | cove | 2026-07-07 | — | ✅ Human-only | webhook-guidance-GroupSystemPrompt | Small feature (64+2 lines). Human approved, no code review service run. |
| #457 | cove | 2026-07-09 | R1 | ✅ Ready (3/3 unanimous) | silent-reply-loss-diagnostics | Pure diagnostic logging. Consensus: dead second isAborted check, missing message.id in freshSend catch. Merged 2026-07-09T04:17Z. |
| #460 | cove | 2026-07-15 | R1 | ✅ Approve (3/3 unanimous) | cross-channel-messaging-api | 548+ lines. 5 consensus suggestions (embeds unused, O(n) rate limit, shared logic, internal webhook visibility, spec-reality drift). Stella: transaction atomicity, WebhookType export. Nova: thread_id validation, execute defense-in-depth. Vega: avatar_url format. All non-blocking. Awaiting human review. |

## Ground Truth Summary (77 merged + 2 closed-unmerged + 1 open PRs reviewed)

- **Human blind spots found by us:** 0 - human has never caught something we missed
- **Our blind spots:** 2 - #387 spec-misalignment (PR closed because design was revised mid-flight). #400: human caught spec artifact cleanup (.baseline, SPEC-398.md, SPEC-398-DELTAS.md) we all missed.
- **Human rubber-stamp rate:** 96% - human approved without findings in 77/78 merged cases. Exceptions: #174 (design questions), #281 (false positive), #400 (artifact cleanup)
- **Iterative review as quality gate:** In 77/78 merged PRs, our multi-round review was the actual quality gate (#424 was a Kagura-only quick review). #447: R1 caught 5 security criticals, all fixed by R2 — merged.
- **Over-flagging instances:** 3 (#100 verdict too conservative, #281 stale PR description, #400 R1 C1/C2 SDK type hallucinations)
- **Multi-round PRs:** 58/78 reviewed PRs went through 2+ rounds. Average rounds: 2.5. Max: 7 (#190).
- **Total review rounds:** ~214 across 83 PRs (80 merged + 2 closed-unmerged + 1 open)
- **False-ready detection:** 8 cases (#255 R4→R5, #330 R4 Vega swing, #348 R2 Vega, #369 R1 Vega, #399 R1 Vega, #418 R1 Vega, #418 R2 Vega, #447 R1 Vega) - self-correcting system working (Vega is 7 of 8)
- **Escalation protocol validated:** 8 cases - all led to fixes (#405 R2 chunking escalation led to #406 follow-up)
- **Closed-unmerged outcomes:** 2 (#387 spec revision, #399 rewritten as #400). Both were quality-driven closures where our review findings shaped the rewrite.
- **SDK type hallucination pattern.** #400 R1 had 2 false positives where Nova+Vega inferred SDK types from naming conventions instead of verifying against source. First systematic hallucination failure across all reviewers.
- **Fallback model resilience.** #409: all 3 primary models (gpt-5.5, claude-opus-4.7, gemini-3.1-pro-preview) failed due to network issues. Fallback models (gpt-4.1, claude-sonnet-4, gemini-2.5-pro) produced high-quality unanimous Ready verdict. System resilience validated.
- **#413 security review value.** Caught real GITHUB_OUTPUT injection via static EOF delimiter - a security fix PR itself had a security gap. Validates our review even on security-hardening PRs.
- **#432 permission system review.** R1 caught real privilege escalation (bulk position update), dispatcher fail-open, and cross-guild access - all security-critical. R2 confirmed all 5 fixes. Also had 4 prior spec review rounds that caught 3 blockers + 5 majors per round. Total spec+code review: 6 rounds. Human approved without comments.
- **#435 most comprehensive coverage.** 2-round spec review + 4-round code review + 4 QA iterations (React #185, TDZ crash, permission gate chicken-and-egg, final pass). Caught GUILD_MEMBER_UPDATE data corruption, hardcoded permission bypass, zustand selector instability, variable ordering TDZ, and roles-not-in-READY chicken-and-egg. All fixed iteratively. First PR with integrated QA loop feeding back into code review.

## Actionable Notes

1. **🟡 Vega: gemini-2.5-pro evaluation — 18 PRs complete.** #357-#447. Results: reliability improved (overall 92%), **calibration still PR-dependent**. #399 gave ✅ Ready with 0 findings (5 criticals existed). #400 was Vega's best PR ever. #418: **missed blocking issues BOTH rounds**. **#435: strong comeback** — 4 unique finds, correct verdicts all 4 rounds, first PR since #400 where Vega outperformed expectations. **#447: approved Ready R1 when 5 security criticals existed** — same pattern as #369, #399, #418. Emerging pattern confirmed: Vega calibrates well on **frontend/UI code** but **unreliable on backend/security reviews**. Consider: (a) weight Vega lower on security PRs (treat as tie-break only, not full vote), (b) maintain explicit security-focus prompt for backend reviews, (c) #435+#437 confirm Vega's frontend value — strong on React/zustand/CSS.

2. **🟠 NEW: SDK type hallucination failure mode.** #400 R1 had Nova+Vega both hallucinate SDK type names from naming conventions and PR spec examples. Neither checked actual SDK source. **Prompt action needed:** Add instruction to verify SDK/library types against actual source, not spec examples or naming inference. First systematic cross-reviewer hallucination.

3. **🟠 Large-diff timeout pattern confirmed.** Both Stella (GPT-5.5) and Nova (Claude Opus 4.7) timed out on #400 (2300 lines). Nova: 3 timeouts total, all on large/complex PRs. Stella: 6 total failures, recent ones on large diffs. **Options:** (a) increase timeout for PRs >1500 lines, (b) split large diffs across reviewers by file, (c) require reviewers to write partial results early.

4. **#281 stale-description pattern still unaddressed in prompts.** Need to add: "Verify understanding of feature matches actual code, not just PR description." Low priority since it hasn't recurred.

5. **Nova FP record broken.** #400 R1 C1/C2 were Nova's first false positives (hallucinated SDK types). Still best-calibrated overall (4% FP rate vs Vega 10%), but the zero-FP streak is over. Continue using Nova as tiebreaker, but the hallucination pattern needs a prompt fix.

6. **Stella: large-diff sensitivity.** Timed out on #400 R1 (2300 lines). Produced a late R1 review with valid ChannelId finding. Stable on normal-sized PRs (#405: 2/2 clean). GPT-5.5 may need longer timeout or diff-splitting for PRs >2000 lines.

7. **Throughput sustained.** 87 PRs tracked (80 reviewed+merged + 2 closed + 4 human-only merged + 1 open), ~214 review rounds, 52 days. ~1.6 PRs/day, ~4.1 rounds/day. Velocity slowed (fewer PRs last 2 weeks; project entering maintenance phase). #460 is first new feature PR in 6 days.

8. **Ground truth: human rubber-stamps 96% (of reviewed+merged PRs).** Our iterative review IS the quality gate. #457: small diagnostic PR, 3/3 unanimous Ready, human approved without comments. #447 merged: R1 caught 5 security criticals (auth bypass, token rotation, shell injection, admin label, no tests), all fixed by R2. #400 broke the pattern - human caught spec artifact cleanup we missed (first non-trivial human finding since #174). Two closed-unmerged PRs (#387 spec revision, #399 rewrite). #413: EOF injection catch on a security-fix PR validates depth even on hardening PRs. #424 was a Kagura-only quick review (3-line follow-up from #423 Nova finding). #429: 4-round architecture review (URL routing) with all rounds catching real issues. #431: clean CI review. #432: security-focused permission system review - first PR with both spec review (4 rounds) and code review (2 rounds) in the same PR. #435: **most comprehensive per-PR coverage** - spec review (2 rounds) + code review (4 rounds) + QA testing (4 iterations finding React #185, TDZ, permission gate, and final pass). First integrated spec→code→QA pipeline on a single PR. #437: clean 3-round multi-server feature review with 3/3 consensus on both R1 criticals.

9. **Nova still leads unique find rate.** 23% unique find rate vs Stella 15% vs Vega 12% (window #409-#460). Nova finds ~1.5× more unique issues per PR. #460 R1: Nova found thread_id-validation + execute-defense-in-depth (2 unique), Stella found transaction-atomicity + WebhookType-export (2 unique), Vega found avatar_url-format (1 unique). All 3 contributed this round.

10. **Multi-round PR pattern emerging.** Complex feature PRs consistently need 4+ rounds. Reviewer fatigue may affect Vega most.

11. **Prompt evolved: added "Config & Schema Consistency" dimension (#8).** Triggered by #369 - Vega's miss of the manifest schema gap. This dimension was implicit before; now explicit. Should help all reviewers but especially Vega on plugin/config PRs.

12. **#387 closed-unmerged - spec-revision blind spot (low priority).** First occurrence. Not adding a "design questioning" dimension. If recurrence climbs above ~5%, reconsider.

13. **#399 closed-unmerged - rewritten as #400.** Our R1-R3 findings (dead adapter, editQueue race, hollow tests) directly shaped the rewrite. Validates the review process even on ultimately-discarded PRs.

14. **#400 R1 hallucination post-mortem.** Both Nova and Vega inferred SDK type names from the PR's own spec examples rather than checking actual SDK source code. The spec said `sendText` as a dep key but the actual SDK uses channel ID. **Root cause:** reviewers trust PR-provided context over primary sources when the spec looks authoritative. **Fix needed:** prompt addition requiring SDK/library type verification against actual source.

15. **#405 merged with known blocker (chunking deferred to #406).** Author justified: SDK `sendDurableMessageBatch` callback doesn't fire (verified on staging). Our review correctly held on the blocker; author made informed decision to defer. This is the review process working as intended - blocker identified, trade-off made explicitly, follow-up tracked.

16. **#435 established integrated spec→code→QA pipeline.** First PR with all three review modes: 2-round spec review (caught 2 blockers + 5 majors), 4-round code review (caught data corruption + permission bypass + zustand instability + TDZ), 4 QA iterations (browser-level testing found render loops and chicken-and-egg bug). Total quality assurance effort: 10 review/QA rounds. This level of coverage is warranted for feature PRs touching auth/permissions. Consider making this the standard for future auth/security feature PRs.
