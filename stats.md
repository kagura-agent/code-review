# Code Review Service — Reviewer Stats

_Last updated: 2026-06-08 02:26 (Asia/Shanghai)_

## Per-Reviewer Performance

| Reviewer | Model | Total Review Rounds | Reliability | Trend |
|----------|-------|---------------------|-------------|-------|
| 🌟 Stella | gpt-5.5 | 103 | 100/103 (97%) → | Stable — 1 timeout (#176 R1), 1 late (#190 R5), 1 miss (#255 R2). Last 44+ rounds ex-R2: clean |
| 🌠 Nova | claude-opus-4.7 | 106 | 106/106 (100%) → | Rock solid. No failures ever |
| 💫 Vega | gemini-3.1-pro-preview | 103 | 99/103 (96%) ↑ | Improving — last 50+ rounds: 100%. Early failures dragging average |

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
| Protocol/Gateway | ⭐⭐⭐ | **RESUMED aborts dispatches** (#255 R1 — unique insight: RESUME should NOT trigger dispatch abort), `resumed` vs `reconnect` event distinction, channel refetch lifecycle. **WS fallback gap** (#261 R1 — WS disconnect → sidebar loading forever) |
| Control Flow Analysis | ⭐⭐⭐ | **try/catch control flow bug** (#255 R5 — caught that R4's "fix" was non-functional: POST still retried due to throw inside try). New dimension. |

**Stella's superpower:** Runs actual builds + reproduces bugs locally. Catches things that pure code reading misses. Deepest lifecycle analysis. Most persistent on escalation rules. Protocol-level reasoning. **New: control flow verification** — caught that an apparent fix didn't actually work (#255 R5).
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

**Nova's superpower:** Best calibration. Most suggestions per review, almost all actionable. Strongest on API compatibility, security, accessibility, async lifecycle, and retry semantics. Zero false positives across 99 rounds.
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

**Vega's superpower:** Fast (~1m avg). Capable of star-quality finds when the bug is deterministic/logical (gen ID reuse #190, own-message-unread #192, 204 JSON parsing #255). Cleanest fix suggestions. Excellent edge-case tenacity (deleted-message tracked across 3 rounds). Strong on input sanitization/DoS vectors.
**Vega's weakness:** Fewer unique finds overall but improving. Sometimes over-escalates severity (#191 R2 — ❌ Major for all 3 issues). One premature Ready in #261 R3 — isolated, not a pattern.

## Unique Find Rate (last 10 PRs: #240 through #261)

| Reviewer | Unique Finds | Total Issues Found | Unique Rate | Trend |
|----------|-------------|-------------------|-------------|-------|
| 🌟 Stella | 15 | ~120 | ~13% | → Stable |
| 🌠 Nova | 19 | ~120 | ~16% | → Stable |
| 💫 Vega | 14 | ~120 | ~12% | → Stable |

**Notable unique finds (last 10 PRs: #240-#261):**
- Stella: mobile sidebar scroll overlap (#240 R2), logout doesn't close WS (#248 R3), local dev NODE_ENV gap (#248 R3), presence mutation on GUILD_MEMBER (#252 R1), **RESUMED aborts dispatches** (#255 R1), channel refetch discarded (#255 R1), **dispatch.ts fallback paths use sendMessage** (#255 R3), **try/catch control flow verification** (#255 R5 — caught false-ready from R4), **WS fallback loading forever** (#261 R1), setMessages/pending race (#261 R4)
- Nova: mobile sidebar safe-area padding (#240 R2), **PUBLIC_PATHS signup break** (#248 R1), cookie attribute test assertions (#248 R3), CORS credentials concern (#248 R3), guildless user stuck (#249 R1), **Retry-After NaN/unbounded** (#255 R1), **POST retry duplicates** (#255 R2), sendTyping retry budget (#255 R2), INVALID_SESSION socket guard (#255 R1), **empty guilds READY crash** (#261 R3), **nonce validation ordering** (#261 R3), retry/dismiss keyboard a11y (#261 R3), **broadcastToGuilds loop optimization** (#263 R1)
- Vega: safe-area background gap (#240 R1), getComputedStyle render race (#240 R2), **parseCookies URIError DoS** (#248 R1), **localStorage XSS remnant** (#248 R2), null propagation clarity (#254 R2), **204 JSON parsing retry storm** (#255 R2), token bucket math (#261 R1), broadcastToGuilds loop (#263 R1)

## Consensus Participation

| Reviewer | Part of 2/3+ consensus | Solo dissent (correct) | Solo dissent (noise) |
|----------|----------------------|----------------------|---------------------|
| 🌟 Stella | 86% | 8 (WS scoping, presences, build-order, WS disconnect #176 R3, auto-ack dedup #192 R4, RESUMED abort semantics #255 R1, dispatch.ts fallback paths #255 R3, **try/catch control flow #255 R5**) | 1 (WS scoping over-scope #168) |
| 🌠 Nova | 93% | 4 (ready when others flag, PUBLIC_PATHS #248 R1, POST retry idempotency #255 R2, **empty guilds READY #261 R3**) | 0 |
| 💫 Vega | 85% | 6 (#125 R1, gen ID reuse #190 R4, own-message-unread #192 R2, parseCookies DoS #248 R1, localStorage XSS #248 R2, 204 JSON parsing #255 R2) | 1 (#261 R3 Ready while Stella+Nova found blockers — isolated) |

## Severity Calibration

| Reviewer | Verdict matches final | Over-flags | Under-flags |
|----------|----------------------|------------|-------------|
| 🌟 Stella | 80% | 15% (WS scoping, build-order, same-ms monotonicity) | 5% |
| 🌠 Nova | 95% | 3% | 2% |
| 💫 Vega | 82% | 10% | 8% (↑ from 6% — #261 R3 Ready premature) |

## False Positive Rate (Critical flagged → later proven non-issue)

| Reviewer | False Positives | Total Criticals | FP Rate |
|----------|----------------|-----------------|---------|
| 🌟 Stella | 1 (WS scoping as blocker for #168) | ~30 | 3% |
| 🌠 Nova | 0 | ~28 | 0% |
| 💫 Vega | 1 (#168 R2 oversized; #125 R1 over-flagged) | ~24 | 4% |

## Reliability History

| Reviewer | Early (PRs #96-#145) | Mid (#155-#167) | Recent (#168-#261) | Trend |
|----------|---------------------|-----------------|--------------------|----|
| 🌟 Stella | 12/12 (100%) | 8/8 (100%) | 80/83 (96%) | → (timeout #176 R1, late #190 R5, miss #255 R2) |
| 🌠 Nova | 12/12 (100%) | 8/8 (100%) | 86/86 (100%) | → |
| 💫 Vega | 8/12 (67%) | 6/8 (75%) | 79/79 (100%) | ↑ Significant improvement after prompt fixes |

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
| **#255** | **cove** | **2026-06-06** | **R1-R6** | **✅ Ready (merged)** | **resumed-abort, rest-retry, 204-json-parsing, post-idempotency, try-catch-control-flow** |
| **#261** | **cove** | **2026-06-07** | **R1-R4** | **✅ Ready (merged)** | **retry-duplicate, ws-fallback, token-bucket, optimistic-send, nonce-validation** |
| **#263** | **cove** | **2026-06-07** | **R1-R2** | **✅ Ready (merged)** | **o1-session-lookup, broadcastToGuilds-optimization** |
| **#264** | **cove** | **2026-06-07** | **R1 (open)** | **❌ Major Issues** | **session-ttl-delete-vs-update, migration-immediate-expiry, refreshTTL-dead-code** |

## Ground Truth Summary (33 merged PRs + 1 open)

- **Human blind spots found by us:** 0 — human has never caught something we missed
- **Our blind spots:** 0 — human has never flagged something all 3 reviewers missed
- **Human rubber-stamp rate:** 97% — human approved without findings in 32/33 cases. Exception: #174 where human asked design-level questions while our review caught code-level safety. Complementary perspectives.
- **Iterative review as quality gate:** In 30/33 merged PRs, our multi-round review was the actual quality gate (human approved final state without independent analysis)
- **Over-flagging instances:** 1 (#100 — verdict too conservative for personal project context)
- **Multi-round PRs:** 27/34 PRs went through 2+ rounds. Average rounds: 2.6. Max: 7 (#190)
- **Total review rounds:** 97 across 34 PRs (33 merged + 1 open)
- **False-ready detection:** 1 case (#255 R4→R5) — R4 said Ready but R5 found the fix was non-functional. Self-correcting system working.

## Actionable Notes

1. **All 3 reviewers above 10% unique find rate.** No reviewer flagged for replacement. Healthy distribution.

2. **#255 saga completed (6 rounds, merged).** The most complex review in our history. Key milestones:
   - R2: Vega's 204 JSON parsing star find
   - R3: POST retry escalation by all 3 (3/3 consensus escalation working)
   - R5: **False-ready catch** — Stella (all 3 confirmed) caught that R4's "fix" had a try/catch control flow bug making `isIdempotent` gate non-functional. POST still retried 4x.
   - R6: Fix confirmed + 15 unit tests. This is the first time our review caught a "fix that didn't fix."
   - **New signal:** Multi-round review can catch its own false-readies. This validates the iterative approach.

3. **Vega gave premature Ready in #261 R3 (isolated).** While Stella and Nova found remaining blockers (empty guilds READY crash, nonce validation ordering), Vega said LGTM. Single instance — not a pattern. Vega returned correct Ready in R4.

4. **Nova continues zero false positives across 99 rounds.** Best-calibrated reviewer. Continue using Nova's verdict as tiebreaker.

5. **#261 merged after R4 (4 rounds).** All issues from R1-R3 resolved. Stella's R4 setMessages/pending race was correctly assessed as non-blocking (follow-up issue). System self-calibrating on blocker vs follow-up.

6. **#263 merged after R2 (2 rounds).** Clean performance PR. Nova+Vega caught `broadcastToGuilds` loop optimization. Fixed in one round. Fast turnaround.

7. **#264 open with Major Issues (R1).** Session TTL PR has critical data-loss bug: `DELETE FROM users` instead of `UPDATE` token clear. Plus migration immediate-expiry risk. Needs significant rework.

8. **Stella adding "Control Flow Analysis" dimension.** The #255 R5 find (try/catch making isIdempotent non-functional) is qualitatively different from code reading — it's tracing execution paths through exception handling. This is becoming a Stella signature strength alongside build verification.

9. **Nova emerging as "last reviewer standing" pattern.** In #255 R5, #261 R3, and #263 R1, Nova found issues that at least one other reviewer missed. Nova's calibration advantage is growing. 16% unique find rate (highest).

10. **Vega premature Ready in #261 R3 was isolated.** R4 Vega returned to Ready correctly along with Nova. Not a trend — single instance. Continue monitoring.

11. **Security review capability validated across multiple PRs:** #156 (XSS), #202 (snowflake auth), #248 (BFF cookies), #255 (retry semantics), #264 (session TTL data loss). Each surface found by different reviewer combinations — multi-reviewer approach justified.

12. **Ground truth pattern: human rubber-stamps ~97% of the time.** Our iterative review IS the quality gate. This validates the service but also means limited external validation. Consider requesting more detailed human reviews for high-stakes PRs.

13. **Escalation protocol robust.** POST retry: R2 🟡 → R3 🔴 (3/3 consensus). Working as designed. No false escalations observed.

14. **Reviewer model versions stable.** No model changes since launch. Performance trends are attributable to prompt tuning, not model upgrades.

15. **Throughput high this cycle.** PRs #255 (6 rounds), #261 (4 rounds), #263 (2 rounds), #264 (1 round, open) — 13 review rounds in 2 days. Service scaling well.
