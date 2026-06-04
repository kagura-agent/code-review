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

## Round 2 — 2026-06-04 (FlowForge)

**Verdict:** ⚠️ Needs Changes (3/3)

### R1 → R2 fixes
- Stale guildIds → live addGuildToUser/removeGuildFromUser ✅
- Optional channelsRepo → required ✅
- DM channels → TODO(#111) acknowledged 🟡

### New issues found in R2
- Self-broadcast on disconnect (Nova)
- No GUILD_CREATE/DELETE events to client (Nova)
- O(N²) IDENTIFY presence calculation (Vega)
- DM channels escalated (Stella)

### Reviewer Performance (Round 2)
| Reviewer | Verdict | Notes |
|----------|---------|-------|
| 🌟 Stella | ⚠️ | 4m9s. Full build + test verified. DM escalation strict but justified per rules |
| 🌠 Nova | ⚠️ | Self-broadcast + GUILD events gap — deepest lifecycle analysis. Most actionable fixes |
| 💫 Vega | ⚠️ | O(N²) perf finding — unique across all reviewers. Concrete fix suggestion |

### Layer 2 — Prompt Evolution Check
- "Self-broadcast on disconnect" is a lifecycle pattern — first occurrence
- "No client-side events for server-side state changes" — new pattern. Could become recurring
- O(N²) in hot path — performance dimension working. No prompt change needed
- No prompt changes ✅
