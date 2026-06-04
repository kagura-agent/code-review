# cove#179 — scope gateway events by guild membership

**Date:** 2026-06-04
**Verdict:** ⚠️ Needs Changes (2/3)

## Consensus Critical
- Stale guildIds after membership changes — kicked users keep receiving events (Stella + Nova)

## Reviewer Performance (Round 1)
| Reviewer | Verdict | Notes |
|----------|---------|-------|
| 🌟 Stella | ❌ | Deepest security analysis. Found typing bypass for removed members. 3m11s, verified 107 tests locally |
| 🌠 Nova | ⚠️ | Optional channelsRepo trap + DM channel gap were unique. O(N²) perf analysis. Most suggestions |
| 💫 Vega | ✅ | Noted membership gap but didn't rate as critical. Performance suggestions (LRU cache) were unique |

## Layer 2 — Prompt Evolution Check
- "Stale authorization state" is a new pattern — first time across all reviews
- This connects to #168's WS guild scoping concern that Stella raised in R5/R6
- Not a prompt gap — reviewers found it without prompting. The Product Impact dimension helped frame it
- No prompt changes needed ✅
