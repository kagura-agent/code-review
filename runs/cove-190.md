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
