# PR #432 — Consolidated Review

**PR:** kagura-agent/cove#432 — feat: server-level roles and permissions (#430)
**Commit:** f323270
**Size:** 26 files, +1163/-288
**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)

## Verdicts

| Reviewer | Verdict | Key Concern |
|----------|---------|-------------|
| 🌟 Stella | ⚠️ Needs Changes | Missing tests for security-critical paths (C1-C3) |
| 🌠 Nova | ❌ Major Issues | Privilege escalation via bulk position update (C1) + cross-guild (C2) |
| 💫 Vega | ⚠️ Needs Changes | Bulk position escalation (C1) + dispatcher fail-open (H1) |

**Consensus: ⚠️ Needs Changes** — 1 confirmed privilege escalation vulnerability, 1 fail-open pattern, missing security test coverage.

## 🔴 Critical: Privilege Escalation via Bulk Role Position Update (2/3 consensus, manually verified ✅)

**File:** `routes/roles.ts` — `PATCH /guilds/:guildId/roles`
**Found by:** Nova (Critical), Vega (Critical). Stella missed this.
**Manually verified against source code: CONFIRMED.**

The handler only checks the **target position** is below the caller's highest role. It does NOT check the role's **current position**.

**Attack scenario:**
1. User has MANAGE_ROLES, highest role at position 3
2. ADMINISTRATOR role exists at position 8
3. User sends `[{ id: "admin-role-id", position: 2 }]`
4. Check passes: target position 2 < caller highest 3 ✅
5. ADMINISTRATOR role now at position 2 (below caller)
6. User assigns it to themselves → **full privilege escalation**

**Fix:** Add current position check:
```typescript
const existingRole = roles.find(r => r.id === entry.id);
if (existingRole && existingRole.position >= callerHighest) {
  return missingPermissions(c);
}
```

## 🟠 High: Dispatcher Fail-Open (3/3 consensus, verified ✅)

**File:** `ws/dispatcher.ts` — `broadcastToGuildWithChannelFilter()`
**Found by:** Nova (High), Vega (High), Stella (Medium H5)

Permission check is gated by null checks. If any repo isn't wired → all sessions bypass filtering → data leak.

**Fix:** Invert to fail-closed — `if (!guild || !roles || ...) continue;`

## 🟡 Medium: Cross-Guild Role Access (3/3 consensus, verified ✅)

**File:** `repos/roles.ts` — `getById()`
**Found by:** Nova (Critical), Vega (Medium), Stella (High)

`getById(roleId)` has no `guild_id` filter. Currently safe in single-guild, but latent vulnerability.

**Fix:** Add `getByIdInGuild(roleId, guildId)` method.

## 🟡 Medium: Missing Security Tests (2/3 consensus)

**Found by:** Stella (Critical C1-C3), Nova (Medium M2)

No dedicated unit tests for:
- `computePermissions` algorithm (spec §10 explicitly requires this)
- Role CRUD privilege escalation paths
- Overwrite value constraints

## 🟡 Medium: Other Issues (2+ reviewers)

| Issue | Reviewers | Severity |
|-------|-----------|----------|
| Guild webhook list missing MANAGE_WEBHOOKS | 3/3 | Medium |
| Channel file write/delete only needs VIEW_CHANNEL | Nova + Vega | Medium |
| Fresh deploy owner_id stays null | Nova + Stella | Medium |
| Bulk-delete missing VIEW_CHANNEL | Nova | Medium |
| New roles created at highest position | Nova | Medium |

## Suggestions (non-blocking)

- Remove old helpers (`requireGuildMember`, `requireBotChannelPermission`) per spec §7.2
- `requireChannelPermission`/`requireGuildPermission` not actually async (no await)
- Direct `repos.db` access in role assignment → should use MembersRepo
- LIKE pattern for role ID matching in delete could match partial IDs
- Typing endpoint missing VIEW_CHANNEL
- Migration test description says v19 but asserts v20

## ✅ What's Done Well (3/3 consensus)

- **computePermissions algorithm is correct** — exact Discord parity (owner bypass, @everyone base, role OR accumulation, ADMINISTRATOR shortcut, overwrite priority)
- **Unified enforcement** — bot + human same permission path (major security improvement over old dual system)
- **Human WebSocket filtering** — closes data leak where denied humans received all events
- **BigInt throughout** — no Number truncation risk for 64-bit permission values
- **Migration is idempotent** — IF NOT EXISTS + OR IGNORE
- **Role hierarchy enforcement** — correct in single-role CRUD operations
- **Permission value constraints** — new permissions must be subset of caller's
- **Managed role protection** — blocks modify/assign/remove
- **Thread → parent channel overwrite resolution** — correct
- **Transactional role deletion** — member cleanup + overwrite cleanup + delete in one transaction

## Required Before Merge

1. **[C1]** Fix bulk position update — add current position check (privilege escalation)
2. **[H1]** Invert dispatcher to fail-closed
3. **[M-tests]** Add computePermissions unit tests + privilege escalation negative tests

## Recommended

4. **[M-guild]** Add guild_id validation to role getById
5. **[M-webhook]** Add MANAGE_WEBHOOKS to guild webhook list
6. **[M-files]** Strengthen channel file write/delete permissions
