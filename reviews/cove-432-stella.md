# 🌟 Stella's Code Review — PR #432: Server-Level Roles and Permissions

**PR:** https://github.com/kagura-agent/cove/pull/432
**Commit:** f323270
**Files:** 26 files, +1163/-288
**Reviewer:** 🌟 Stella (Security-focused)
**Date:** 2026-06-25
**Tests:** 312/312 passing, QA 23/23

---

## Verdict: ⚠️ Needs Changes

The core permission algorithm is correct and matches Discord's specification. The migration strategy is sound and the enforcement middleware is well-designed. However, there are **Critical** and **High** severity issues around missing test coverage for newly-introduced security paths, and several correctness edge cases that need attention before merging.

---

## 🔴 Critical Issues

### C1. No Unit Tests for `computePermissions` Algorithm

**File:** `packages/server/src/permissions/compute.ts` (new)
**Impact:** Security-critical — the entire permission system's correctness rests on this module

The `computePermissions`, `computeBasePermissions`, and `computeOverwrites` functions have **zero dedicated unit tests**. There is no `compute.test.ts` or equivalent. These are the most critical functions in the PR — every permission check in the system flows through them.

The spec (§10) explicitly requires: "Unit: Permission computation — test all algorithm branches (owner bypass, ADMINISTRATOR, @everyone overwrite, role overwrites combined, member overwrite precedence)."

**Must test:**
- Owner bypass → returns ALL_PERMISSIONS
- ADMINISTRATOR role → returns ALL_PERMISSIONS (both at base and overwrite level)
- @everyone base permissions (no extra roles)
- Multiple roles → permissions OR'd correctly
- @everyone channel overwrite (deny then allow ordering)
- Role-specific overwrites combined (deny/allow aggregated separately, then applied)
- Member-specific overwrite (highest priority, overrides role denies)
- Conflicting role deny + member allow → member wins
- Empty roles array → falls back to @everyone only
- Missing @everyone role in roles array → defaults to 0n (not crash)
- Thread channels → parent channel overwrites used

**Severity:** Critical (blocking) — Cannot verify algorithm correctness without tests.

---

### C2. No Tests for Role CRUD API Endpoints

**File:** `packages/server/src/routes/roles.ts` (new, 414 lines)
**Impact:** Security-critical — no test coverage for privilege escalation prevention

There is no `roles.test.ts`. The entire role CRUD API — `GET /guilds/:guildId/roles`, `POST /guilds/:guildId/roles`, `PATCH /guilds/:guildId/roles/:roleId`, `DELETE /guilds/:guildId/roles/:roleId`, bulk position update, `PUT/DELETE /guilds/:guildId/members/:userId/roles/:roleId` — has **zero dedicated integration tests**.

**Critical paths without tests:**
1. **Privilege escalation prevention:** Can a user with MANAGE_ROLES create a role with ADMINISTRATOR? (Permission value constraint §5.6)
2. **Hierarchy enforcement:** Can a user modify/delete a role at or above their highest position?
3. **Managed role immutability:** Can managed roles be modified/assigned/removed via standard API?
4. **@everyone protection:** Is the @everyone role protected from deletion?
5. **Position reordering:** Can a user move a role above their own highest position?
6. **Role assignment:** Can a user assign a role above their highest position to another member?
7. **Non-owner vs owner:** Does the owner bypass work for hierarchy constraints?

**Severity:** Critical (blocking) — Every hierarchy/permission-value constraint is a privilege escalation boundary, and none are tested.

---

### C3. No Tests for Channel Permission Overwrite Value Constraints

**File:** `packages/server/src/routes/permissions.ts`
**Impact:** Privilege escalation vector

The PR adds overwrite value constraints (§5.6 rule 4): allow/deny must be subset of caller's permissions, and guild-level bits cannot appear in channel overwrites. These are **not tested**.

**Must test:**
- User cannot set `allow` bits they don't have → 403
- User cannot set `deny` bits they don't have → 403
- ADMINISTRATOR/KICK_MEMBERS/BAN_MEMBERS/MANAGE_GUILD/VIEW_AUDIT_LOG/MANAGE_NICKNAMES in channel overwrites → 400
- Guild owner can set any overwrite values (has ALL_PERMISSIONS)

**Severity:** Critical (blocking) — Untested privilege escalation vector.

---

## 🟠 High Issues

### H1. `getHighestPosition` Returns 0 When Member Has No Assigned Roles

**File:** `packages/server/src/routes/roles.ts`, line ~30

```typescript
function getHighestPosition(memberRoles: string[], allRoles: Role[]): number {
  let max = 0; // @everyone is position 0
  for (const roleId of memberRoles) { ... }
  return max;
}
```

A guild member with no explicitly-assigned roles (only implicit @everyone at position 0) will have `max = 0`. This means the hierarchy check `targetRole.position >= callerHighest` will block them from modifying ANY role (since all non-@everyone roles have position ≥ 1), which is actually correct. However, this function is also used in position update validation:

```typescript
if (entry.position >= callerHighest) {
  return missingPermissions(c);
}
```

A member with `callerHighest = 0` cannot move any role to any position (including position 0), which is fine. But the comment `// @everyone is position 0` implies it's counting @everyone — @everyone isn't in `member.roles` (it's implicit), so the comment is misleading.

**Impact:** Misleading code, but functionally safe. Low-priority fix.

**Severity:** Suggestion

---

### H2. Role `getById` Has No Guild Scope Validation

**File:** `packages/server/src/routes/roles.ts`

In `GET /guilds/:guildId/roles/:roleId`, the code checks guild membership but then fetches the role by ID without verifying it belongs to the requested guild:

```typescript
const role = repos.roles.getById(roleId);
if (!role) return unknownRole(c);
return c.json(role);
```

A user in guild A could potentially fetch details of a role from guild B by guessing its ID. Since `getById` doesn't filter by `guild_id`, the guild check only validates that the *user* is in the specified guild, not that the *role* is.

**Fix:** Either add a `getByIdAndGuild(roleId, guildId)` method, or check `role.guild_id === guildId` after fetch. This also applies to PATCH and DELETE handlers (though those at least look up `member` in the right guild for hierarchy checks).

Wait — looking again, in PATCH and DELETE, the handler loads `repos.roles.listByGuild(guildId)` for hierarchy checks, but loads the target role via `repos.roles.getById(roleId)` without scoping to the guild. A user could theoretically delete a role from another guild if they have MANAGE_ROLES in their own guild and the target role has a lower position than their highest role.

**Impact:** Cross-guild role information disclosure and potentially cross-guild role modification.

**Severity:** High — needs guild-scope validation on `getById` calls in role routes.

---

### H3. `owner_id` Null Check in `computeBasePermissions`

**File:** `packages/server/src/permissions/compute.ts`

```typescript
if (guild.owner_id === member.user.id) {
  return ALL_PERMISSIONS;
}
```

The `Guild.owner_id` type is `string | null`. If `owner_id` is `null` and `member.user.id` is somehow also evaluated against null... well, in TypeScript `null === someString` is always false, so this is safe. However, the `initDb` function creates guilds with `owner_id: null`:

```typescript
db.prepare("INSERT INTO guilds (..., owner_id, ...) VALUES (?, ?, ?, ?, ?, ?)")
  .run(id, "Cove", null, null, now, now);
```

Migration v20 fixes this by bootstrapping owners, but if v20 fails to find a human member (empty guild), `owner_id` remains null and nobody gets owner bypass. This is a valid edge case.

**Impact:** In a guild with no human members, no one has owner permissions, so no one can manage roles. This is a chicken-and-egg problem for guilds that only have bots.

**Severity:** Medium — edge case, but worth documenting. The `initDb` function should ideally set a default owner when creating the guild.

---

### H4. Role Assignment Directly Writes to DB Instead of Using Repo

**File:** `packages/server/src/routes/roles.ts` (~line 340, 400)

```typescript
repos.db
  .prepare("UPDATE guild_members SET roles = ? WHERE guild_id = ? AND user_id = ?")
  .run(JSON.stringify(newRoles), guildId, targetUserId);
```

The role assignment/removal endpoints directly access `repos.db` to update `guild_members.roles` instead of going through `MembersRepo`. This bypasses any future encapsulation, validation, or caching in the repo layer.

**Fix:** Add `MembersRepo.updateRoles(guildId, userId, roles: string[])` method.

**Severity:** Medium — code quality / maintainability

---

### H5. `broadcastToGuildWithChannelFilter` Fails Open When Repos Are Not Set

**File:** `packages/server/src/ws/dispatcher.ts`

```typescript
if (guild && roles && permChannel && overwrites && this.membersRepo && session.user) {
  const member = this.membersRepo.get(guildId, session.user.id);
  if (member) {
    const perms = computePermissions(member, permChannel, guild, roles, overwrites);
    if (!(perms & VIEW_CHANNEL_BIT)) continue;
  } else {
    continue; // Not a member
  }
}
```

If any of `guild`, `roles`, `permChannel`, `overwrites`, or `this.membersRepo` is null/undefined, the entire permission check is **skipped** and the event is dispatched to ALL sessions in the guild. This is a fail-open design.

In the current code, all these repos are set in `index.ts`, so this should never happen in production. But if someone calls the dispatcher before repos are wired (e.g., in tests), events would be dispatched without permission checks.

**Fix:** Consider failing closed — if repos aren't available, skip the session rather than dispatching to everyone.

**Severity:** Medium — defense-in-depth. Currently mitigated by initialization order.

---

### H6. Test "human user always receives messages regardless of permissions" Is Misleading

**File:** `packages/server/src/__tests__/permissions.test.ts`, line 481

This test passes because the admin user is set as guild owner (which returns ALL_PERMISSIONS), NOT because human users bypass permission checks. The test name implies humans always receive messages regardless, which contradicts the new unified permission system.

The test should either:
1. Be renamed to "guild owner receives messages (has all permissions)"
2. Or add a test for a non-owner human WITHOUT VIEW_CHANNEL who should NOT receive messages

Without fix (2), there's no test verifying that the dispatcher correctly filters **human** sessions that lack VIEW_CHANNEL. This is a regression risk.

**Severity:** High — missing negative test for human user gateway filtering.

---

## 🟡 Medium Issues

### M1. Overwrite Value Constraint Uses Own Computed Permissions (Circular Logic Risk)

**File:** `packages/server/src/routes/permissions.ts`

```typescript
const overwriteChannelId = channel.type === 11 && channel.parent_id ? channel.parent_id : channelId;
const overwrites = repos.permissions.listByChannel(overwriteChannelId);
const callerPerms = computePermissions(member, channel, guild, roles, overwrites);

if ((allow & ~callerPerms) !== 0n || (deny & ~callerPerms) !== 0n) {
  return c.json({ message: "Missing Permissions", code: 50013 }, 403);
}
```

The caller's computed permissions **include** the existing channel overwrites — which are the overwrites being modified. This means:
- If a user already has a member-level overwrite granting MANAGE_MESSAGES, they can set role-level overwrites for MANAGE_MESSAGES (because they already have it via their own overwrite)
- If a user removes their own allow overwrite, they might lose the ability to restore it

This matches Discord's behavior (Discord also uses computed permissions for this check), so it's correct. But worth noting.

**Severity:** Informational — matches Discord, no action needed.

---

### M2. Thread Creation Requires `CREATE_PUBLIC_THREADS | VIEW_CHANNEL` for ALL Threads

**File:** `packages/server/src/routes/threads.ts`

```typescript
const channel = await requireChannelPermission(repos, channelId, user.id, 
  PermissionBits.CREATE_PUBLIC_THREADS | PermissionBits.VIEW_CHANNEL);
```

Both `POST /channels/:channelId/messages/:messageId/threads` and `POST /channels/:channelId/threads` require `CREATE_PUBLIC_THREADS`. But the spec (§5.3) says thread creation should require `CREATE_PUBLIC_THREADS or CREATE_PRIVATE_THREADS` depending on thread type. Currently there's no private thread distinction.

**Severity:** Low — acceptable for Phase A since private threads aren't implemented. Add TODO comment.

---

### M3. `DELETE /channels/:id/messages/:msgId` — MANAGE_MESSAGES Check After First Permission Check

**File:** `packages/server/src/routes/messages.ts`

```typescript
const ch = await requireChannelPermission(repos, channelId, user.id, PermissionBits.VIEW_CHANNEL);
const existing = repos.messages.getById(channelId, msgId);
if (!existing) return unknownMessage(c);

if (existing.author.id !== user.id) {
  await requireChannelPermission(repos, channelId, user.id, PermissionBits.MANAGE_MESSAGES);
}
```

This calls `requireChannelPermission` **twice** for deleting another user's message — once for VIEW_CHANNEL and once for MANAGE_MESSAGES. Each call independently loads channel → guild → member → roles → overwrites. This is functionally correct but does redundant DB queries.

**Fix:** Load permissions once and check both bits.

**Severity:** Suggestion — performance optimization.

---

### M4. Migration v19 Creates Individual SQL Queries Per Member for Orphan Cleanup

**File:** `packages/server/src/db/migrations/v19-roles.ts`

```typescript
const validRoles = roleIds.filter((roleId) => {
  return !!db.prepare("SELECT 1 FROM roles WHERE id = ?").get(roleId);
});
```

For each member with roles, each role ID triggers a separate SQL query. For large datasets, this could be slow. Using `WHERE id IN (...)` would be more efficient.

**Severity:** Suggestion — performance for migration (one-time operation).

---

### M5. `RolesRepo.delete()` Uses LIKE for Role ID Matching

**File:** `packages/server/src/repos/roles.ts`

```typescript
const members = this.db
  .prepare(`SELECT guild_id, user_id, roles FROM guild_members
           WHERE roles LIKE '%' || ? || '%'`)
  .all(roleId) as Array<...>;
```

Using `LIKE '%' || roleId || '%'` could match partial role IDs. For example, if role ID is `123`, it would match a member whose roles array contains `1234` (since the JSON `["1234"]` contains the substring `123`). The subsequent `JSON.parse` + `filter` prevents actual corruption, but the query returns false positives that waste processing.

Using `json_each` (SQLite JSON support) would be more precise, or simply scanning all members of the guild.

**Severity:** Low — functionally correct due to post-filter, but wasteful.

---

## 🟢 Suggestions

### S1. `requireChannelPermission` / `requireGuildPermission` Are Not Actually Async

Both functions are declared `async` but contain no `await` expressions. They're synchronous functions returning resolved promises. This works correctly but adds unnecessary async overhead.

**Severity:** Suggestion — minor optimization.

---

### S2. `computeOverwrites` Has Unused `_channel` Parameter

**File:** `packages/server/src/permissions/compute.ts`

The `_channel` parameter is prefixed with underscore (indicating unused), but is still a required parameter. This was presumably kept for API compatibility with the spec. Fine as-is.

**Severity:** Informational

---

### S3. Old Helpers (`requireGuildMember`, `requireBotChannelPermission`) Not Removed

**File:** `packages/server/src/routes/helpers.ts`

The old `requireGuildMember` and `requireBotChannelPermission` functions remain in the codebase. The spec (§7.2) says "Old helpers (`requireGuildMember` + `requireBotChannelPermission`) are removed entirely." Keeping them as dead code is a maintenance hazard — someone might use them instead of the new helpers.

**Severity:** Medium — dead code per spec. Should be removed (or at least deprecated with a warning).

---

### S4. `GET /guilds/:guildId/webhooks` Only Checks Membership, Not MANAGE_WEBHOOKS

**File:** `packages/server/src/routes/webhooks.ts`

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

Other webhook operations require `MANAGE_WEBHOOKS`, but listing all guild webhooks only requires membership. This matches Discord's behavior (listing requires `MANAGE_WEBHOOKS` in Discord), so this might be an oversight.

**Severity:** Medium — potential information disclosure. Check if this matches intended behavior.

---

## ✅ What's Done Well

### Algorithm Correctness ✅
The `computePermissions` algorithm exactly matches Discord's documented algorithm:
- Owner bypass → ALL_PERMISSIONS
- @everyone base → OR'd role permissions → ADMINISTRATOR check → ALL_PERMISSIONS
- Channel overwrites: @everyone overwrite → combined role overwrites → member overwrite
- Deny applied before allow at each stage (correct: `&= ~deny; |= allow`)
- Role overwrites correctly aggregated (combined deny, combined allow, then applied)
- BigInt used throughout — no Number truncation risk for 64-bit permission values

### Migration Strategy ✅
- v19: Creates roles table, seeds @everyone, cleans orphans — all idempotent (`CREATE TABLE IF NOT EXISTS`, `INSERT OR IGNORE`)
- v20: Bootstraps guild owner from first human member — handles the chicken-and-egg problem
- Default @everyone permissions are generous enough to not break existing workflows
- Atomic deployment: no dangerous intermediate states

### Permission Enforcement Architecture ✅
- `requireChannelPermission` and `requireGuildPermission` use HTTPException throws — clean pattern that works with Hono's error handling
- Thread channels correctly resolve parent channel for overwrites
- Multi-permission checks use AND semantics with bitwise OR (`SEND_MESSAGES | VIEW_CHANNEL`)
- Both bot and human sessions go through identical permission paths — no more `if (user.bot)` branching

### Gateway Dispatcher ✅
- Human sessions now correctly filtered by VIEW_CHANNEL (was a data leak before)
- Pre-loads guild data once per broadcast (guild, roles, channel, overwrites), then per-session only loads member — good performance pattern
- Role lifecycle events use `broadcastToGuild` (no channel filtering) — correct, matches Discord

### Role CRUD Security ✅
- Hierarchy enforcement: position checks on create/modify/delete/assign
- Permission value constraints: new permissions must be subset of caller's
- @everyone immutable: can't delete, position locked at 0
- Managed roles: can't modify/assign/remove via API
- Guild owner bypass: correctly exempted from hierarchy constraints
- Idempotent role assignment/removal: no duplicate events

### Channel Overwrite Security ✅
- Guild-level bits (ADMINISTRATOR, KICK_MEMBERS, etc.) blocked from channel overwrites
- Overwrite values must be subset of caller's computed permissions
- MANAGE_ROLES now required for PUT/DELETE overwrites (was unrestricted for humans before)

---

## Summary of Required Changes

| # | Severity | Issue | Action |
|---|---|---|---|
| C1 | Critical | No unit tests for `computePermissions` | Add comprehensive unit test suite |
| C2 | Critical | No tests for role CRUD API | Add integration tests for all hierarchy/escalation paths |
| C3 | Critical | No tests for overwrite value constraints | Add tests for privilege escalation via overwrites |
| H2 | High | Cross-guild role access via `getById` | Add guild-scope validation |
| H6 | High | No test for human gateway filtering | Add negative test for non-owner human without VIEW_CHANNEL |
| H5 | Medium | Dispatcher fails open when repos not set | Consider fail-closed design |
| S3 | Medium | Old helpers not removed per spec | Remove dead code |
| S4 | Medium | Guild webhook list lacks permission check | Add MANAGE_WEBHOOKS or document exception |

The security architecture and algorithm are solid. The primary blocker is **test coverage** — this is a security-critical permission system shipping without tests for its core algorithm or its API enforcement boundaries. Once C1-C3 are addressed, this PR will be in excellent shape.
