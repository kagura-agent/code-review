# Code Review Service — Reviewer Stats

_Last updated: 2026-06-14 08:32 (Asia/Shanghai)_

## Per-Reviewer Performance

| Reviewer | Model | Total Review Rounds | Reliability | Trend |
|----------|-------|---------------------|-------------|-------|
| 🌟 Stella | gpt-5.5 | 171 | 167/171 (98%) → | Stable — 4 historical failures (#176 R1 timeout, #190 R5 late, #255 R2 miss, #278 R5 timeout). Last 80+ rounds: clean |
| 🌠 Nova | claude-opus-4.7 | 175 | 175/175 (100%) → | Rock solid. No failures ever |
| 💫 Vega | gemini-3.1-pro-preview | 171 | 160/171 (94%) ↓ | 11 failures total + 1 retry-needed (#348 R1). Recent: #294 R1 crash, #294 R4 timeout, #294 R5 stale, #316 R5 timeout, #322 R1 timeout, #337 R2 no output, #348 R1 retry. **7 issues in last 21 PRs — accelerating decline** |

## Dimension Strengths (per reviewer)

### 🌟 Stella (GPT-5.5)
| Dimension | Strength | Evidence |
|-----------|----------|----------|
| DB/Migration | ⭐⭐⭐ | SQLite ALTER TABLE (#168), migration ordering (#144), FK pragma-in-transaction (#178 R1 — reproduced locally), FK safety (#174), migration seq overflow (#202 R1) |
| Build Verification | ⭐⭐⭐ | Only reviewer who runs `pnpm -r build` — caught tsc failure (#165 R1), verified tests every round. #255: verified 152 server + 38 plugin tests. #261: verified server + client build |
| Security (Auth) | ⭐⭐⭐ | Ghost presence (#167), presences membership (#168), stale guildIds (#179 R1), snowflake-as-auth-token (#202 R1), user deletion stale sessions (#179 R3) |
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
| State Lifecycle | ⭐⭐⭐ | prepend-triggers-scroll interaction (#330 R1), stuck spinner on channel switch (#330 R3), guild scoping leak in mentions (#337 R1), edit path missing resolveMentions (#337 R1) |
| Test Requirements | ⭐⭐⭐ | Most persistent on negative auth tests (#316 R4), delete confirmation (#331 R1), retry loses reply (#335 R1) |
| Edge Case Reasoning | ⭐⭐ | **NEW: Stale cached messages freeze unread computation (#346 R3 — valid but over-scoped), banner dismissal + suppressed scroll events (#346 R2), server-side auth scope analysis (#343 R1)** |

**Stella's superpower:** Runs actual builds + reproduces bugs locally. Catches things pure code reading misses. Deepest lifecycle analysis. Most persistent on escalation rules. Cross-module verification. State lifecycle reasoning.
**Stella's weakness:** Sometimes over-scopes (flags out-of-PR architectural concerns as blocking). Occasionally over-strict on severity — #343 blocked on pre-existing #113, #346 R3 blocked on stale cache edge case.

### 🌠 Nova (Claude Opus 4.7)
| Dimension | Strength | Evidence |
|-----------|----------|----------|
| API Design | ⭐⭐⭐ | Breaking changes (#175), API compatibility, positional arg drift (#168), topic nullability (#174) |
| Security | ⭐⭐⭐ | IDOR (#168 R3), cross-guild leak (#143), typing indicator leak (#190 R1), snowflake-as-auth-token (#202 R1) |
| Architecture | ⭐⭐⭐ | Timer leak (#176 R2), event model verification (#176 R1), self-broadcast lifecycle (#179 R2), READY payload growth (#192 R1) |
| Async/Concurrency | ⭐⭐⭐ | Queued side-effect race trace (#190 R5), handler ordering (#190 R6), ack cursor monotonicity race (#192 R2) |
| Severity Calibration | ⭐⭐⭐ | Most accurately calibrates critical vs suggestion. Rarely over-flags. Best tiebreaker when others disagree |
| Accessibility/A11y | ⭐⭐⭐ | WCAG 2.4.7 (#191 R2), aria-label (#191 R1), matchMedia mobile detection (#191 R2) |
| Auth Route Analysis | ⭐⭐⭐ | PUBLIC_PATHS signup break (#248 R1), resolveUser duplication (#248 R2-R3) |
| Retry/Idempotency | ⭐⭐⭐ | Retry-After NaN (#255 R1), POST retry duplicates (#255 R2), sendTyping budget (#255 R2) |
| Session TTL/Auth | ⭐⭐⭐ | Non-sliding session design flaw (#264 R2), bot footgun (#264 R4), backfill hardcode (#264 R4) |
| Security Model Design | ⭐⭐⭐ | Token exfiltration (#294 R1 — unique), webhook permission model (#294 R1), READY payload leak (#316 R2), CHANNEL_CREATE unreachable (#316 R3) |
| UX-Level Analysis | ⭐⭐⭐ | spinner scroll jolt (#330 R2 — unique), pendingPrependRestoreRef leak (#330 R3 — unique), token redaction (#331 R1), reply state cleanup (#335 R1), mention count cap (#337 R1), self-mention highlight (#339 R1), mentionMapRef channel-switch (#339 R1), 8 unique UX/arch findings (#343 R1) |
| Feature Correctness | ⭐⭐⭐ | **NEW: "Mark as Read" doesn't actually ack (#346 R1 — unique critical), unread count lies (#346 R2 — unique), pill positioning (#346 R1-R2 — escalated), "+" suffix disappears (#346 R3 — unique low-pri). Most thorough per-round analysis across all 3 rounds.** |

**Nova's superpower:** Best calibration. Most suggestions per review, almost all actionable. Zero false positives across 175 rounds. Strongest on API compatibility, security model design, async lifecycle, UX-level analysis, and feature correctness. #343 (8 unique findings) and #346 (6 unique findings across 3 rounds) confirm continued breadth.
**Nova's weakness:** None significant. Very occasionally over-cautious (e.g. #330 R5 — ⚠️ when .finally() guarantees re-render).

### 💫 Vega (Gemini 3.1 Pro)
| Dimension | Strength | Evidence |
|-----------|----------|----------|
| Security (Code-level) | ⭐⭐⭐ | Prototype pollution (#176 R1, unique), IDOR framing (#168 R3, clearest) |
| Async/Concurrency | ⭐⭐⭐ | Generation ID reuse via .delete() (#190 R4 — star find of entire review history) |
| Product Impact | ⭐⭐⭐ | O(N²) presence (#179 R2), own-message-causes-unread (#192 R2 — star find) |
| Input Sanitization/DoS | ⭐⭐⭐ | parseCookies URIError DoS (#248 R1), localStorage XSS remnant (#248 R2) |
| Runtime Error Detection | ⭐⭐⭐ | 204 JSON parsing retry storm (#255 R2 — star find) |
| Session TTL Edge Cases | ⭐⭐⭐ | Sliding threshold math bug (#264 R3 — unique), stale expires_at (#264 R5) |
| Framework-Level Analysis | ⭐⭐ | React 18 batching breaks scroll-restore (#330 R1 — star quality find with concrete flushSync fix) |
| Performance Regression | ⭐⭐ | **NEW: O(N²) render regression (#346 R2 — all 3 found it, but Vega escalated to ❌ Major Issues). Batch message pill counter (#346 R1 — unique). No-scrollbar edge case (#346 R2 — unique)** |

**Vega's superpower:** Fast (~1m avg). Capable of star-quality finds when the bug is deterministic/logical (gen ID reuse #190, 204 JSON parsing #255, React 18 batching #330). Cleanest fix suggestions.
**Vega's weakness:** ⚠️ **Calibration deteriorating significantly.** Three distinct failure patterns emerging:
1. **Over-lenient** — approves Ready when real bugs exist: #330 R2 (missed spinner jolt + firstMessageIdRef), #330 R3 (missed stuck spinner), #335 R1 (missed lifecycle issues — deleted ref visibility, retry loses reply)
2. **Over-strict** — escalates to ❌ when ⚠️ is appropriate: #330 R4, #331 R2 (arg parsing to Critical), #346 R2 (❌ Major when ⚠️ was correct — issue was real but severity overstated)
3. **Under-verification** — doesn't check whether fixes actually work: #327 R5 (Ready when bridge non-functional), #261 R3 (premature Ready)

## Unique Find Rate (last 10 PRs: #322 through #346)

| Reviewer | Unique Finds | Total Issues Found | Unique Rate | Trend |
|----------|-------------|-------------------|-------------|-------|
| 🌟 Stella | 15 | ~125 | ~12% | → Stable (guild_id #327, stuck spinner #330, retry-loses-reply #335, guild scoping #337, stale cache #346, toUser() propagation #348) |
| 🌠 Nova | 24 | ~125 | ~19% | ↑↑ Strengthening (spinner jolt #330, token redaction #331, reply cleanup #335, 4 unique #339, 8 unique #343, Mark-as-Read ack + unread-count-lies + "+" suffix #346) |
| 💫 Vega | 6 | ~125 | ~5% | ↓↓ Declining sharply (React 18 #330, dangling-autocomplete #339, batch pill counter #346, no-scrollbar #346, OAuth COALESCE #348). **Below 10% threshold for 8+ consecutive periods** |

## Consensus Participation

| Reviewer | Part of 2/3+ consensus | Solo dissent (correct) | Solo dissent (noise) |
|----------|----------------------|----------------------|---------------------|
| 🌟 Stella | 87% | 16 (incl. stuck spinner #330 R3, guild_id #327 R5, retry-loses-reply #335 R1, guild scoping #337 R1, webhook-mention #339 R1, stale cache #346 R3) | 2 (#168 over-scope, #346 R3 over-scoped stale cache) |
| 🌠 Nova | 93% | 17 (incl. spinner jolt #330 R2, pendingPrependRestore #330 R3, reply cleanup #335 R1, 4 unique #339, Mark-as-Read ack #346 R1, unread count lies #346 R2) | 1 (#330 R5 over-cautious on .finally()) |
| 💫 Vega | 80% | 10 (gen ID #190, own-message #192, 204 parsing #255, sliding math #264, React 18 #330, dangling-autocomplete #339 R1, batch pill #346 R1, no-scrollbar #346 R2, OAuth COALESCE #348 R1) | 5 (#261 R3 premature Ready, #290 over-flagged, #327 R5 under-flag, #330 R2/R3 over-lenient, #331 R2 over-escalated) |

## Severity Calibration

| Reviewer | Verdict matches final | Over-flags | Under-flags |
|----------|----------------------|------------|-------------|
| 🌟 Stella | 82% | 14% (incl. #339 R2 over-scoped MESSAGE_UPDATE, #346 R3 stale cache) | 4% |
| 🌠 Nova | 94% | 4% | 2% |
| 💫 Vega | 72% ↓ | 15% (#290, #191, #330 R4, #331 R2, #346 R2 ❌ over-escalated) | 13% (#261 R3, #327 R5, #330 R2/R3, #335 R1) |

## False Positive Rate (Critical flagged → later proven non-issue)

| Reviewer | False Positives | Total Criticals | FP Rate |
|----------|----------------|-----------------|---------|
| 🌟 Stella | 1 (#168 WS scoping as blocker) | ~40 | 3% |
| 🌠 Nova | 0 | ~44 | 0% |
| 💫 Vega | 3 (#168 R2 oversized, #290 pre-existing, #331 R2 arg parsing) | ~32 | 9% |

## Reliability History

| Reviewer | Early (#96-#145) | Mid (#155-#264) | Recent (#278-#346) | Trend |
|----------|---------------------|-----------------|--------------------|----|
| 🌟 Stella | 12/12 (100%) | 95/97 (98%) | 60/62 (97%) | → Stable |
| 🌠 Nova | 12/12 (100%) | 97/97 (100%) | 66/66 (100%) | → Rock solid |
| 💫 Vega | 8/12 (67%) | 89/97 (92%) | 63/62 (87%) | ↓ Recent: crash #278 R4, crash #294 R1, timeout #294 R4, stale #294 R5, timeout #316 R5, timeout #322 R1, failed #337 R2, retry #348 R1. 8 issues in 62 recent rounds (87%) |

## Vega Calibration Swing Pattern

**#330 demonstrates a failure mode: calibration swings within a single PR.**

| Round | Vega Verdict | Correct Verdict | Assessment |
|-------|-------------|-----------------|------------|
| R2 | ✅ Ready | ⚠️ Needs Changes | Over-lenient (missed spinner jolt + firstMessageIdRef) |
| R3 | ✅ Ready | ⚠️ Needs Changes | Over-lenient (missed stuck spinner) |
| R4 | ❌ Major Issues | ⚠️ Needs Changes | Over-strict (escalated all to Major) |
| R5 | ✅ Ready | ✅ Ready | Correct (best analysis of the round) |

**#346 shows the same pattern at PR level:** R2 escalated to ❌ Major Issues (all 3 found O(N²) but Vega was the only one to go ❌). Pattern: Vega either under-detects or over-escalates, rarely in the calibrated middle.

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
| **#348** | **cove** | **2026-06-14** | **R1 (open)** | **⚠️ Needs Changes** | **toUser-drops-global_name, empty-string-normalization, control-char-validation, OAuth-COALESCE** |

## Ground Truth Summary (54 merged PRs)

- **Human blind spots found by us:** 0 — human has never caught something we missed
- **Our blind spots:** 0 — human has never flagged something all 3 reviewers missed
- **Human rubber-stamp rate:** 96% — human approved without findings in 52/54 cases. Exceptions: #174 (design questions), #281 (false positive)
- **Iterative review as quality gate:** In 52/54 merged PRs, our multi-round review was the actual quality gate
- **Over-flagging instances:** 2 (#100 verdict too conservative, #281 stale PR description)
- **Multi-round PRs:** 43/54 merged PRs went through 2+ rounds. Average rounds: 2.7. Max: 7 (#190). #348 open after R1, fix commits pushed
- **Total review rounds:** ~187 across 54 merged PRs + 1 open (#348)
- **False-ready detection:** 2 cases (#255 R4→R5, #330 R4 Vega swing) — self-correcting system working
- **Escalation protocol validated:** 6 cases — all led to fixes

## Actionable Notes

1. **🔴 Vega: decision point reached.** Unique find rate **4%** (below 10% threshold for 7+ periods). Reliability **89% recent** (7 failures in 61 rounds). Calibration **72%** with near-equal over-flag and under-flag rates. False positive rate **9%**. The combination of declining unique finds, declining reliability, and erratic calibration swings makes Vega the weakest link. **Recommendation:** Try `gemini-2.5-pro` as replacement. Vega still produces occasional star finds (React 18 batching #330, sliding math #264) but the signal-to-noise ratio is degrading.

2. **Vega prompt tuning (if keeping):** Two specific additions could help:
   - "Before approving Ready, verify the fix is functional by checking the data flow end-to-end, not just that code was added."
   - "Anchor severity to previous rounds — if R(n-1) had Critical issues, R(n) Ready requires explicit evidence each was resolved."
   
3. **#281 stale-description pattern still unaddressed in prompts.** Need to add: "Verify understanding of feature matches actual code, not just PR description."

4. **Nova continues zero false positives across 175 rounds.** Best-calibrated reviewer. Continue using Nova's verdict as tiebreaker.

5. **Stella's edge-case reasoning sometimes over-scopes.** #343 (pre-existing auth) and #346 R3 (stale cache) were valid analysis but wrong to block on. Consider prompt guidance: "Pre-existing issues tracked in separate issues are not blockers for the current PR."

6. **Throughput sustained.** 54 merged PRs, ~186 review rounds. Service scaling well. Average 2.7 rounds per PR.

7. **Ground truth: human rubber-stamps 96%.** Our iterative review IS the quality gate. This validates the service but means limited external validation of our work.

8. **Nova widening gap.** 20% unique find rate vs Stella 12% vs Vega 4%. Nova is the most thorough reviewer by a significant and growing margin. #346 further confirmed: 6 unique findings across 3 rounds including the critical "Mark as Read doesn't ack" catch.
