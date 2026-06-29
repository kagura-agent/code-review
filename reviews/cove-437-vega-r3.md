# PR #437 — Multi-Server Support — Round 3 Re-Review

**Reviewer:** 💫 Vega  
**PR:** kagura-agent/cove#437  
**Commit:** 06a5d9f  
**Date:** 2026-06-29  

---

## 1. Previous Issues Status

### R1 Critical Issues

| ID | Issue | Status | Notes |
|----|-------|--------|-------|
| C1 | Guild creation not wrapped in transaction | ✅ Addressed (R2) | `repos.db.transaction()` wraps create guild + @everyone role + #general channel + member add. Confirmed. |
| C2 | GUILD_CREATE WS event missing channels/roles | ✅ Addressed (R2) | `guildCreateFull()` sends full payload with channels + roles. Client handler seeds channelStore and roleStore. Confirmed. |

### R2 Escalated Blocker

| ID | Issue | Status | Notes |
|----|-------|--------|-------|
| C3 | `icon` field has no validation | ✅ Addressed (R3) | Icon parameter completely removed from `POST /guilds` and `PATCH /guilds/:guildId` request body types. Both route handlers now parse `{ name }` / `{ name? }` only. Client `createGuild()` sends only `{ name }`, `updateGuild()` accepts only `{ name? }`. Icon upload deferred to #420. Clean fix. |

**Note on C3 fix completeness:** `GuildsRepo.update()` signature still accepts `{ name?: string; icon?: string }` and has the `if (data.icon !== undefined)` branch. This is dead code since no route passes `icon` anymore — not a security issue, but a leftover that should be cleaned up eventually.

### R1 Suggestions (non-blocking)

| ID | Issue | Status | Escalation |
|----|-------|--------|------------|
| S2 | Unused import `generateSnowflake` in repos/guilds.ts | ❌ Not addressed | Line 2: `import { generateSnowflake, type Guild }` — `generateSnowflake` is never called in this file (it's used in routes/guilds.ts via its own import). 3rd round unaddressed → **escalate to Concern**. Trivial one-line fix. |
| S3 | `saveLastChannel` coupling (GuildSidebar exports, Sidebar imports) | ❌ Not addressed | Cross-component coupling persists. Extract to a shared util. |
| S4 | Client GUILD_CREATE handler hardcodes `features: []` | ❌ Not addressed | `gateway-subscriptions.ts` line: `features: []` hardcoded instead of passing through from event payload. |
| S5 | Channel type magic number `0` | ❌ Not addressed | `GuildSidebar.tsx`: `channels.find((c) => c.type === 0)`. Should use a named constant. |
| S6 | Guild name validation duplication | ❌ Not addressed | Server validates in route, client validates in CreateServerDialog + OverviewSection. Three places. |
| S7 | Cascade delete documentation | ❌ Not addressed | Code comments exist but no formal doc. Also: cascade may not cover `message_reactions` or `channel_files` tables if they exist without FK cascades. |

### R1 Product Impact (non-blocking)

| ID | Issue | Status | Escalation |
|----|-------|--------|------------|
| P1 | Guild sidebar ordering non-deterministic | ❌ Not addressed | `Object.values(guilds)` relies on JS insertion order. After addGuild/removeGuild churn, order becomes unpredictable. Server returns `ORDER BY g.name` but the zustand store is a `Record<string, Guild>`. |
| P2 | Double-navigation on guild delete | ✅ Addressed (R3) | `DangerSection` now only calls `onClose()` after delete. Store cleanup + redirect handled exclusively by `GUILD_DELETE` gateway event in `gateway-subscriptions.ts`. Race eliminated. Clean separation of concerns. |
| P3 | Duplicate store updates on guild creation | ❌ Not addressed | `CreateServerDialog` manually calls `addGuild()` + `setChannels()`, then the `GUILD_CREATE` gateway event does the same. Harmless (idempotent overwrite) but wasteful. |

### R2 New Suggestions (non-blocking)

| ID | Issue | Status |
|----|-------|--------|
| N1 | CreateServerDialog doesn't seed roles | ❌ Not addressed | Dialog adds guild + channels to store but not roles. Gateway event covers it eventually, but there's a window where roles aren't available. |
| N2 | `addGuildToUser` still sends minimal GUILD_CREATE | ❌ Not addressed | Invite/member-add flow dispatches guild object without channels/roles. When invite system (#171) lands, joined users will get an incomplete GUILD_CREATE event. |
| N3 | `guildCreateFull` payload typed as `unknown` | ❌ Not addressed | `guildCreateFull(userId: string, guildId: string, payload: unknown)` — should have a proper interface. |
| N4 | `session.identify` parameter sprawl | ❌ Not addressed | Now **8 positional parameters** (added `membersRepo` in this PR). An options object would be much cleaner. |
| N5 | GUILD_UPDATE broadcasts full object | ❌ Not addressed | Route sends full guild object via `guildUpdate`. Discord sends partial. Minor bandwidth concern at scale. |
| N6 | No PATCH validation tests | ❌ Not addressed | Tests cover owner-can-update and non-owner-rejection, but not edge cases: empty name, name < 2 chars, name > 100 chars, whitespace-only name. |

---

## 2. New Issues (R3)

### S8. OverviewSection double-updates guild store *(Suggestion)*

`OverviewSection.handleSave()` calls `useGuildStore.getState().updateGuild(guildId, updated)` after the PATCH API call, but the server also dispatches `GUILD_UPDATE` which triggers the gateway subscription handler to call `updateGuild` again. Same double-update pattern as P3.

**Impact:** Harmless (idempotent), but inconsistent with the DangerSection pattern (R3 fix) which correctly relies on gateway events only. Could confuse future contributors about the intended pattern.

### S9. P2 fix trades immediacy for correctness *(Observation, non-blocking)*

The R3 DangerSection fix relies entirely on the `GUILD_DELETE` gateway event for store cleanup. If the WebSocket connection is temporarily down when the DELETE API call succeeds (HTTP and WS are independent), the user will see a success toast but the deleted guild remains in the sidebar until the WS reconnects and replays the event. The R2 approach (immediate cleanup) didn't have this issue but had the double-navigation race.

This is a reasonable tradeoff — correctness over immediacy — but worth documenting as a known limitation. A hybrid approach (optimistic cleanup + gateway event as confirmation) would be ideal but is unnecessary for V1.

---

## 3. Summary + Rating

### What's Fixed in R3
- **C3 (icon field):** Completely removed from API surface. Clean, minimal fix.
- **P2 (double-navigation):** Properly separated concerns — API call closes UI, gateway event handles state/navigation. Unused imports cleaned up.

### Remaining Items
All remaining issues (S2–S7, P1, P3, N1–N6, S8, S9) are **non-blocking suggestions**. None represent correctness bugs, security risks, or data integrity problems. They are tech debt / polish items appropriate for follow-up.

### Escalation Note
S2 (unused `generateSnowflake` import) has been unaddressed for 3 rounds. Escalating to **Concern** — not blocking, but it's a trivial fix that keeps getting skipped. Should be addressed before or immediately after merge.

---

### ✅ Ready to Merge

All critical and blocking issues from R1 and R2 have been resolved. The R3 changes are minimal, focused, and correct. The remaining suggestions are genuine improvements but none should block this PR. Ship it.
