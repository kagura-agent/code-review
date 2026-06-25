# Code Review: PR #432 — Server-Level Roles and Permissions

**Reviewer:** 💫 Vega  
**PR:** https://github.com/kagura-agent/cove/pull/432  
**Commit:** f323270  
**Date:** 2026-06-25  
**Verdict:** ⚠️ Needs Changes (1 Critical, 1 High, 3 Medium)

---

## Executive Summary

This PR implements a full Discord-parity permission system — a massive, well-structured change touching 26 files (+1163/-288). The core permission computation algorithm is correct and faithfully matches Discord's documented behavior. The spec is excellent and the implementation is generally disciplined. However, I found **one critical privilege escalation vector** in the role position bulk-update endpoint and **one high-severity fail-open pattern** in the WebSocket dispatcher that must be fixed before merge.

---

## 🔴 Critical Findings

### C1: Privilege Escalation via Bulk Role Position Update

**File:** `routes/roles.ts` — `PATCH /guilds/:guildId/roles` (bulk position update)  
**Severity:** Critical — Privilege Escalation  

The endpoint validates that the **target position** is below the caller's highest role, but does NOT validate that the **role being moved** is below the caller's highest role.

```typescript
for (const entry of body) {
  // ✅ Checks target position
  if (entry.position >= callerHighest) {
    return missingPermissions(c);
  }
  // ❌ MISSING: Check that the role's CURRENT position is below callerHighest
}
```

**Attack scenario:**
1. Attacker has MANAGE_ROLES with highest role at position 3
2. A high-privilege role exists at position 5 (with ADMINISTRATOR)
3. Attacker calls `PATCH /guilds/:guildId/roles` with `[{ id: "<high-role-id>", position: 2 }]`
4. The role is moved to position 2 (below attacker's position 3) — **passes validation**
5. Attacker can now `PATCH` that role (position 2 < 3) or assign it to themselves
6. Full privilege escalation achieved

**Fix:** Add a check that each role's current position is below `callerHighest`:

```typescript
for (const entry of body) {
  if (entry.id === guildId) {
    return validationError(c, "Cannot change position of @everyone role");
  }
  if (entry.position >= callerHighest) {
    return missingPermissions(c);
  }
  // ADD: Cannot reposition roles at or above your highest role
  const existingRole = roles.find(r => r.id === entry.id);
  if (existingRole && existingRole.position >= callerHighest) {
    return missingPermissions(c);
  }
}
```

Discord enforces this exact constraint.

---

## 🟠 High Findings

### H1: WebSocket Dispatcher Permission Filter is Fail-Open

**File:** `ws/dispatcher.ts` — `broadcastToGuildWithChannelFilter()`  
**Severity:** High — Data Leak  

The permission check in the dispatcher is wrapped in a guard that degrades to open if any dependency is unavailable:

```typescript
if (guild && roles && permChannel && overwrites && this.membersRepo && session.user) {
  // Permission check runs here
} else {
  // ❌ Falls through — event is dispatched WITHOUT permission check
}
```

If `this.membersRepo`, `this.rolesRepo`, or `this.permissionsRepo` are not set (e.g., initialization order issue, test setup, future refactor), **all events leak to all sessions** without any filtering.

**Fix:** Invert the logic to fail-closed:

```typescript
// Fail-closed: if we can't verify permissions, don't dispatch
if (!guild || !roles || !permChannel || !overwrites || !this.membersRepo || !session.user) {
  continue; // Skip this session — cannot verify permissions
}
const member = this.membersRepo.get(guildId, session.user.id);
if (!member) continue;
const perms = computePermissions(member, permChannel, guild, roles, overwrites);
if (!(perms & VIEW_CHANNEL_BIT)) continue;
```

Currently in production the repos ARE set (`index.ts` calls all three setters), so this is not actively exploitable, but the pattern is dangerous for a security-critical path.

---

## 🟡 Medium Findings

### M1: Cross-Guild Role Information Leak

**File:** `routes/roles.ts` — `GET /guilds/:guildId/roles/:roleId`  
**Severity:** Medium — Information Disclosure  

The endpoint verifies the user is a member of `guildId` but fetches the role by ID without verifying it belongs to that guild:

```typescript
if (!repos.guilds.exists(guildId)) return unknownGuild(c);
if (!repos.members.exists(guildId, user.id)) return unknownGuild(c);

const role = repos.roles.getById(roleId);  // ❌ No guild_id check
if (!role) return unknownRole(c);
return c.json(role);
```

`getById()` in `repos/roles.ts` queries by `id` only, not `(id, guild_id)`. If a user knows a role ID from another guild, they can fetch its details (name, permissions, color) while authenticated against any guild they're a member of.

**Fix:** Either filter in the query or validate after fetch. Since `Role` doesn't include `guild_id`, use the repo layer:

```typescript
// In RolesRepo:
getByIdInGuild(roleId: string, guildId: string): Role | null {
  const row = this.db.prepare("SELECT * FROM roles WHERE id = ? AND guild_id = ?")
    .get(roleId, guildId) as RoleRow | undefined;
  return row ? toRole(row) : null;
}
```

### M2: Guild Webhook Listing Missing Permission Check

**File:** `routes/webhooks.ts` — `GET /guilds/:guildId/webhooks`  
**Severity:** Medium — Missing Authorization  

This endpoint only checks guild membership, not MANAGE_WEBHOOKS:

```typescript
app.get("/guilds/:guildId/webhooks", (c) => {
  const user = c.get("botUser");
  const guildId = c.req.param("guildId");
  if (!repos.guilds.exists(guildId) || !repos.members.exists(guildId, user.id)) {
    return c.json({ message: "Unknown Guild", code: 10004 }, 404);
  }
  return c.json(repos.webhooks.listByGuild(guildId));
});
```

Discord requires MANAGE_WEBHOOKS for this endpoint. This exposes webhook metadata (names, channel bindings) to any guild member. Webhook tokens are already stripped by `stripToken()`, so the impact is information disclosure only.

**Fix:** Add `requireGuildPermission(repos, guildId, user.id, PermissionBits.MANAGE_WEBHOOKS)`.

### M3: Channel File Write/Delete Only Requires VIEW_CHANNEL

**File:** `routes/channel-files.ts`  
**Severity:** Medium — Weak Authorization  

All channel file operations (list, read, write, delete) only require `VIEW_CHANNEL`:

```typescript
app.put("/channels/:channelId/files/:filename", async (c) => {
  await requireChannelPermission(repos, channelId, user.id, PermissionBits.VIEW_CHANNEL);
  // ...write file...

app.delete("/channels/:channelId/files/:filename", async (c) => {
  await requireChannelPermission(repos, channelId, user.id, PermissionBits.VIEW_CHANNEL);
  // ...delete file...
```

Writing files should arguably require SEND_MESSAGES (or a Cove-specific permission), and deleting files should require MANAGE_MESSAGES or be restricted to file owner. Any user with VIEW_CHANNEL can overwrite or delete any channel file.

**Recommendation:** At minimum, write should require `VIEW_CHANNEL | SEND_MESSAGES` and delete should require the author check or `MANAGE_MESSAGES`.

---

## ✅ What's Done Well

### Core Algorithm (permissions/compute.ts) — Correct
The `computeBasePermissions` / `computeOverwrites` / `computePermissions` trio faithfully implements Discord's documented algorithm:
- Owner bypass → ALL_PERMISSIONS ✅
- @everyone role as base ✅  
- Role permission OR accumulation ✅
- ADMINISTRATOR bypass at both guild and channel level ✅
- Overwrite priority: @everyone → role (combined) → member ✅
- BigInt used throughout (no Number truncation) ✅
- Thread channels use parent channel overwrites ✅

### Helpers (routes/helpers.ts) — Well-Designed
- `requireChannelPermission` and `requireGuildPermission` use HTTPException throws, matching Hono patterns
- AND semantics for multi-bit permission checks (`(perms & permission) !== permission`) ✅
- Thread → parent channel resolution ✅
- Returns the loaded entity for handler reuse ✅

### Role Hierarchy (routes/roles.ts) — Mostly Solid
- Create: permission value subset check ✅
- Update: managed role guard + position constraint + permission subset check ✅
- Delete: @everyone guard + managed guard + position constraint + transactional cleanup ✅
- Assignment: managed guard + position constraint + idempotency ✅
- All owner-exempt correctly ✅

### Migrations — Safe
- v19: `CREATE TABLE IF NOT EXISTS` + `INSERT OR IGNORE` → idempotent ✅
- v19: Orphaned role cleanup iterates correctly ✅
- v20: Bootstrap owner only for `owner_id IS NULL` guilds ✅
- Schema auto-creates @everyone on fresh DB ✅

### Route Handler Migration — Thorough
All ~30+ callsites migrated from `requireGuildMember()` + `requireBotChannelPermission()` to the new unified system. Bot and human users go through identical permission paths. The old dual-system pattern is cleanly replaced.

### Test Updates — Appropriate
Tests properly updated to:
- Set admin as guild owner (needed for owner bypass)
- Add explicit deny overwrites for bot denial tests (since bots now get @everyone perms by default)
- The behavioral shift from "default deny" to "default allow + explicit deny" in tests correctly reflects the new model

### Gateway Event Emission — Complete
`GUILD_ROLE_CREATE`, `GUILD_ROLE_UPDATE`, `GUILD_ROLE_DELETE`, `GUILD_MEMBER_UPDATE` all emitted from the correct code paths.

---

## 💡 Low / Nits

### L1: Migration Test Description Mismatch
**File:** `__tests__/migration.test.ts`  
Test name says `"fresh DB gets user_version = 19"` but asserts `expect(version).toBe(20)`. Should say `user_version = 20`.

### L2: Direct `repos.db` Access in Role Routes
**File:** `routes/roles.ts` — role assignment/removal  
```typescript
repos.db
  .prepare("UPDATE guild_members SET roles = ? WHERE guild_id = ? AND user_id = ?")
  .run(JSON.stringify(newRoles), guildId, targetUserId);
```
This bypasses the `MembersRepo` abstraction. Should add an `updateRoles(guildId, userId, roles)` method to `MembersRepo`.

### L3: No Tests for Privilege Escalation Vectors
There are no tests covering:
- Attempt to reposition a role above the caller's highest
- Attempt to create a role with permissions exceeding the caller's
- Attempt to modify a managed role
- Cross-guild role fetch

Given this is a security-critical PR, these negative tests are important.

### L4: Redundant `@everyone` Overwrite Type Check
In `computeOverwrites`, the @everyone overwrite check (`overwrites.find(o => o.id === guildId)`) doesn't filter by `type === 0`, unlike the role-specific overwrites. This matches Discord's algorithm (the @everyone overwrite's type is implicitly role), but could use a comment noting the intentional omission.

### L5: `threads.test.ts` Behavior Change
The test change from "returns 404 for non-thread channel" to "returns empty array for non-thread channel" is a behavioral change in the thread-members listing. This is correct under the new system (`requireChannelPermission` succeeds on any viewable channel, and the member query returns empty for non-threads), but should be documented as an intentional API behavior change.

---

## Checklist Summary

| Category | Status | Notes |
|---|---|---|
| Permission computation algorithm | ✅ Pass | Discord-exact implementation |
| Owner bypass | ✅ Pass | Correctly returns ALL_PERMISSIONS |
| ADMINISTRATOR bypass | ✅ Pass | Both guild-level and channel-level |
| Route coverage | ✅ Pass | All routes use new permission system |
| Bot/human parity | ✅ Pass | Same code path for both |
| Thread permission resolution | ✅ Pass | Uses parent channel overwrites |
| Role hierarchy — create/update/delete | ✅ Pass | Position + permission subset checks |
| Role hierarchy — bulk position | ❌ **FAIL** | Missing source position check (C1) |
| Permission overwrite value constraint | ✅ Pass | Guild-only bits + subset check |
| Managed role protection | ✅ Pass | Blocks modify/assign/remove |
| Gateway filtering | ⚠️ **Weak** | Fail-open guard (H1) |
| Migration idempotency | ✅ Pass | IF NOT EXISTS + OR IGNORE |
| BigInt safety | ✅ Pass | No Number truncation |
| Test coverage for security paths | ⚠️ **Gap** | Missing escalation tests (L3) |

---

## Required Before Merge

1. **[C1]** Fix bulk role position update to check source role position against caller's highest
2. **[H1]** Invert dispatcher permission guard to fail-closed
3. **[L3]** Add privilege escalation test cases

## Recommended (Non-Blocking)

4. **[M1]** Add guild_id validation to single-role GET endpoint  
5. **[M2]** Add MANAGE_WEBHOOKS to guild webhook listing  
6. **[M3]** Strengthen channel file write/delete permissions  
7. **[L1]** Fix test description  
8. **[L2]** Move role array update to MembersRepo
