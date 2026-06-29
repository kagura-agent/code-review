# PR #437 — Multi-Server Support — Vega R2 Re-Review

**PR:** kagura-agent/cove#437
**Title:** feat: multi-server support (#434, #212)
**Branch:** docs/434-multi-server-support
**Latest commit:** 364626f
**Reviewer:** 💫 Vega (Round 2)
**Date:** 2026-06-29

---

## 1. Previous Issues Status

### Critical Issues

| ID | Issue | Status | Notes |
|----|-------|--------|-------|
| C1 | Guild creation not wrapped in transaction | ✅ **Addressed** | `repos.db.transaction()` now wraps all 4 DB writes (guild, role, channel, member) in `POST /guilds`. Clean fix. |
| C2 | GUILD_CREATE WS event missing channels/roles | ✅ **Addressed** | New `dispatcher.guildCreateFull()` sends full payload with channels + roles. Client handler seeds both `useChannelStore` and `useRoleStore` from the event. |

### Suggestions (from R1)

| ID | Issue | R1 Severity | Status | R2 Severity |
|----|-------|-------------|--------|-------------|
| S1 | `icon` field lacks validation | Suggestion (3/3) | ❌ **Not Addressed** | **⬆ Critical** |
| S2 | Unused import `generateSnowflake` in repos/guilds.ts | Suggestion (3/3) | ❌ **Not Addressed** | ⬆ Suggestion (escalated) |
| S3 | `saveLastChannel` coupling (exported from component) | Suggestion (2/3) | ❌ **Not Addressed** | ⬆ Suggestion (escalated) |
| S4 | Client GUILD_CREATE handler hardcodes `features: []` | Suggestion (1/3) | ❌ **Not Addressed** | ⬆ Suggestion (escalated) |
| S5 | Channel type magic number `0` | Suggestion (1/3) | ❌ **Not Addressed** | ⬆ Suggestion (escalated) |
| S6 | Guild name validation duplication | Suggestion (1/3) | ❌ **Not Addressed** | ⬆ Suggestion (escalated) |
| S7 | Cascade delete documentation | Suggestion (2/3) | ⚠️ **Partially Addressed** | Suggestion |

### Product Impact (from R1)

| ID | Issue | Status | Notes |
|----|-------|--------|-------|
| P1 | Guild sidebar ordering non-deterministic | ❌ **Not Addressed** | `Object.values(guilds)` depends on insertion order; no explicit sort. |
| P2 | Double-navigation on guild delete | ❌ **Not Addressed** | `DangerSection.handleDelete()` manually removes guild + navigates, AND the `GUILD_DELETE` WS event handler does the same cleanup + navigation. The user who deletes gets both paths triggered. |
| P3 | Duplicate store updates on guild creation | ❌ **Not Addressed** | `CreateServerDialog` adds guild/channels to store, then `GUILD_CREATE` event does the same. Idempotent but redundant. |

---

## 2. Detailed Analysis of Unaddressed Issues

### S1 → C3: `icon` field lacks server-side validation (Escalated to Critical)

**Files:** `packages/server/src/routes/guilds.ts` (POST + PATCH), `packages/client/src/components/GuildSidebar.tsx`

The `icon` field is accepted as arbitrary string input in both POST and PATCH without any validation. It is then rendered directly as `<img src={guild.icon}>` in `GuildSidebar.tsx`:

```tsx
// GuildSidebar.tsx line ~190
{guild.icon ? (
  <img src={guild.icon} alt={guild.name} style={{ width: "100%", height: "100%", objectFit: "cover" }} />
) : (
  getAbbreviation(guild.name)
)}
```

**Risk:** While `<img>` tags don't execute JavaScript from `src`, arbitrary URLs could:
- Load external tracking pixels (privacy leak)
- Load `data:` URIs of arbitrary size (DoS via memory)
- Point to offensive content
- Be used for SSRF if server ever proxies icons

**Recommendation:** Either:
- Remove `icon` from POST/PATCH body entirely (spec defers icon upload to #420)
- Or validate as URL matching an allowlist (e.g., `/^https?:\/\//` + max length)

### S2: Unused `generateSnowflake` import in repos/guilds.ts (Escalated)

```typescript
// packages/server/src/repos/guilds.ts
import { generateSnowflake, type Guild } from "@cove/shared";
// ^ generateSnowflake is never used — the ID is passed in via create({ id, ... })
```

Trivial fix: remove from the import.

### S7: Cascade delete — Partially Addressed

The spec documents the approach ("V1 uses synchronous cascade delete"), and the implementation in `repos/guilds.ts` `delete()` covers: messages, read_states, channel_permission_overwrites, channels, guild_members, roles, webhooks.

**Note:** Thread-related tables (if any) are not explicitly cleaned up. If threads have their own rows beyond the channels table, they could be orphaned. Worth verifying.

---

## 3. New Issues

### N1. `guildCreateFull` payload typed as `unknown` (Suggestion)

**File:** `packages/server/src/ws/dispatcher.ts`

```typescript
guildCreateFull(userId: string, guildId: string, payload: unknown): void {
```

The `payload` parameter is typed as `unknown`, losing type safety. Should use a proper interface (e.g., `Guild & { channels: Channel[]; roles: Role[] }`).

### N2. Transaction return type requires `as` assertion (Suggestion)

**File:** `packages/server/src/routes/guilds.ts`

```typescript
const { guild, everyoneRole, generalChannel } = repos.db.transaction(() => {
  // ...
  return { guild, everyoneRole, generalChannel };
})() as { guild: ...; everyoneRole: Role; generalChannel: Channel };
```

The `as` type assertion on the transaction result is a code smell. `better-sqlite3`'s `transaction()` should infer the return type. If the library's types don't support this, a wrapper function would be cleaner.

### N3. `setupGateway` / `session.identify` parameter lists are growing unwieldy (Suggestion)

**File:** `packages/server/src/ws/index.ts`, `packages/server/src/ws/session.ts`

`setupGateway` now takes 9 positional parameters. `session.identify` takes 8. These should be refactored to accept an options/deps object:

```typescript
// Instead of:
setupGateway(server, users, guilds, channels, dispatcher, readStates, permissions, roles, members)

// Consider:
setupGateway(server, dispatcher, { users, guilds, channels, readStates, permissions, roles, members })
```

### N4. `guildUpdate` broadcasts full guild object instead of partial (Minor)

**File:** `packages/server/src/ws/dispatcher.ts`

```typescript
guildUpdate(guildId: string, guild: unknown): void {
    this.broadcastToGuild(guildId, "GUILD_UPDATE", guild);
}
```

The PATCH route passes the full updated guild object. Discord's `GUILD_UPDATE` sends only changed fields. This is fine functionally but sends unnecessary data over the wire.

### N5. No test for PATCH name validation edge cases (Suggestion)

**File:** `packages/server/src/__tests__/guilds.test.ts`

Tests exist for POST name validation (< 2 chars, max guilds) but PATCH doesn't test:
- Name too short
- Name too long
- Empty body (no-op PATCH)
- Icon field values

---

## 4. Summary

### What's Good
- **C1 and C2 are properly fixed.** The transaction wrapping is clean and the `guildCreateFull` dispatcher method correctly adds the guild to session subscriptions before sending the event.
- **Comprehensive test coverage** for guild CRUD (235 lines) and gateway events (164 lines).
- **Clean cascade delete** implementation with proper ordering (messages → channels → members → roles → webhooks → guild).
- **Bot channel filtering** improved from simple `hasPermission` to proper `computePermissions` with overwrites — this is actually better than what was there before.
- **Proper ownership checks** throughout: owner-only delete, owner-or-MANAGE_GUILD for PATCH, seed guild protection.
- **Good UX touches:** confirmation dialog for delete requiring exact name match, proper loading states, error handling.

### What Needs Attention
- **S1 (icon validation)** is the only issue I'd escalate to blocking. The field is accepted without any validation and rendered as `<img src>`. Since the spec explicitly defers icon upload to #420, the simplest fix is to strip `icon` from the POST/PATCH body entirely for now.
- **P2 (double-navigation on delete)** is a real UX bug — the deleting user will get two navigations. Simple fix: let the WS event handler handle it exclusively, or skip the manual navigation in `DangerSection`.
- All other items are non-blocking quality improvements.

### Rating

## ⚠️ Needs Changes

The two critical issues from R1 are resolved. One escalated issue (S1 → C3: icon validation) and one product bug (P2: double-navigation) need attention before merge. Everything else is non-blocking.

**Blocking:**
1. **C3 (was S1):** Strip or validate `icon` field — easiest to just ignore it until #420
2. **P2:** Fix double-navigation on guild delete — choose one path (WS handler or manual), not both

**Non-blocking (address in follow-ups):**
- S2: Remove unused import
- S3: Extract `saveLastChannel` to a utility module
- S4: Use `data.features ?? []` instead of hardcoded `[]`
- S5: Use named constant for channel type
- S6: Consider shared validation constants
- N1–N5: Type safety and test coverage improvements
