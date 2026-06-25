# Code Review: PR #432 — feat: server-level roles and permissions

**Reviewer:** 🌠 Nova  
**PR:** https://github.com/kagura-agent/cove/pull/432  
**Commit:** f323270  
**Date:** 2026-06-25  
**Rating:** ❌ **Major Issues** — 2 Critical privilege escalation vulnerabilities must be fixed before merge

---

## Executive Summary

This PR implements a comprehensive Discord-parity permission system (Phase A). The core `computePermissions` algorithm is correct and faithfully matches Discord's documented approach. The migration is well-designed and idempotent. Route handler unification (bot + human same system) is a significant security improvement.

However, the review identified **2 Critical privilege escalation vulnerabilities** and **1 High severity fail-open pattern** that must be addressed before merging.

---

## 🔴 Critical Issues

### C1. Bulk Position Update — Privilege Escalation via Hierarchy Bypass

**File:** `routes/roles.ts` — `PATCH /guilds/:guildId/roles` (bulk position update)  
**Lines:** Bulk position validation loop

**Problem:** The handler validates that the **target position** is below the caller's highest role, but does **not** validate that the role being moved is **currently** below the caller's highest role. This violates spec §5.6 rule 1: *"Can only create/modify/delete roles with position strictly below the caller's highest role position."*

**Attack scenario (confirmed):**
1. User A has MANAGE_ROLES, highest role at position 5
2. There exists an ADMINISTRATOR role at position 8
3. User A sends `PATCH /guilds/:id/roles` with body `[{ id: "admin-role-id", position: 3 }]`
4. Check passes: target position 3 < caller's highest 5 ✅ (but role is currently at position 8, above caller!)
5. ADMINISTRATOR role is now at position 3 (below User A)
6. User A sends `PUT /guilds/:id/members/@me/roles/:adminRoleId` — assignment constraint passes (3 < 5)
7. **User A now has ADMINISTRATOR → full privilege escalation**

**Current code:**
```typescript
for (const entry of body) {
  // Only checks TARGET position, not CURRENT position
  if (entry.position >= callerHighest) {
    return missingPermissions(c);
  }
}
```

**Fix:** Add current position check for each role in the batch:
```typescript
for (const entry of body) {
  if (entry.position >= callerHighest) {
    return missingPermissions(c);
  }
  // Also check the role's CURRENT position
  if (guild.owner_id !== user.id) {
    const targetRole = roles.find(r => r.id === entry.id);
    if (targetRole && targetRole.position >= callerHighest) {
      return missingPermissions(c);
    }
  }
}
```

---

### C2. Cross-Guild Role Manipulation — Missing guild_id Validation

**File:** `repos/roles.ts` — `getById()` + all routes using it  
**Affected routes:** GET/PATCH/DELETE single role, role assignment/removal, bulk position update

**Problem:** `RolesRepo.getById(roleId)` queries `WHERE id = ?` without filtering by `guild_id`. Route handlers validate the caller's membership/permissions against the URL's `guildId`, but the role lookup doesn't verify the role belongs to that guild. In a multi-guild deployment, a user could manipulate roles from a different guild.

**Attack scenario:**
1. User in Guild A has MANAGE_ROLES with highest role at position 5
2. User sends `PATCH /guilds/guildA/roles/roleFromGuildB` with modified permissions
3. Guild membership check passes (user is in Guild A) ✅
4. MANAGE_ROLES check passes (user has it in Guild A) ✅
5. `getById(roleFromGuildB)` returns the role from Guild B (no guild filter)
6. Position check compares Guild B role against Guild A hierarchy (meaningless comparison)
7. Role from Guild B is modified

**Current code:**
```typescript
getById(roleId: string): Role | null {
  const row = this.db.prepare("SELECT * FROM roles WHERE id = ?").get(roleId);
  return row ? toRole(row) : null;
}
```

**Fix — Option A (recommended):** Add guild-scoped lookup method:
```typescript
getByIdInGuild(roleId: string, guildId: string): Role | null {
  const row = this.db.prepare("SELECT * FROM roles WHERE id = ? AND guild_id = ?")
    .get(roleId, guildId);
  return row ? toRole(row) : null;
}
```
Then use it in all routes where guildId is available from the URL params.

**Note:** Currently Cove is single-guild, so this isn't exploitable in practice. But it's a latent vulnerability that will become exploitable if multi-guild support is added.

---

## 🟠 High Issues

### H1. Gateway Dispatcher — Fail-Open Permission Check

**File:** `ws/dispatcher.ts` — `broadcastToGuildWithChannelFilter()`

**Problem:** The permission check is gated by a conjunction of null checks:
```typescript
if (guild && roles && permChannel && overwrites && this.membersRepo && session.user) {
  // Permission check runs here
} else {
  // NO CHECK — session receives the event!
}
```

If any required repo is not set (e.g., `membersRepo` or `rolesRepo`), **all sessions bypass permission filtering** and receive every event. This is a fail-open pattern. While the repos are correctly wired in `index.ts` and test setup today, any future refactor that misses a `setXxxRepo` call silently disables all permission filtering.

**Fix:** Invert the logic — fail-closed:
```typescript
if (!guild || !roles || !permChannel || !overwrites || !this.membersRepo) {
  // Cannot verify permissions — skip this session (fail-closed)
  continue;
}
if (!session.user) continue; // No user identity — skip

const member = this.membersRepo.get(guildId, session.user.id);
if (!member) continue;
const perms = computePermissions(member, permChannel, guild, roles, overwrites);
if (!(perms & VIEW_CHANNEL_BIT)) continue;

session.dispatch(event, data);
```

---

## 🟡 Medium Issues

### M1. New Roles Created at Highest Position

**File:** `repos/roles.ts` — `create()` method

New roles are assigned `position = max(existing) + 1`, placing them at the **highest** position in the guild. This diverges from Discord, which creates roles at position 1 (just above @everyone). A non-owner user with MANAGE_ROLES creates a role above their own highest position, producing a "stuck" role they can't subsequently modify, delete, or assign.

**Recommendation:** Create new roles at position 1 and shift existing roles up, or create at position just above @everyone. Alternatively, enforce the position constraint on creation too.

### M2. No Dedicated Unit Tests for computePermissions

**File:** Missing `compute.test.ts` or similar

The core security algorithm (`computeBasePermissions`, `computeOverwrites`, `computePermissions`) has no dedicated unit tests. The spec's test plan (§10) explicitly calls for *"Unit: Permission computation — test all algorithm branches (owner bypass, ADMINISTRATOR, @everyone overwrite, role overwrites combined, member overwrite precedence)."*

Existing tests verify enforcement at the HTTP level but don't directly test the algorithm's edge cases. Missing test scenarios:
- Owner bypass returns ALL_PERMISSIONS
- ADMINISTRATOR in any role → ALL_PERMISSIONS
- @everyone overwrite deny → strips bit
- Multiple role overwrites → combined with OR for allow, OR for deny
- Member overwrite → overrides role overwrites
- Role missing from roles array → gracefully skipped
- Thread → parent channel overwrite resolution

### M3. Fresh Deployment Owner Bootstrap Gap

**Files:** `db/schema.ts`, `db/migrations/v20-bootstrap-owner.ts`

On a fresh deployment:
1. `initDb` creates a guild with `owner_id = null`
2. v20 migration runs — no human members exist yet → owner stays null
3. Users join after startup → no owner is ever set (v20 only runs at startup)
4. Nobody has guild owner privileges → cannot manage roles, create channels, or modify guild settings

The @everyone defaults cover standard operations (messages, reactions), so the system is usable. But administrative operations are permanently locked until a manual database fix or server restart after the first human joins.

**Recommendation:** Set `owner_id` to the first human member who joins the guild (in the member join handler), or add logic to v20 that also runs on member join if owner is still null.

### M4. Bulk-Delete/Clear-All Missing VIEW_CHANNEL Check

**File:** `routes/messages.ts`

`POST /channels/:id/messages/bulk-delete` and `DELETE /channels/:id/messages` only require `MANAGE_MESSAGES`, not `MANAGE_MESSAGES | VIEW_CHANNEL`. A user with MANAGE_MESSAGES but denied VIEW_CHANNEL via channel overwrite could delete messages in a channel they cannot see.

```typescript
// Current:
const ch = await requireChannelPermission(repos, channelId, user.id, PermissionBits.MANAGE_MESSAGES);

// Recommended:
const ch = await requireChannelPermission(repos, channelId, user.id,
  PermissionBits.MANAGE_MESSAGES | PermissionBits.VIEW_CHANNEL);
```

### M5. Channel File Writes Only Check VIEW_CHANNEL

**File:** `routes/channel-files.ts`

PUT (create/update) and DELETE file operations only require `VIEW_CHANNEL`. Any member who can see a channel can create, modify, and delete files in it. Write operations should arguably require `SEND_MESSAGES` at minimum, and delete operations should require `MANAGE_MESSAGES` or file ownership checks.

---

## 🟢 Low Issues

### L1. Guild Webhook List Missing Permission Check

**File:** `routes/webhooks.ts` — `GET /guilds/:guildId/webhooks`

This endpoint only checks guild membership, not `MANAGE_WEBHOOKS`. Discord requires `MANAGE_WEBHOOKS` to list webhooks. Not in the spec's enforcement table, so may be intentional.

### L2. Typing Endpoint Doesn't Require VIEW_CHANNEL

**File:** `routes/messages.ts` — `POST /channels/:id/typing`

Only checks `SEND_MESSAGES`, not `SEND_MESSAGES | VIEW_CHANNEL`. Matches the spec table, but a user denied VIEW_CHANNEL shouldn't be able to trigger typing indicators in channels they can't see.

### L3. Double Permission Computation in Overwrite PUT

**File:** `routes/permissions.ts` — `PUT /channels/:channelId/permissions/:targetId`

The handler calls `requireChannelPermission()` (which computes permissions internally) and then re-computes the same permissions for the subset check. The computed value from `requireChannelPermission` is discarded. Not a bug, just wasted work.

**Suggestion:** Add a variant that returns both the channel and the computed permissions, or cache the computation.

### L4. Thread-Members Endpoint Behavior Change

**File:** `routes/threads.ts` — `GET /channels/:threadId/thread-members`

Previously returned 404 for non-thread channels; now returns 200 with an empty array. This is because `requireChannelPermission` doesn't filter by channel type. Minor behavioral change, documented in test update. Not a security issue.

---

## ✅ What's Good

### Core Algorithm — Correct
`computeBasePermissions` and `computeOverwrites` in `permissions/compute.ts` faithfully implement Discord's documented algorithm:
- Owner bypass → ALL_PERMISSIONS ✅
- @everyone base → BigInt OR accumulation ✅  
- ADMINISTRATOR shortcut → ALL_PERMISSIONS ✅
- Overwrite order: @everyone deny/allow → role deny/allow (combined) → member deny/allow ✅
- BigInt used throughout — no Number truncation for high bits ✅

### Unified Enforcement — Major Security Improvement
The replacement of the dual `requireGuildMember()` + `requireBotChannelPermission()` system with unified `requireChannelPermission()` / `requireGuildPermission()` is a significant improvement. The old system let human users bypass all permission checks (`if (!isBotUser) return true`). Now all users go through the same computation.

### Permission Check Semantics — Correct
Multi-permission checks use AND semantics: `(perms & permission) !== permission` correctly requires ALL requested bits. ✅

### Thread Handling — Correct
Thread channels (type 11) correctly resolve parent channel overwrites. Consistent across `requireChannelPermission`, dispatcher, and inline filters. ✅

### Role Hierarchy Enforcement — Mostly Correct
Single-role PATCH, DELETE, and role assignment/removal all correctly check the target role's current position against the caller's highest. Only the bulk position update is missing this check (C1).

### Managed Role Protection — Correct
Cannot modify, assign, or remove managed roles via standard API. ✅

### @everyone Protection — Correct
Cannot delete or reposition the @everyone role. ✅

### Permission Value Constraint — Correct
Role creation/modification validates that new permission values are a subset of the caller's computed permissions. Channel overwrite PUT validates both allow and deny are subsets. Guild-only bits (ADMINISTRATOR, KICK/BAN, etc.) are blocked from channel overwrites. ✅

### Migration — Solid
- v19: `CREATE TABLE IF NOT EXISTS` + `INSERT OR IGNORE` → idempotent ✅
- v20: `WHERE owner_id IS NULL` → won't overwrite existing owners ✅
- Orphaned role cleanup: LIKE pre-filter + exact JSON parse/filter → correct ✅

### Gateway Dispatcher — Human Filtering Added
The critical fix: human sessions are now filtered by VIEW_CHANNEL, closing the data leak where denied human users received all events. ✅

### Role CRUD — Complete and Correct
All Discord-parity endpoints implemented with proper hierarchy security invariants (except C1 bulk position). Gateway events emitted for all role lifecycle changes. ✅

### Idempotent Assignment — Correct
Role assignment/removal returns 204 without emitting events when no change occurs. ✅

### Transactional Cleanup — Correct
Role deletion wraps member role cleanup + overwrite cleanup + role delete in a single transaction. ✅

---

## Route Coverage Audit

| Route | Permission | Status |
|-------|-----------|--------|
| GET /channels/:id/messages | VIEW_CHANNEL | ✅ |
| GET /channels/:id/messages/:msgId | VIEW_CHANNEL | ✅ |
| POST /channels/:id/messages | SEND_MESSAGES \| VIEW_CHANNEL | ✅ |
| PATCH /channels/:id/messages/:msgId | VIEW_CHANNEL + author check | ✅ |
| DELETE /channels/:id/messages/:msgId | VIEW_CHANNEL + MANAGE_MESSAGES for others | ✅ |
| POST bulk-delete | MANAGE_MESSAGES | ⚠️ Missing VIEW_CHANNEL (M4) |
| DELETE /channels/:id/messages (clear all) | MANAGE_MESSAGES | ⚠️ Missing VIEW_CHANNEL (M4) |
| PUT ack | VIEW_CHANNEL | ✅ |
| POST typing | SEND_MESSAGES | ⚠️ Missing VIEW_CHANNEL (L2) |
| GET /guilds/:id/channels | Per-item VIEW_CHANNEL filter | ✅ |
| GET /channels/:id | VIEW_CHANNEL | ✅ |
| POST /guilds/:id/channels | MANAGE_CHANNELS (guild) | ✅ |
| PATCH /channels/:id | MANAGE_CHANNELS | ✅ |
| DELETE /channels/:id | MANAGE_CHANNELS | ✅ |
| PUT channel permissions | MANAGE_ROLES + value constraints | ✅ |
| DELETE channel permissions | MANAGE_ROLES | ✅ |
| PUT add reaction | ADD_REACTIONS \| VIEW_CHANNEL | ✅ |
| DELETE own reaction | VIEW_CHANNEL | ✅ |
| GET reactions | VIEW_CHANNEL | ✅ |
| POST create thread | CREATE_PUBLIC_THREADS \| VIEW_CHANNEL | ✅ |
| GET active threads | VIEW_CHANNEL | ✅ |
| GET archived threads | VIEW_CHANNEL | ✅ |
| GET guild active threads | Per-item VIEW_CHANNEL filter | ✅ |
| Thread join/leave/add/list members | VIEW_CHANNEL | ✅ |
| POST create webhook | MANAGE_WEBHOOKS | ✅ |
| GET channel webhooks | MANAGE_WEBHOOKS | ✅ |
| GET guild webhooks | Membership only | ⚠️ (L1) |
| GET/PATCH/DELETE webhook by id | MANAGE_WEBHOOKS | ✅ |
| Channel files (all) | VIEW_CHANNEL only | ⚠️ Writes need more (M5) |
| GET roles | Membership | ✅ |
| POST/PATCH/DELETE roles | MANAGE_ROLES + hierarchy | ✅ (except C1) |
| PUT/DELETE role assignment | MANAGE_ROLES + hierarchy | ✅ |
| PATCH guild | **Not in diff** | ❓ Unknown |
| Kick/Ban | **Not in diff** | ❓ Unknown |

**Note:** `PATCH /guilds/:guildId` and member moderation routes (kick/ban) are not in this diff. If they exist, they may still use the old enforcement system. Needs verification.

---

## Verdict

**Rating: ❌ Major Issues**

The PR is architecturally sound and the core permission algorithm is correct. However, **C1 (bulk position escalation)** is a confirmed privilege escalation path that allows any user with MANAGE_ROLES to obtain ADMINISTRATOR. This must be fixed.

**C2 (cross-guild)** is latent in the current single-guild deployment but should be fixed to prevent future vulnerabilities.

**H1 (fail-open dispatcher)** should be inverted to fail-closed.

**Required before merge:**
1. Fix C1 — add current position check in bulk position update
2. Fix C2 — scope `getById` to guild or validate guild_id in routes
3. Fix H1 — invert dispatcher null-check logic to fail-closed

**Recommended before merge:**
4. Add dedicated unit tests for computePermissions (M2)
5. Add VIEW_CHANNEL to bulk-delete/clear-all (M4)

**Can address post-merge:**
6. Role creation position (M1)
7. Owner bootstrap for fresh deployments (M3)
8. Channel file permission granularity (M5)
9. Low issues (L1–L4)
