# Code Review: PR #432 — Server-Level Roles and Permissions (Round 2)

**Reviewer:** 🌠 Nova
**PR:** https://github.com/kagura-agent/cove/pull/432
**Commit:** `25950f2`
**Round:** 2 (re-review of security fixes)
**Tests:** 312/312 pass, QA 23/23
**Rating:** ✅ Ready

---

## Round 1 Issue Verification

### 🔴 C1: Bulk Position Privilege Escalation — ✅ FIXED

**Original issue:** `PATCH /guilds/:guildId/roles` only checked target position, not current. An attacker could demote an ADMINISTRATOR role to position 0, then assign it to themselves for full escalation.

**Verification:** In `routes/roles.ts`, the bulk position handler now checks BOTH:

```typescript
// Check CURRENT position: cannot move a role currently at or above caller's highest
const targetRole = roles.find((r) => r.id === entry.id);
if (targetRole && targetRole.position >= callerHighest) {
  return missingPermissions(c);
}
// Cannot move a role to or above caller's highest position
if (entry.position >= callerHighest) {
  return missingPermissions(c);
}
```

The attack scenario is fully blocked: an attacker cannot demote a high-position role because the CURRENT position check (`targetRole.position >= callerHighest`) rejects it before any position change is applied. The `roles` list is loaded once pre-validation, and `updatePositions` runs in a transaction, preventing TOCTOU races. Non-existent role IDs are harmlessly ignored via `WHERE id = ? AND guild_id = ?`.

**Verdict:** Attack vector eliminated. Fix is correct and complete.

---

### 🔴 C2: Cross-Guild Role Access — ✅ FIXED

**Original issue:** `RolesRepo.getById` didn't take `guildId`, allowing cross-guild role access.

**Verification:** `getById` now accepts an optional `guildId` parameter and rejects mismatches:

```typescript
getById(roleId: string, guildId?: string): Role | null {
  const row = this.db.prepare("SELECT * FROM roles WHERE id = ?").get(roleId);
  if (!row) return null;
  if (guildId && row.guild_id !== guildId) return null;
  return toRole(row);
}
```

All route-level callsites pass `guildId`:
- `GET /guilds/:guildId/roles/:roleId` → `getById(roleId, guildId)` ✅
- `PATCH /guilds/:guildId/roles/:roleId` → `getById(roleId, guildId)` ✅
- `DELETE /guilds/:guildId/roles/:roleId` → `getById(roleId, guildId)` ✅
- `PUT .../roles/:roleId` (assign) → `getById(roleId, guildId)` ✅
- `DELETE .../roles/:roleId` (remove) → `getById(roleId, guildId)` ✅

**Note:** The internal `update()` method calls `this.getById(roleId)` without `guildId`, but this is only invoked after the route handler has already validated guild membership. Not exploitable, though making `guildId` required at the type level would be more defensive.

**Verdict:** Cross-guild role access is blocked at all external-facing callsites.

---

### 🟠 H1: Dispatcher Fail-Open — ✅ FIXED

**Original issue:** `broadcastToGuildWithChannelFilter` skipped permission checks when `permissionsRepo` was null (fail-open), and only filtered bot sessions while humans passed unconditionally.

**Verification:** The dispatcher now uses proper fail-closed logic that applies to ALL sessions:

```typescript
// Fail-closed: if we can't compute permissions, deny by default
if (!session.user) continue;
if (!guild || !roles || !permChannel || !this.membersRepo) continue;

const member = this.membersRepo.get(guildId, session.user.id);
if (!member) continue;

const perms = computePermissions(member, permChannel, guild, roles, channelOverwrites);
if (!(perms & VIEW_CHANNEL_BIT)) continue;
```

Three critical improvements:
1. **Fail-closed:** Any null dependency (guild, roles, permChannel, membersRepo) → session denied.
2. **Universal filtering:** The old `if (session.user?.bot && ...)` guard is gone — ALL sessions (human and bot) are permission-checked.
3. **Full computation:** Uses the complete `computePermissions` algorithm with channel overwrites, not the old `hasPermission` single-row lookup.

Gateway tests are updated with proper mock repos verifying the new behavior.

**Verdict:** The data leak via WebSocket for denied users is eliminated.

---

### 🟡 M1: New Roles Created at Position 0 — ✅ FIXED

**Original issue:** New roles were created at position 0 (same as @everyone), breaking the hierarchy.

**Verification:** In `repos/roles.ts`:
```typescript
const maxPos = this.db
  .prepare("SELECT MAX(position) as max_pos FROM roles WHERE guild_id = ?")
  .get(guildId);
const position = (maxPos.max_pos ?? 0) + 1;
```

New roles are always created at `max(existing positions) + 1`, placing them at the top of the hierarchy. This matches the spec's "position = max(existing positions) + 1" requirement.

**Verdict:** Fixed correctly.

---

### 🟡 M3: Fresh Deploy Owner Gap — ⚠️ PARTIALLY FIXED

**Original issue:** On fresh deploy, `owner_id` is null, so nobody can manage roles (no owner bypass, nobody has MANAGE_ROLES).

**Verification:** Migration `v20-bootstrap-owner.ts` sets the first human member as owner for guilds with null `owner_id`:

```typescript
const ownerlessGuilds = db
  .prepare("SELECT id FROM guilds WHERE owner_id IS NULL")
  .all();
for (const guild of ownerlessGuilds) {
  const firstHuman = db.prepare(
    "SELECT gm.user_id FROM guild_members gm JOIN users u ON u.id = gm.user_id WHERE gm.guild_id = ? AND u.bot = 0 ORDER BY gm.joined_at ASC LIMIT 1"
  ).get(guild.id);
  if (firstHuman) {
    db.prepare("UPDATE guilds SET owner_id = ? WHERE id = ?").run(firstHuman.user_id, guild.id);
  }
}
```

This correctly fixes **existing deployments** where members already exist but owner_id was null.

**Residual gap:** For **brand-new deployments**, `initDb` creates the default guild with `owner_id = null` AFTER v20 has already run (no members exist yet). The first user to join will have @everyone permissions (VIEW_CHANNEL, SEND_MESSAGES, etc.) but no MANAGE_ROLES capability. An admin must manually `UPDATE guilds SET owner_id = '...'` in the database.

**Assessment:** This is an operational bootstrap concern, not a security vulnerability. The @everyone defaults cover all standard operations. Only role management is locked out until owner is set. Acceptable for a self-hosted platform where the deployer has DB access.

---

### 🟡 M4: Bulk-Delete/Clear-All VIEW_CHANNEL — ℹ️ SPEC-CORRECT

**Original issue:** `POST /channels/:id/messages/bulk-delete` and `DELETE /channels/:id/messages` didn't check VIEW_CHANNEL.

**Current code:**
```typescript
// bulk-delete
await requireChannelPermission(repos, channelId, user.id, PermissionBits.MANAGE_MESSAGES);
// clear-all
await requireChannelPermission(repos, channelId, user.id, PermissionBits.MANAGE_MESSAGES);
```

The spec table explicitly lists only `MANAGE_MESSAGES` for bulk-delete, matching Discord's API behavior. A user denied VIEW_CHANNEL can't retrieve message IDs via GET, so they can't construct a valid bulk-delete request in practice.

**Assessment:** Spec-correct. Adding `VIEW_CHANNEL` would be defense-in-depth but is not required.

---

### 🟡 Webhook List MANAGE_WEBHOOKS — ✅ FIXED

Both `GET /channels/:channelId/webhooks` and `GET /guilds/:guildId/webhooks` now require MANAGE_WEBHOOKS.

### 🟡 Channel Files SEND_MESSAGES — ✅ FIXED

`PUT` (write) and `DELETE` channel files now require `VIEW_CHANNEL | SEND_MESSAGES`.

---

## New Code Quality Review

### Permission Computation (`permissions/compute.ts`)

The computation algorithm is a correct implementation of Discord's documented algorithm:
- Guild owner → ALL_PERMISSIONS ✅
- @everyone base permissions → OR with role permissions ✅  
- ADMINISTRATOR → ALL_PERMISSIONS bypass ✅
- Channel overwrites: @everyone → role (combined OR/AND) → member (override) ✅
- Thread channels use parent channel's overwrites ✅

### Route Enforcement Completeness

All routes in the spec table are properly enforced:

| Route | Permission | Status |
|---|---|---|
| GET messages | VIEW_CHANNEL | ✅ |
| POST messages | SEND_MESSAGES \| VIEW_CHANNEL | ✅ |
| PATCH message | VIEW_CHANNEL (+ author check) | ✅ |
| DELETE message | VIEW_CHANNEL (+ MANAGE_MESSAGES for others) | ✅ |
| bulk-delete | MANAGE_MESSAGES | ✅ |
| clear-all | MANAGE_MESSAGES | ✅ |
| ack | VIEW_CHANNEL | ✅ |
| typing | SEND_MESSAGES | ✅ |
| PATCH channel | MANAGE_CHANNELS | ✅ |
| DELETE channel | MANAGE_CHANNELS | ✅ |
| POST guild channels | MANAGE_CHANNELS | ✅ |
| GET guild channels | per-item VIEW_CHANNEL filter | ✅ |
| PUT/DELETE channel permissions | MANAGE_ROLES + value constraint | ✅ |
| Roles CRUD | MANAGE_ROLES + hierarchy | ✅ |
| Role assignment | MANAGE_ROLES + hierarchy | ✅ |
| Webhooks | MANAGE_WEBHOOKS | ✅ |
| Reactions | ADD_REACTIONS \| VIEW_CHANNEL | ✅ |
| Channel files read | VIEW_CHANNEL | ✅ |
| Channel files write/delete | VIEW_CHANNEL \| SEND_MESSAGES | ✅ |
| Threads | CREATE_PUBLIC_THREADS \| VIEW_CHANNEL | ✅ |
| Guild active threads | per-item VIEW_CHANNEL filter | ✅ |

### Permission Overwrite Value Constraint (`permissions.ts`)

The overwrite route correctly implements §5.6 rule 4:
1. Guild-only bits (ADMINISTRATOR, KICK_MEMBERS, etc.) rejected in channel overwrites → returns 400 ✅
2. Allow/deny values must be subset of caller's computed permissions → returns 403 ✅

### Role Hierarchy Security (`roles.ts`)

All hierarchy invariants are properly enforced:
1. Position constraint: target role position < caller's highest (owner exempt) ✅
2. Permission value constraint: new permissions ⊆ caller's permissions ✅
3. Assignment constraint: role position < caller's highest ✅
4. Managed role immutability: create/modify/assign/remove all blocked ✅
5. @everyone protection: cannot delete, cannot change position ✅

### Migration Safety

- `v19-roles`: Idempotent (`CREATE TABLE IF NOT EXISTS`, `INSERT OR IGNORE`), cleans orphaned role IDs ✅
- `v20-bootstrap-owner`: Only affects guilds with null owner_id ✅
- Schema: @everyone role auto-created on guild creation ✅

---

## Minor Observations (Non-Blocking)

1. **`RolesRepo.getById` optional guildId:** Making `guildId` required (separate `getByIdUnsafe` for internal use) would be more defensive. Currently safe because all routes pass it.

2. **Thread-members returns 200 instead of 404 for non-thread channels:** Behavioral change from previous version. `requireChannelPermission` doesn't verify channel type, so `GET /channels/:channelId/thread-members` on a regular channel returns `[]` instead of 404. Minor info-leak about channel existence.

3. **Double permission computation on delete-other-message:** `requireChannelPermission` is called twice (once for VIEW_CHANNEL, once for MANAGE_MESSAGES). Could compute once and check both bits conditionally. Performance only — not a correctness issue.

---

## Verdict

**Rating: ✅ Ready**

All critical and high-severity Round 1 findings are properly fixed:
- **C1 (Bulk position escalation):** Both current AND target position checked. Attack eliminated.
- **C2 (Cross-guild):** Guild-scoped at all external callsites.
- **H1 (Dispatcher fail-open):** Fail-closed, universal filtering, full permission computation.
- **M1 (Role position):** New roles at max+1.
- **M3 (Owner gap):** Migration handles existing deployments. Fresh deploy bootstrap documented as operational concern.
- **Webhooks/Channel files/Bulk-delete:** All enforced per spec.

The permission system is well-architected: clean separation (compute module → helpers → route handlers → dispatcher), correct Discord algorithm implementation, comprehensive enforcement across all routes, and proper test coverage. The security model is sound.

The fresh deploy owner bootstrap gap (M3 residual) is an operational concern that doesn't pose a security risk — it prevents role management until owner is set, which is fail-safe behavior.
