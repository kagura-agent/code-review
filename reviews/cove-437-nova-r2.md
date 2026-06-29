# 🌠 Nova — Round 2 Re-Review: PR #437 (Multi-Server Support)

**PR:** kagura-agent/cove#437
**Branch:** `docs/434-multi-server-support`
**Latest commit:** `364626f`
**Reviewer:** Nova (Round 2)
**Date:** 2026-06-29

---

## 1. Previous Issues Status

### Critical Issues (R1)

| ID | Issue | Status | Notes |
|----|-------|--------|-------|
| **C1** | Guild creation not wrapped in transaction | ✅ **Addressed** | `repos.db.transaction()` now wraps all 4 DB writes (guild, role, channel, member) in `routes/guilds.ts:40-46`. Clean implementation. |
| **C2** | GUILD_CREATE WS event missing channels/roles | ✅ **Addressed** | New `dispatcher.guildCreateFull()` method sends full payload with channels + roles. Client handler in `gateway-subscriptions.ts` correctly seeds `channelStore` and `roleStore` from event payload. |

### Suggestions (R1)

| ID | Issue | Status | Escalated? | Notes |
|----|-------|--------|-----------|-------|
| **S1** | `icon` field lacks validation | ❌ Not Addressed | → **Critical** | `POST /guilds` and `PATCH /guilds/:guildId` accept arbitrary strings for `icon`. While icon upload is deferred to #420, the field is still writable via API. No format/length/protocol validation. Could store arbitrary payloads in DB. |
| **S2** | Unused import `generateSnowflake` in repos/guilds.ts | ❌ Not Addressed | → **Critical** | `repos/guilds.ts` line 2: `import { generateSnowflake, type Guild }` — `generateSnowflake` is never used in this file. The ID is generated in `routes/guilds.ts` and passed to `create()`. Dead import. |
| **S3** | `saveLastChannel` coupling (GuildSidebar → Sidebar) | ❌ Not Addressed | → **Critical** | `saveLastChannel` is defined in `GuildSidebar.tsx` and imported by `Sidebar.tsx`. A utility function for localStorage shouldn't live in a UI component. Should be in a shared lib/utils file. |
| **S4** | Client GUILD_CREATE handler hardcodes `features: []` | ❌ Not Addressed | → **Critical** | Both `gateway-subscriptions.ts` GUILD_CREATE handler and `CreateServerDialog.tsx` hardcode `features: []`. Should use `data.features ?? []` to be forward-compatible. |
| **S5** | Channel type magic number `0` | ❌ Not Addressed | → **Critical** | `GuildSidebar.tsx:155`: `channels.find((c) => c.type === 0)` — magic number for text channel type. Should use a named constant from `@cove/shared`. |
| **S6** | Guild name validation duplication | ❌ Not Addressed | → **Critical** | Name validation (2–100 chars, trim) duplicated in `CreateServerDialog.tsx`, `OverviewSection`, and `routes/guilds.ts`. Client-side validation is fine as UX, but the constants (min=2, max=100) should reference shared values. |
| **S7** | Cascade delete documentation | ❌ Not Addressed | → **Critical** | `GuildsRepo.delete()` manually deletes 7 tables but relies on SQLite `ON DELETE CASCADE` for `reactions`, `channel_files`, and `thread_members`. No comment documents this split responsibility. A reader might assume the manual list is exhaustive and file a bug for the "missing" tables. |

### Product Impact (R1)

| ID | Issue | Status | Notes |
|----|-------|--------|-------|
| **P1** | Guild sidebar ordering non-deterministic | ❌ Not Addressed | `Object.values(guilds)` iteration order depends on insertion order, not a stable sort. `listForUser()` queries `ORDER BY g.name`, but after WS-driven additions, order may diverge from DB order. |
| **P2** | Double-navigation on guild delete | ❌ Not Addressed | `DangerSection.handleDelete()` navigates after API call. Then `GUILD_DELETE` WS event handler also navigates. Both run in the same tab, causing two `router.navigate` calls in quick succession. |
| **P3** | Duplicate store updates on guild creation | ❌ Not Addressed | `CreateServerDialog` manually calls `addGuild` + `setChannels` from HTTP response, then `GUILD_CREATE` WS handler does the same. Idempotent but wasteful. Additionally, dialog never calls `setRoles`, so roles are missing until WS event arrives. |

---

## 2. New Issues

### N1. `CreateServerDialog` doesn't seed roles from API response — **Suggestion**
**File:** `packages/client/src/components/CreateServerDialog.tsx:37-44`

The dialog adds guild and channels from the HTTP response but skips `roles`:
```typescript
useGuildStore.getState().addGuild({ ... });
if (guild.channels?.length) {
  useChannelStore.getState().setChannels(guild.id, guild.channels);
}
// ← Missing: useRoleStore.getState().setRoles(guild.id, guild.roles);
```
Roles are only populated when the WS `GUILD_CREATE` event arrives. Brief window where the guild has no roles in store. If user navigates to server settings immediately, roles section may flash empty.

### N2. `addGuildToUser()` still sends minimal GUILD_CREATE — **Suggestion**
**File:** `packages/server/src/ws/dispatcher.ts:144-157`

The old `addGuildToUser()` method (used by `routes/agents.ts` for bot/agent membership) still sends a bare guild object without channels/roles. The new `guildCreateFull()` was added for guild creation but `addGuildToUser` was not updated. When a bot is added to an existing guild, its client won't receive channels/roles in the GUILD_CREATE event.

This is a pre-existing concern and out of scope for this PR (invite system is deferred to #171), but worth noting for consistency.

### N3. `GUILD_UPDATE` payload sends full guild object — **Suggestion**
**File:** `packages/server/src/routes/guilds.ts:99`

```typescript
dispatcher?.guildUpdate(guildId, updated);
```
`updated` is a full `Guild` object from `repos.guilds.update()`. The `GUILD_UPDATE` event type in `gateway-dispatcher.ts` defines partial fields (`name?`, `icon?`, etc.). Sending the full object works but includes `features: []` and other fields that weren't changed. Minor bandwidth inefficiency; Discord sends only changed fields.

### N4. `guildCreateFull` payload typed as `unknown` — **Suggestion**
**File:** `packages/server/src/ws/dispatcher.ts:163`

```typescript
guildCreateFull(userId: string, guildId: string, payload: unknown): void {
```
Using `unknown` loses type safety. Should be typed as `Guild & { channels: Channel[]; roles: Role[] }` or a named interface.

---

## 3. Summary

### What's Good
- **C1 & C2 properly addressed** — Transaction wrapping and full GUILD_CREATE payload are clean, correct implementations
- **Comprehensive test coverage** — `guilds.test.ts` covers CRUD, authorization, rate limiting, cascade delete, channel scoping, and cross-guild isolation (235 lines)
- **Client-side guild event tests** — `guild-events.test.ts` covers GUILD_CREATE/UPDATE/DELETE with proper mock setup
- **Permission model** — PATCH checks owner OR MANAGE_GUILD, DELETE is owner-only, seed guild protection works correctly
- **Guild store** — `updateGuild` with no-op on non-existent guild is defensive
- **UI** — GuildSidebar, CreateServerDialog, OverviewSection, DangerSection are well-structured with proper loading/error states and confirmation dialog for delete

### What Needs Attention
All R1 suggestions (S1–S7) and product impact items (P1–P3) remain unaddressed. Per escalation rules, suggestions are promoted to Critical. In practice, **S1 (icon validation)** and **S7 (cascade delete documentation)** are the most important to address before merge. The rest are code hygiene issues that could be batched into a follow-up.

### Rating

**⚠️ Needs Changes**

The two original critical issues are resolved. The remaining items are accumulated suggestions that were not addressed between rounds. **S1 (icon validation)** is the most actionable: at minimum, add a length limit and reject protocol schemes like `javascript:`. **S7 (cascade delete docs)** deserves a one-line comment noting SQLite CASCADE handles the remaining tables. The product impact items (P2 double-navigation, P3 duplicate updates) are real UX bugs that should be tracked even if not fixed in this PR.

**Recommended path to ✅:**
1. Add `icon` field validation (max length, optional URL format check, or just strip the field entirely since upload is deferred)
2. Add a comment in `GuildsRepo.delete()` noting that `reactions`, `channel_files`, `thread_members` are handled by SQLite `ON DELETE CASCADE`
3. Remove unused `generateSnowflake` import from `repos/guilds.ts`
4. File follow-up issues for P2 and P3
