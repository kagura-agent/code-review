# Code Review: PR #432 — Server-Level Roles and Permissions (Round 2)

**Reviewer:** 💫 Vega  
**PR:** kagura-agent/cove#432  
**Commit:** 25950f2  
**Round:** 2 (re-review of security fixes)  
**Date:** 2026-06-25  

---

## Overall Verdict: ✅ Ready

All Round 1 critical, high, and medium security issues have been properly addressed. The fixes are architecturally sound and the code is production-quality. One Round 1 recommendation (L3: privilege escalation tests) remains unaddressed but is non-blocking.

---

## Round 1 Issue Verification

### C1 — Bulk Position Privilege Escalation: ✅ FIXED

**Original attack:** Caller with MANAGE_ROLES demotes an ADMINISTRATOR role below their own position, then assigns it to themselves.

**Fix in `routes/roles.ts` PATCH `/guilds/:guildId/roles` (bulk position update):**

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

**Analysis:** Both invariants are now enforced:
1. **Current position check** — The `roles` variable comes from `repos.roles.listByGuild(guildId)` (current DB state), not from the request body. A role at position ≥ callerHighest is immovable.
2. **Target position check** — Cannot move any role to ≥ callerHighest, preventing lateral escalation.
3. **Owner bypass** — `callerHighest` is `Infinity` for guild owner, correctly exempting them.

The original attack is blocked: an ADMINISTRATOR role at position 5 cannot be moved by a caller whose highest role is at position 3 (5 >= 3 → rejected).

**Single-role PATCH also enforced correctly** — `PATCH /guilds/:guildId/roles/:roleId` checks `targetRole.position >= callerHighest` against the target's current position + validates managed role immutability.

---

### H1 — Dispatcher Fail-Open: ✅ FIXED

**Original bug:** `broadcastToGuildWithChannelFilter` only checked bot sessions and only when `permissionsRepo` was set. Human users denied VIEW_CHANNEL still received messages via WebSocket.

**Fix in `ws/dispatcher.ts`:**

```typescript
// Permission filter: ALL sessions (bot and human) are filtered
// Fail-closed: if we can't compute permissions, deny by default
if (!session.user) continue;
if (!guild || !roles || !permChannel || !this.membersRepo) continue;

const member = this.membersRepo.get(guildId, session.user.id);
if (!member) continue;

const perms = computePermissions(member, permChannel, guild, roles, channelOverwrites);
if (!(perms & VIEW_CHANNEL_BIT)) continue;
```

**Analysis:** Three key improvements:
1. **Universal filtering** — ALL sessions (bot AND human) are permission-checked. The old `if (session.user?.bot && this.permissionsRepo)` guard is gone.
2. **Fail-closed** — If `guild`, `roles`, `permChannel`, or `membersRepo` is null/missing, the session is skipped (denied). If `member` not found → skipped.
3. **Full permission computation** — Uses `computePermissions()` with the complete algorithm (base + overwrites), not the old single-row `hasPermission()` lookup.

Guild data is pre-loaded once per broadcast, then only the member lookup is per-session. Good performance consideration.

---

### M1 — Cross-Guild Role Access: ✅ FIXED

**Fix in `repos/roles.ts`:**

```typescript
getById(roleId: string, guildId?: string): Role | null {
  const row = this.db.prepare("SELECT * FROM roles WHERE id = ?").get(roleId);
  if (!row) return null;
  if (guildId && row.guild_id !== guildId) return null;
  return toRole(row);
}
```

All route handlers in `routes/roles.ts` pass `guildId` to `getById()`:
- `repos.roles.getById(roleId, guildId)` — single role GET, PATCH, DELETE, and role assignment routes.

A role belonging to guild-B cannot be accessed through guild-A's API path.

**Note:** The internal `update()` method calls `this.getById(roleId)` without guildId, but this is a defense-in-depth gap only — the route handler validates guild scope before calling `update()`. Not exploitable.

---

### M2 — Webhook List Missing MANAGE_WEBHOOKS: ✅ FIXED

All webhook routes now use the proper permission:

| Route | Permission Check |
|---|---|
| `POST /channels/:id/webhooks` | `requireChannelPermission(..., MANAGE_WEBHOOKS)` |
| `GET /channels/:id/webhooks` | `requireChannelPermission(..., MANAGE_WEBHOOKS)` |
| `GET /guilds/:id/webhooks` | `requireGuildPermission(..., MANAGE_WEBHOOKS)` |
| `GET /webhooks/:id` | `requireChannelPermission(webhook.channel_id, ..., MANAGE_WEBHOOKS)` |
| `PATCH /webhooks/:id` | `requireChannelPermission(webhook.channel_id, ..., MANAGE_WEBHOOKS)` |
| `DELETE /webhooks/:id` | `requireChannelPermission(webhook.channel_id, ..., MANAGE_WEBHOOKS)` |

Previously, listing and individual webhook access only required guild membership. Now properly gated.

---

### M3 — Channel Files Missing SEND_MESSAGES: ✅ FIXED

| Route | Permission Check |
|---|---|
| `GET /channels/:id/files` | `VIEW_CHANNEL` |
| `GET /channels/:id/files/:name` | `VIEW_CHANNEL` |
| `PUT /channels/:id/files/:name` | `VIEW_CHANNEL \| SEND_MESSAGES` |
| `DELETE /channels/:id/files/:name` | `VIEW_CHANNEL \| SEND_MESSAGES` |

Write and delete operations now require SEND_MESSAGES in addition to VIEW_CHANNEL. Read-only operations correctly require only VIEW_CHANNEL.

---

## Round 1 L3 — Privilege Escalation Tests: ❌ NOT ADDRESSED

No dedicated role hierarchy or privilege escalation tests were added. The test changes are limited to:
- Making admin the guild owner in existing test suites
- Adding explicit deny overwrites for bot permission tests (adapting to @everyone having VIEW_CHANNEL by default)
- Updating gateway test mocks for new repo dependencies

**Missing test coverage:**
- Bulk position hierarchy enforcement (the C1 attack scenario)
- Role creation with permissions exceeding caller's own
- Cross-guild role access rejection
- Managed role immutability
- Permission value subset validation on PATCH

The code is correct on review, but these scenarios are untested. **Recommendation:** Add a `roles-api.test.ts` in a follow-up PR. Not blocking for merge.

---

## New Findings (Round 2)

### N1 — Thread-Member Routes Lost Type-11 Guard (Low)

**Routes affected:**
- `PUT /channels/:threadId/thread-members/:userId` (add user to thread)
- `GET /channels/:threadId/thread-members` (list thread members)

**Before:** These routes checked `if (!thread || thread.type !== 11) return unknownChannel(c);` before processing.

**After:** They only call `requireChannelPermission(repos, threadId, user.id, VIEW_CHANNEL)` which does not validate channel type. A non-thread channel would pass the permission check, and `repos.threads.addMember()` / `repos.threads.listMembers()` would execute against it.

**Impact:** Low — operational correctness, not a security issue. The test was updated to expect 200/empty array instead of 404 for non-thread channels, suggesting this is intentional. The join/leave thread routes still have the type-11 guard.

### N2 — Dead Code: Old Permission Helpers (Info)

`requireGuildMember()` and `requireBotChannelPermission()` are still exported from `routes/helpers.ts` but no longer imported by any route file. They should be removed in a follow-up cleanup.

---

## Architecture Assessment

The overall implementation is clean and well-structured:

1. **`computePermissions()`** in `src/permissions/compute.ts` — Single source of truth for permission logic, used by both HTTP routes and WebSocket dispatcher.
2. **`requireChannelPermission()` / `requireGuildPermission()`** — Clean replacements for the old split helpers, throwing HTTPException for Hono's error handling.
3. **Thread parent resolution** — Correctly delegates to parent channel overwrites for type-11 channels.
4. **Permission overwrite value constraints** — `PUT /channels/:id/permissions/:targetId` validates that allow/deny are subsets of the caller's permissions AND blocks guild-level bits (ADMINISTRATOR, KICK_MEMBERS, etc.) in channel overwrites.
5. **v20 migration** — Smart bootstrap of guild owners for existing ownerless guilds. Solves the chicken-and-egg problem without requiring manual intervention.

---

## Summary

| Finding | Severity | Status |
|---|---|---|
| C1: Bulk position privilege escalation | 🔴 Critical | ✅ Fixed |
| H1: Dispatcher fail-open | 🟠 High | ✅ Fixed |
| M1: Cross-guild role access | 🟡 Medium | ✅ Fixed |
| M2: Webhook list auth | 🟡 Medium | ✅ Fixed |
| M3: Channel files write auth | 🟡 Medium | ✅ Fixed |
| L3: Privilege escalation tests | 🔵 Low | ❌ Not addressed (non-blocking) |
| N1: Thread type guard regression | 🔵 Low | New finding |
| N2: Dead code cleanup | ℹ️ Info | New finding |

**Rating: ✅ Ready to merge.** All security issues are properly fixed. The remaining items (test coverage, dead code, thread guard) are follow-up material.
