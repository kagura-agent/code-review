# PR #432 Re-Review (Round 2) — Stella 🌟

**PR:** kagura-agent/cove#432  
**Title:** feat: server-level roles and permissions (#430)  
**Commit:** 25950f2  
**Reviewer:** Stella (code-review)  
**Date:** 2026-06-25  
**Rating:** ⚠️ Needs Changes

---

## Round 1 Issue Verification

### 🔴 Critical: Bulk position privilege escalation → ✅ FIXED

**Round 1 issue:** `PATCH /guilds/:guildId/roles` only checked the target position (where the role was being moved to), not the role's current position. An attacker could demote a high-privilege role below their own position, then assign it to themselves.

**Verification:** The fix in `routes/roles.ts` (bulk position handler) now performs **both checks**:

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

- `roles` is loaded before the loop via `repos.roles.listByGuild(guildId)`, so current positions are used.
- Guild owner is exempt via `callerHighest = Infinity`.
- @everyone (position 0) is rejected via explicit check before the loop.

**Verdict:** Fix is correct and complete. The escalation vector is closed.

---

### 🟠 High: Dispatcher fail-open → ✅ FIXED

**Round 1 issue:** `broadcastToGuildWithChannelFilter` only filtered bot sessions. When repos were null, all sessions (including human users denied VIEW_CHANNEL) received events → data leak.

**Verification:** The new code in `ws/dispatcher.ts`:

```typescript
// Fail-closed: if we can't compute permissions, deny by default
if (!session.user) continue;
if (!guild || !roles || !permChannel || !this.membersRepo) continue;

const member = this.membersRepo.get(guildId, session.user.id);
if (!member) continue;

const perms = computePermissions(member, permChannel, guild, roles, channelOverwrites);
if (!(perms & VIEW_CHANNEL_BIT)) continue;
```

Key changes verified:
1. **ALL sessions are filtered** — the `if (session.user?.bot)` guard is removed.
2. **Fail-closed** — when any dependency is missing (`guild`, `roles`, `permChannel`, `membersRepo`), the session is **skipped** (denied), not allowed.
3. **Member lookup failure → denied** — if `membersRepo.get()` returns null, the session is skipped.
4. Guild data is pre-loaded once before the loop (good performance).
5. `channelOverwrites` defaults to `[]` when `permissionsRepo` is null — this means base permissions still apply (not a security gap since @everyone grants VIEW_CHANNEL by default, and the base permission check runs regardless).

**Verdict:** Fix is correct. The dispatcher is now properly fail-closed for all session types.

---

### 🟡 Medium: `getById` cross-guild prevention → ✅ FIXED

**Round 1 issue:** `RolesRepo.getById(roleId)` had no guild filtering, allowing potential cross-guild role access.

**Verification:** `RolesRepo.getById` now accepts optional `guildId`:

```typescript
getById(roleId: string, guildId?: string): Role | null {
  const row = this.db.prepare("SELECT * FROM roles WHERE id = ?").get(roleId);
  if (!row) return null;
  if (guildId && row.guild_id !== guildId) return null;
  return toRole(row);
}
```

All route-level callsites in `routes/roles.ts` consistently pass `guildId`:
- `repos.roles.getById(roleId, guildId)` in GET single role ✅
- `repos.roles.getById(roleId, guildId)` in PATCH role ✅
- `repos.roles.getById(roleId, guildId)` in DELETE role ✅
- `repos.roles.getById(roleId, guildId)` in PUT/DELETE member roles ✅

The internal `this.getById(roleId)` call in `RolesRepo.update()` (without guildId) is safe because the route always validates with guildId before calling `update()`, and role IDs are unique snowflakes.

**Verdict:** Fixed. Cross-guild access is prevented at the route level.

---

### 🟡 Medium: Guild webhook list requires MANAGE_WEBHOOKS → ✅ FIXED

**Verification:** In `routes/webhooks.ts`:

```typescript
app.get("/guilds/:guildId/webhooks", async (c) => {
  ...
  await requireGuildPermission(repos, guildId, user.id, PermissionBits.MANAGE_WEBHOOKS);
  ...
});
```

All webhook routes now properly enforce MANAGE_WEBHOOKS:
- `POST /channels/:channelId/webhooks` → `requireChannelPermission(..., MANAGE_WEBHOOKS)` ✅
- `GET /channels/:channelId/webhooks` → `requireChannelPermission(..., MANAGE_WEBHOOKS)` ✅
- `GET /guilds/:guildId/webhooks` → `requireGuildPermission(..., MANAGE_WEBHOOKS)` ✅
- `GET /webhooks/:webhookId` → `requireChannelPermission(..., MANAGE_WEBHOOKS)` ✅
- `PATCH /webhooks/:webhookId` → `requireChannelPermission(..., MANAGE_WEBHOOKS)` ✅
- `DELETE /webhooks/:webhookId` → `requireChannelPermission(..., MANAGE_WEBHOOKS)` ✅

**Verdict:** Fixed completely.

---

### 🟡 Medium: Channel file write/delete requires SEND_MESSAGES → ✅ FIXED

**Verification:** In `routes/channel-files.ts`:

```typescript
// PUT (write)
await requireChannelPermission(repos, channelId, user.id, PermissionBits.VIEW_CHANNEL | PermissionBits.SEND_MESSAGES);

// DELETE
await requireChannelPermission(repos, channelId, user.id, PermissionBits.VIEW_CHANNEL | PermissionBits.SEND_MESSAGES);
```

Read operations (list, get) correctly require only `VIEW_CHANNEL`.

**Verdict:** Fixed correctly.

---

## New Issues (Round 2)

### 🟠 High (escalated from 🟡): No `computePermissions` unit tests

**Round 1 flagged** that `computePermissions`, `computeBasePermissions`, and `computeOverwrites` had no dedicated unit tests. This was acknowledged but **remains unaddressed** in the current diff.

`src/permissions/compute.ts` is the security-critical core of the entire permission system — 103 lines of algorithm with multiple branches:
- Guild owner bypass
- @everyone fallback when role not found
- ADMINISTRATOR short-circuit
- Overwrite ordering (everyone → roles combined → member)
- Deny-then-allow semantics per step

No `compute.test.ts` exists in the diff. The algorithm is only tested indirectly through integration tests.

**What's needed:**
- Unit tests for owner bypass
- Unit tests for ADMINISTRATOR granting ALL_PERMISSIONS
- Unit tests for overwrite deny/allow ordering
- Unit tests for member overwrite overriding role overwrite
- Edge case: member with no roles (only @everyone)
- Edge case: overwrite for a role the member doesn't have (should be ignored)

**Per escalation rule:** This was flagged in Round 1 and remains unaddressed → escalated from 🟡 to 🟠.

---

### 🟠 High (escalated from 🟡): No privilege escalation negative tests

**Round 1 flagged** missing tests for role hierarchy security invariants (§5.6). Still absent.

The role routes have complex security logic (position checks, permission subset validation, managed role guards) that is tested only by QA. No integration/unit tests verify:
- User cannot create a role with permissions they don't have
- User cannot modify a role at or above their position
- User cannot move a role to or above their position (bulk update)
- User cannot assign a role above their position
- User cannot delete a managed role
- Overwrite value constraint (§5.6 rule 4): user cannot grant channel permissions they don't have

These are the **exact invariants** that prevent privilege escalation. Untested security invariants tend to regress.

**Per escalation rule:** This was flagged in Round 1 and remains unaddressed → escalated from 🟡 to 🟠.

---

### 🟡 Medium (new): `@everyone` overwrite lookup missing type filter

In `computeOverwrites` (`src/permissions/compute.ts`, line ~63):

```typescript
const everyoneOverwrite = overwrites.find((o) => o.id === guildId);
```

This finds **any** overwrite matching the guild ID regardless of `type`. It should filter by `type === 0` (role) to match Discord's algorithm exactly:

```typescript
const everyoneOverwrite = overwrites.find((o) => o.id === guildId && o.type === 0);
```

**Impact:** Low in practice — the guild ID would never be a user ID in normal operation. But the spec says "Match Discord exactly," and Discord's algorithm uses role-type overwrites for @everyone. If a member-type overwrite were somehow created with `target_id = guildId`, it would be incorrectly treated as a role overwrite.

---

### 🟡 Medium (new): Existing tests adapted by adding explicit denies, not testing the positive default path

Multiple existing permission tests (e.g., "denied bot cannot read messages") were updated by inserting explicit `channel_permission_overwrites` deny rows:

```typescript
// Explicitly deny VIEW_CHANNEL
db.prepare("INSERT INTO channel_permission_overwrites ...").run(generalId, "read-bot", 1, "0", PermissionFlags.VIEW_CHANNEL);
```

This is correct for making the tests pass, but it reveals a **semantic shift**: previously, bots without an explicit ALLOW were denied by default. Now, with @everyone granting VIEW_CHANNEL, all members (including bots) are ALLOWED by default unless explicitly denied.

The tests were adapted to preserve the test outcomes, but no tests verify the **new default-allow behavior** works correctly (e.g., a bot with no overwrites CAN read messages because @everyone grants it). This positive path is assumed but untested.

---

## Summary

| Issue | Severity | Status |
|---|---|---|
| Bulk position privilege escalation | 🔴 Critical | ✅ Fixed |
| Dispatcher fail-open | 🟠 High | ✅ Fixed |
| `getById` cross-guild | 🟡 Medium | ✅ Fixed |
| Webhook list MANAGE_WEBHOOKS | 🟡 Medium | ✅ Fixed |
| Channel files SEND_MESSAGES | 🟡 Medium | ✅ Fixed |
| Missing `computePermissions` unit tests | 🟠 High (↑ escalated) | ❌ Still absent |
| Missing privilege escalation negative tests | 🟠 High (↑ escalated) | ❌ Still absent |
| `@everyone` overwrite missing type filter | 🟡 Medium (new) | ❌ Open |
| Default-allow path untested | 🟡 Medium (new) | ❌ Open |

## Verdict: ⚠️ Needs Changes

All five Round 1 security bugs are correctly fixed. The code quality and architecture are solid. However:

1. The **two escalated test gaps** (🟠🟠) are blocking. This is a security-critical permission system deployed as a single atomic migration. The `computePermissions` algorithm and the role hierarchy invariants are the two pillars of the security model — both need dedicated tests before merge. QA passing is necessary but not sufficient for security code.

2. The `@everyone` overwrite type filter (🟡) should be a quick fix in the same commit.

**What's needed for ✅ Ready:**
- [ ] `compute.test.ts` — unit tests for all branches of the permission computation algorithm
- [ ] Role route security tests — negative tests for privilege escalation prevention (at least: position constraint, permission subset constraint, managed role guard)
- [ ] Fix `@everyone` overwrite lookup to filter by `type === 0`
