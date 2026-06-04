# cove#190 — plugin dispatch resilience

**Date:** 2026-06-04
**Verdict:** ⚠️ Needs Changes (2/3)

## Consensus Findings
- AbortSignal not propagated to underlying dispatch — abort is observational, not cancellative (Stella + Nova)
- Typing indicator leaked on timeout/abort (Nova)
- Error identity by string compare (Nova)

## Reviewer Performance (Round 1)
| Reviewer | Verdict | Notes |
|----------|---------|-------|
| 🌟 Stella | ⚠️ | 2m52s. Found stale dispatch side-effects, verified build + 38 tests. Integration test gap |
| 🌠 Nova | ⚠️ | Most comprehensive. 3 criticals + 7 suggestions. Typing leak + error identity unique finds |
| 💫 Vega | ✅ | Signal propagation noted as future suggestion. Least depth but accurate |

## Layer 2 — Prompt Evolution Check
- "Abort doesn't actually cancel" is a new pattern — first occurrence. Async cancellation semantics
- "Typing indicator leak on error path" — relates to cleanup-on-all-paths, not a new prompt dimension
- No prompt changes needed ✅

## Round 2 — 2026-06-04 (FlowForge)

**Verdict:** ✅ Ready (2/3)

### R1 → R2 fixes
- Abort observational → mitigated with generation token fence ✅
- Typing indicator leak → cleanup in catch paths ✅
- Error string compare → custom Error subclasses ✅

### Reviewer disagreement
- Stella ❌: generation not incremented on timeout/reconnect — stale dispatch can still send
- Nova ⚠️: mitigated to safe behavior, configurable timeout + map cleanup needed
- Vega ✅: generation pattern is elegant, ready

### Reviewer Performance (Round 2)
| Reviewer | Verdict | Notes |
|----------|---------|-------|
| 🌟 Stella | ❌ | 2m49s. Found generation invalidation gap on timeout/reconnect. Guards incomplete for all callbacks. Most thorough |
| 🌠 Nova | ⚠️ | "Close to ready." Map cleanup leak unique. Honest about trade-off documentation |
| 💫 Vega | ✅ | UnhandledPromiseRejection on early return — unique library-level find |

### Layer 2 — Prompt Evolution Check
- "Generation token invalidation completeness" — new pattern. When you add a guard, need to verify ALL paths increment it
- "UnhandledPromiseRejection from early return" — async error handling pattern, first occurrence
- No prompt changes needed ✅

## Round 3 — 2026-06-04 (FlowForge)

**Verdict:** ⚠️ Needs Changes (3/3)

### R2 → R3 fixes
- Generation on timeout/reconnect ✅ (Stella's R2 blocker resolved)

### Escalated (3/3 consensus)
- UnhandledPromiseRejection on pre-aborted signal
- channelGeneration map never cleaned
- Not all callbacks guarded

### Reviewer Performance (Round 3)
| Reviewer | Verdict | Notes |
|----------|---------|-------|
| 🌟 Stella | ⚠️ | 5m22s. Most thorough — tested locally, listed every unguarded callback. Plugin shutdown gap unique |
| 🌠 Nova | ⚠️ | Escalated unhandled rejection from suggestion to critical. Typing callback proxy suggestion unique |
| 💫 Vega | ❌ | Strictest. Concrete code fix for unhandled rejection |

### Layer 2 — Prompt Evolution Check
- Escalation protocol driving quality — R2 🟡 items correctly escalated when unaddressed in R3
- "UnhandledPromiseRejection from early return" pattern now seen in 2 rounds — confirmed real
- No prompt changes needed ✅

## Round 3 — 2026-06-04 (FlowForge)

**Verdict:** ⚠️ Needs Changes (3/3)

### R2 → R3 fixes
- Generation increment on timeout/reconnect ✅

### Escalated (3/3 consensus)
- UnhandledPromiseRejection on pre-aborted signal
- channelGeneration map never cleaned
- Incomplete callback guards (only 3 of ~12 guarded)

### Reviewer Performance (Round 3)
| Reviewer | Verdict | Notes |
|----------|---------|-------|
| 🌟 Stella | ⚠️ | 5m22s. Most thorough — plugin shutdown gap unique. Verified 38 tests |
| 🌠 Nova | ⚠️ | Unhandled rejection escalation + concrete fix. Typing callback ghost indicator analysis |
| 💫 Vega | ❌ | Strictest escalation. Code examples for every fix |

## Round 4 — 2026-06-04 (FlowForge)

**Verdict:** ⚠️ Needs Changes (2/3)

### R3 → R4 fixes
- UnhandledPromiseRejection → dispatch.catch(() => {}) ✅
- Callback guards → isCurrent() on all 11 callbacks ✅
- channelGeneration cleanup → delete in finally ⚠️ introduces reuse bug

### Key finding: Generation ID reuse (Vega)
channelGeneration.delete() resets counter, next dispatch gets same gen as stale one.
Elegant fix: use AbortController reference equality instead of numeric counter.

### Reviewer Performance (Round 4)
| Reviewer | Verdict | Notes |
|----------|---------|-------|
| 🌟 Stella | ❌ | 4m18s. Queued side-effect race analysis is deepest. Reconnect map leak. But Vega's reuse bug is more critical |
| 🌠 Nova | ✅ | All criticals resolved from his perspective. Reconnect leak noted as follow-up. Most balanced |
| 💫 Vega | ⚠️ | **Star find of the session** — generation ID reuse via .delete() is a deterministic logic bug. AbortController identity fix is elegant and simplifies code |

### Layer 2 — Prompt Evolution Check
- "Counter reset via delete creates reuse vulnerability" — novel pattern. Identity-based guards (object ref) > numeric counters
- Vega's best unique find across all reviews today — architectural suggestion that eliminates an entire data structure
- No prompt changes needed ✅

## Round 5 — 2026-06-04 (FlowForge)

**Verdict:** ⚠️ Needs Changes (3/3, Stella late)

### R4 → R5 fixes
- Generation ID reuse → AbortController reference equality ✅ (Vega's R4 design adopted)
- channelGeneration map leak → eliminated (map removed) ✅

### Remaining issues (2/3 or 3/3 consensus)
- Queued side-effect race in sendOrEdit + deliver (3/3)
- Plugin shutdown doesn't abort (Nova + Vega + Stella)
- Configurable timeout (all, 5th round)

### New finding (Stella unique)
- Async handler race: controller installed after await → older message can abort newer dispatch

### Reviewer Performance (Round 5)
| Reviewer | Verdict | Notes |
|----------|---------|-------|
| 🌟 Stella | ❌ | 3m34s (late but completed). **Star find**: async handler ordering race — unique across all reviewers. Controller installed after multiple awaits = old message can abort new one |
| 🌠 Nova | ⚠️ | Most thorough queued race analysis with concrete trace. 7 suggestions |
| 💫 Vega | ⚠️ | Concise, focused on the queue guard fix |

### Layer 2 — Prompt Evolution Check
- "Async handler ordering race" — important new pattern. When async handlers share mutable state, registration order ≠ arrival order
- Queued side-effect race is a repeated pattern (3 rounds now) — but it's specific to this PR's async queue design, not a general prompt concern
- No prompt changes needed ✅

## Round 6 — 2026-06-04 (FlowForge)

**Verdict:** ⚠️ Needs Changes (3/3)

### R5 → R6 fixes
- Queued side-effect race in sendOrEdit + deliver ✅ (both isCurrent() re-checks added)

### Remaining (3/3 consensus)
- Async handler ordering race — controller after await (escalated 🔴)
- Plugin shutdown doesn't abort (escalated 🔴)
- Configurable timeout (6th round 🟡)

### Reviewer Performance (Round 6)
| Reviewer | Verdict | Notes |
|----------|---------|-------|
| 🌟 Stella | ⚠️ | 4m51s. Found deliver fallback race (cleanupAndSend after failed edit). Most complete previous-issues tracking |
| 🌠 Nova | ⚠️ | Handler ordering fix code example is clearest. Also found dispatch.catch missing in onAbort path |
| 💫 Vega | ❌ | Strictest. Same findings, concrete code examples for all 3 fixes |

### Layer 2 — Prompt Evolution Check
- "Controller installed after await" is now a 2-round pattern — async handler ordering matters
- All remaining fixes are ~10 lines total — the PR is architecturally sound
- No prompt changes needed ✅

### Summary: 6-round journey
R1: abort doesn't cancel → R2: generation fence → R3: generation on timeout → R4: ID reuse bug →
R5: AbortController identity + queue guards needed → R6: queue guards ✅, handler ordering + shutdown left

## Round 7 — 2026-06-04 (FlowForge)

**Verdict:** ✅ Ready (3/3 unanimous) 🎉

### R6 → R7 fixes (all 3 resolved)
- Async handler ordering → controller registered synchronously before any await ✅
- Plugin shutdown → iterate + abort + clear + destroy ✅
- Configurable timeout → channels.cove.dispatchTimeoutMs, 120s default ✅

### Reviewer Performance (Round 7)
| Reviewer | Verdict | Notes |
|----------|---------|-------|
| 🌟 Stella | ✅ | 6m27s. Re-checked all prior race surfaces. Pre-dispatch error cleanup suggestion unique |
| 🌠 Nova | ✅ | "Code demonstrates understanding of failure modes." Config typing suggestion. Most balanced |
| 💫 Vega | ✅ | Clean pass. dispatch.catch in onAbort path suggestion |

### Layer 2 — Prompt Evolution Check
- 7-round PR is the longest in our review history
- Key patterns discovered across rounds: generation ID reuse, async handler ordering, queued side-effect race
- These are all async/concurrency patterns — consider adding "async ownership and cancellation" as a review dimension? Track but don't add yet — too project-specific
- No prompt changes needed ✅

### Summary: 7-round journey
R1: abort doesn't cancel → R2: generation fence → R3: gen on timeout → R4: ID reuse →
R5: AbortController identity + queue guards → R6: queue ✅, ordering + shutdown → R7: ALL RESOLVED

This PR evolved from a basic timeout wrapper to a comprehensive dispatch resilience system.
