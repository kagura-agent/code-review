# Code Review Service — Reviewer Stats

_Last updated: 2026-06-11 08:26 (Asia/Shanghai)_

## Per-Reviewer Performance

| Reviewer | Model | Total Review Rounds | Reliability | Trend |
|----------|-------|---------------------|-------------|-------|
| 🌟 Stella | gpt-5.5 | 126 | 122/126 (97%) → | Stable — 1 timeout (#176 R1), 1 late (#190 R5), 1 miss (#255 R2), 1 timeout (#278 R5). Last 60+ rounds ex-R2: 1 timeout |
| 🌠 Nova | claude-opus-4.7 | 130 | 130/130 (100%) → | Rock solid. No failures ever |
| 💫 Vega | gemini-3.1-pro-preview | 126 | 120/126 (95%) → | 1 crash (#278 R4), 1 crash (#294 R1 — review saved). Stable overall |

## Dimension Strengths (per reviewer)

### 🌟 Stella (GPT-5.5)
| Dimension | Strength | Evidence |
|-----------|----------|----------|
| DB/Migration | ⭐⭐⭐ | SQLite ALTER TABLE (#168), migration ordering (#144), FK pragma-in-transaction (#178 R1 — reproduced locally), FK safety (#174), migration seq overflow (#202 R1) |
| Build Verification | ⭐⭐⭐ | Only reviewer who runs `pnpm -r build` — caught tsc failure (#165 R1), verified tests every round. #255: verified 152 server + 38 plugin tests. #261: verified server + client build |
| Security (Auth) | ⭐⭐⭐ | Ghost presence (#167), presences membership (#168), stale guildIds (#179 R1 — rated ❌), snowflake-as-auth-token (#202 R1), user deletion stale sessions (#179 R3) |
| Async/Concurrency | ⭐⭐ | Async handler ordering race (#190 R5 — unique star find), queued side-effect race analysis (#190 R4), auto-ack race on channel switch (#192 R1) |
| Testing Gaps | ⭐⭐⭐ | Ack endpoint test coverage (#192 R1), fake test detection (#178 R2), product-impact of .catch swallowing (#192 R1) |
| Architecture | ⭐ | WS guild scoping (#168 R5-R6) — valid but sometimes over-scopes beyond PR |
| Accessibility/A11y | ⭐⭐ | Focus ring WCAG violation (#191 R2), high-contrast mode note (#191 R3), send button aria-label (#191 R3) |
| Lifecycle Analysis | ⭐⭐⭐ | Auto-ack dedup across mounts (#192 R3-R4), reload dedup gap (#192 R4), same-ms monotonicity (#192 R4) |
| Auth/Cookie Security | ⭐⭐⭐ | pendingToken leaked to JS (#248 R1), NODE_ENV cookie Secure flag (#248 R2-R3), logout doesn't close WS (#248 R3), local dev NODE_ENV (#248 R3) |
| Protocol/Gateway | ⭐⭐⭐ | **RESUMED aborts dispatches** (#255 R1 — unique insight: RESUME should NOT trigger dispatch abort), `resumed` vs `reconnect` event distinction, channel refetch lifecycle. **WS fallback gap** (#261 R1 — WS disconnect → sidebar loading forever). **WS session outlives expired token** (#264 R5 — unique: gateway never rechecks after IDENTIFY) |
| Control Flow Analysis | ⭐⭐⭐ | **try/catch control flow bug** (#255 R5 — caught that R4's "fix" was non-functional: POST still retried due to throw inside try). New dimension. |
| Session/Auth Lifecycle | ⭐⭐⭐ | **Cookie reissue gap** (#264 R3 — sliding refresh updates DB but browser cookie keeps old maxAge), **OAuth non-atomic** (#264 R4 — two UPDATEs can leave stale expires_at on crash). Persistent escalation across 5 rounds. |
| React Hooks Hygiene | ⭐⭐⭐ | **Ref mutation during render** (#278 R2 — unique find, verified by eslint), **scrollContainerRef.current read during render** (#278 R4 — unique find from shared observer refactor). Caught same lint class twice in one PR. |
| Config/Resolver Design | ⭐⭐ | **`resolveAccount` throws on missing agentId** (#287 R1 — unique Critical, not needed for target resolution), transaction gap in webhook execute (#294 R1), rate limiter pre-auth DoS (#294 R2). |

**Stella's superpower:** Runs actual builds + reproduces bugs locally. Catches things that pure code reading misses. Deepest lifecycle analysis. Most persistent on escalation rules. Protocol-level reasoning. Control flow verification. Session lifecycle depth. React hooks hygiene.
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
| Accessibility/A11y | ⭐⭐⭐ | WCAG 2.4.7 citation (#191 R2), aria-label (#191 R1), useLayoutEffect correctness (#191 R2), matchMedia mobile detection (#191 R2), retry/dismiss keyboard a11y (#261 R3) |
| Code Hygiene | ⭐⭐ | Dead code detection (getAllForUser #192 R2, ReadStateRow alias #192 R2), test mock accuracy (#192 R4) |
| Auth Route Analysis | ⭐⭐⭐ | PUBLIC_PATHS signup break (#248 R1 — unique find), resolveUser duplication escalation (#248 R2-R3), cookie attribute assertions (#248 R3), CORS credentials concern (#248 R3) |
| Retry/Idempotency | ⭐⭐⭐ | Retry-After NaN/unbounded (#255 R1), POST retry duplicates messages (#255 R2), sendTyping retry budget (#255 R2), INVALID_SESSION socket guard (#255 R1). #255 R5: independently confirmed try/catch control flow bug. |
| Optimistic UI | ⭐⭐⭐ | **WS-only reconcile gap** (#261 R2 — REST reconciliation path), **empty guilds READY crash** (#261 R3 — unique find), nonce validation ordering (#261 R3), sidebar loading state diagnosis (#261 R2). Core contributor to #261's 4-round resolution. |
| Session TTL/Auth | ⭐⭐⭐ | **Non-sliding session design flaw** (#264 R2 — fixed-window expiry without user activity renewal), **bot footgun** (#264 R4 — `opts.bot !== false` makes undefined=bot), **backfill hardcode** (#264 R4 — migration ignores SESSION_TTL_MS). Best calibration in #264: first to approve in R3 and R5. |
| Security Model Design | ⭐⭐⭐ | **Token exfiltration** (#294 R1 — unique Critical: list/get endpoints return raw token to any guild member, breaking URL-token security model), **webhook permission model** (#294 R1 — unique: no permission check beyond guild membership). Strongest at identifying systemic security model flaws, not just code-level bugs. |

**Nova's superpower:** Best calibration. Most suggestions per review, almost all actionable. Strongest on API compatibility, security, accessibility, async lifecycle, retry semantics, session/auth design, and security model design. Zero false positives across 130 rounds. **#294 standout** — unique token exfiltration find that neither Stella nor Vega caught.
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
| Runtime Error Detection | ⭐⭐⭐ | **204 JSON parsing retry storm** (#255 R2 — star find). `requestVoid` delegates to `request<T>()` which unconditionally calls `res.json()` on 204 No Content → SyntaxError → retry storm. Concrete, testable, would crash production. |
| Rate Limiting | ⭐⭐ | **Token bucket math errors** (#261 R1), retry_after calculation issues. First reviewer to flag R1 in #261. Ready verdict in R3 when others still had blockers — isolated incident, returned correct in R4. |
| Performance Optimization | ⭐⭐ | **broadcastToGuilds loop** (#263 R1 — joint with Nova), O(1) session lookup verification |
| Session TTL Edge Cases | ⭐⭐⭐ | **Sliding threshold math bug** (#264 R3 — unique find: `TTL - 24h` goes negative for short TTLs → sliding silently fails), **stale expires_at return** (#264 R5 — in-memory value not updated after DB refresh), **cookie maxAge escalation** (#264 R2 — elevated to Major). Strong on config-math edge cases. |
| Scroll/DOM Architecture | ⭐⭐ | **Scroll listener not attached on first visit** (#278 R1 — unique find: useEffect deps missed container mount). Strong first-principles DOM lifecycle analysis. |

**Vega's superpower:** Fast (~1m avg). Capable of star-quality finds when the bug is deterministic/logical (gen ID reuse #190, own-message-unread #192, 204 JSON parsing #255, sliding threshold math #264). Cleanest fix suggestions. Excellent edge-case tenacity (deleted-message tracked across 3 rounds). Strong on input sanitization/DoS vectors and config-math edge cases.
**Vega's weakness:** Fewer unique finds overall. Sometimes over-escalates severity (#191 R2 — ❌ Major for all 3 issues). Premature Ready in #261 R3. **New: over-flagged pre-existing behavior as regression in #290** (abort signal pattern was pre-existing, not introduced by the PR). May misjudge "regression vs pre-existing" when behavior is unchanged.

## Unique Find Rate (last 10 PRs: #264 through #294)

| Reviewer | Unique Finds | Total Issues Found | Unique Rate | Trend |
|----------|-------------|-------------------|-------------|-------|
| 🌟 Stella | 14 | ~120 | ~12% | → Stable |
| 🌠 Nova | 19 | ~120 | ~16% | ↑ Improving (token exfil #294, empty guilds #261) |
| 💫 Vega | 11 | ~120 | ~9% | ↓ Slightly declining |

**Notable unique finds (last 10 PRs: #264-#294):**
- Stella: **cookie reissue gap** (#264 R3), **WS session outlives expired token** (#264 R5), **ref mutation during render** (#278 R2+R4), **resolveAccount agentId throw** (#287 R1), rate limiter pre-auth DoS (#294 R2)
- Nova: **non-sliding session flaw** (#264 R2), **bot footgun** (#264 R4), **backfill hardcode** (#264 R4), **token exfiltration** (#294 R1 — security model, not just code), **webhook permission model missing** (#294 R1), getChannels error (#287 R1)
- Vega: **sliding threshold math bug** (#264 R3), **stale expires_at return** (#264 R5), **scroll listener not attached** (#278 R1), FK violation surface (#294 R1)

## Consensus Participation

| Reviewer | Part of 2/3+ consensus | Solo dissent (correct) | Solo dissent (noise) |
|----------|----------------------|----------------------|---------------------|
| 🌟 Stella | 86% | 10 (WS scoping, presences, build-order, WS disconnect #176 R3, auto-ack dedup #192 R4, RESUMED abort semantics #255 R1, dispatch.ts fallback paths #255 R3, **try/catch control flow #255 R5**, **WS session lifetime #264 R5**, rate limiter DoS #294 R2) | 1 (WS scoping over-scope #168) |
| 🌠 Nova | 93% | 6 (ready when others flag, PUBLIC_PATHS #248 R1, POST retry idempotency #255 R2, **empty guilds READY #261 R3**, **non-sliding session #264 R2**, **token exfiltration #294 R1**) | 0 |
| 💫 Vega | 84% | 7 (#125 R1, gen ID reuse #190 R4, own-message-unread #192 R2, parseCookies DoS #248 R1, localStorage XSS #248 R2, 204 JSON parsing #255 R2, **sliding threshold math #264 R3**) | 2 (#261 R3 premature Ready; **#290 over-flagged pre-existing as regression**) |

## Severity Calibration

| Reviewer | Verdict matches final | Over-flags | Under-flags |
|----------|----------------------|------------|-------------|
| 🌟 Stella | 80% | 15% (WS scoping, build-order, same-ms monotonicity) | 5% |
| 🌠 Nova | 95% | 3% | 2% |
| 💫 Vega | 81% | 12% (#290 pre-existing flagged, #191 over-severity) | 7% (#261 R3 premature Ready) |

## False Positive Rate (Critical flagged → later proven non-issue)

| Reviewer | False Positives | Total Criticals | FP Rate |
|----------|----------------|-----------------|---------|
| 🌟 Stella | 1 (WS scoping as blocker for #168) | ~32 | 3% |
| 🌠 Nova | 0 | ~32 | 0% |
| 💫 Vega | 2 (#168 R2 oversized; **#290 pre-existing as regression**) | ~26 | 8% |

**Note:** #281 false positive was systemic (all 3 reviewers compared against stale PR description) — counted separately as a process issue, not individual reviewer weakness.

## Reliability History

| Reviewer | Early (PRs #96-#145) | Mid (#155-#167) | Recent (#168-#294) | Trend |
|----------|---------------------|-----------------|--------------------|----|
| 🌟 Stella | 12/12 (100%) | 8/8 (100%) | 102/106 (96%) | → (timeout #176 R1, late #190 R5, miss #255 R2, timeout #278 R5) |
| 🌠 Nova | 12/12 (100%) | 8/8 (100%) | 110/110 (100%) | → |
| 💫 Vega | 8/12 (67%) | 6/8 (75%) | 101/104 (97%) | → (crash #278 R4, crash #294 R1. Otherwise 100% since #168) |

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
| #249 | cove | 2026-06-06 | R1-R2 | ✅ Ready | guildless-user-stuck, oauth-auto-join |
| #250 | cove | 2026-06-06 | R1 | ✅ Ready | pure-refactor (schema split) |
| #251 | cove | 2026-06-06 | R1 | ✅ Ready | wire-format-defaults |
| #252 | cove | 2026-06-06 | R1-R2 | ✅ Ready | presence-mutation-bug, gateway-events |
| #254 | cove | 2026-06-06 | R1-R2 | ✅ Ready | hardcoded-guild-removal |
| #255 | cove | 2026-06-06 | R1-R6 | ✅ Ready | resumed-abort, rest-retry, 204-json-parsing, post-idempotency, try-catch-control-flow |
| #261 | cove | 2026-06-07 | R1-R4 | ✅ Ready | retry-duplicate, ws-fallback, token-bucket, optimistic-send, nonce-validation |
| #263 | cove | 2026-06-07 | R1-R2 | ✅ Ready | o1-session-lookup, broadcastToGuilds-optimization |
| #264 | cove | 2026-06-07 | R1-R6 | ✅ Ready | session-ttl-data-loss, sliding-threshold-math, cookie-reissue, oauth-atomic, ws-session-lifetime |
| #278 | cove | 2026-06-09 | R1-R5 | ✅ Ready | scroll-listener-attachment, deep-history-restore, stale-cache-clobber, ref-in-render-lint, shared-observer |
| #279 | cove | 2026-06-09 | R1 | ✅ Ready | tuple-comparison-pagination |
| **#281** | **cove** | **2026-06-10** | **R1** | **⚠️ False positive** | **stale-description-driven false positives (all 3 reviewers)** |
| **#287** | **cove** | **2026-06-10** | **R1-R2** | **✅ Ready (merged)** | **resolver-throws-before-helper, guildId-leak-mapResolved, readAccountConfig-split** |
| **#290** | **cove** | **2026-06-10** | **R1** | **✅ Ready (merged)** | **dispatch-timeout-removal, isCurrent-guard-pattern** |
| **#294** | **cove** | **2026-06-10** | **R1-R2** | **⏳ Open (R2 fixes pushed, awaiting R3)** | **webhook-fk-violation, token-exfiltration, rate-limiting, permission-model** |

## Ground Truth Summary (39 merged PRs)

- **Human blind spots found by us:** 0 — human has never caught something we missed
- **Our blind spots:** 0 — human has never flagged something all 3 reviewers missed
- **Human rubber-stamp rate:** 97% — human approved without findings in 37/39 cases. Exceptions: #174 (design questions), #281 (false positive — stale description)
- **Iterative review as quality gate:** In 35/39 merged PRs, our multi-round review was the actual quality gate (human approved final state without independent analysis)
- **Over-flagging instances:** 2 (#100 — verdict too conservative; #281 — stale PR description led all 3 reviewers astray)
- **Multi-round PRs:** 30/39 PRs went through 2+ rounds. Average rounds: 2.5. Max: 7 (#190)
- **Total review rounds:** ~130 across 39 merged PRs + 1 open PR
- **False-ready detection:** 1 case (#255 R4→R5) — R4 said Ready but R5 found the fix was non-functional. Self-correcting system working.
- **Escalation protocol validated:** 3 cases (#255 R2→R3, #264 R3→R4, #294 R1→R2 permission model) — unaddressed items correctly escalated. All led to fixes.

## Actionable Notes

1. **All 3 reviewers near or above 10% unique find rate.** Stella 12%, Nova 16% (↑), Vega 9% (↓). Vega dipping below 10% — monitor over next 5 PRs. Not yet at replacement threshold (needs 10+ reviews below 10%).

2. **Vega's calibration weakening slightly.** Two new data points:
   - #290: Over-flagged pre-existing abort behavior as a regression (Needs Changes when Stella+Nova correctly approved). This is a "regression vs pre-existing" misjudgment — Vega didn't verify whether the behavior existed before the PR.
   - #287: Missed Critical #1 severity (flagged resolveAccount throw as Ready when it was blocking).
   - **Action:** Monitor. If this pattern continues (3+ more calibration misses in next 10 PRs), consider adding "verify whether flagged behavior is pre-existing or newly introduced" to Vega's prompt.

3. **Nova's security model design dimension is emerging.** #294 R1 token exfiltration find is the strongest unique security find since #248 PUBLIC_PATHS. Neither Stella nor Vega caught it. Nova reasons about security *model* (how the system's security design works) vs security *code* (individual bug). Consider emphasizing security model analysis in all reviewer prompts.

4. **#281 stale-description pattern is a systemic issue.** All 3 reviewers compared against outdated PR description instead of understanding design evolution. **Action needed:** Add prompt guidance: "When reviewing, verify that your understanding of the feature matches the actual code, not just the PR description. PR descriptions may be stale."

5. **#294 is the most complex open review.** Two rounds, 5+ critical issues found. Token exfiltration (Nova unique) + FK violation + rate limiting + permission model. Strong test of multi-round depth. Expect 1-2 more rounds before Ready.

6. **Nova continues zero false positives across 130 rounds.** Best-calibrated reviewer. Continue using Nova's verdict as tiebreaker.

7. **Throughput sustained.** PRs #281, #287, #290, #294 — 4 PRs in 1 day with ~7 review rounds total. Service scaling well.

8. **Escalation protocol robust.** #294 R1→R2 permission model escalation (3/3 consensus) joins #255 and #264 as successful escalation cases. Working as designed.

9. **Reviewer model versions stable.** No model changes since launch. Performance trends are attributable to prompt tuning, not model upgrades.

10. **Ground truth: 39 merged PRs, human rubber-stamps 97%.** Our iterative review IS the quality gate. This validates the service but means limited external validation.
