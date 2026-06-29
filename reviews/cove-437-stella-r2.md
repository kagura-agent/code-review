# 🌟 Stella — Round 2 Re-Review: PR #437 (Multi-Server Support)

**PR:** kagura-agent/cove#437
**Branch:** `docs/434-multi-server-support`
**Latest Commit:** `364626f`
**Reviewer:** Stella (Round 2)
**Date:** 2026-06-29

---

## 1. Previous Issues Status

### Critical Issues

| ID | Issue | Status | Notes |
|----|-------|--------|-------|
| **C1** | Guild creation not wrapped in transaction | ✅ **Addressed** | `routes/guilds.ts` POST handler now uses `repos.db.transaction()` wrapping all 4 DB writes (guild, role, channel, member). Correctly invoked with `()()` pattern for better-sqlite3. Event dispatch happens AFTER transaction commits — proper ordering. |
| **C2** | GUILD_CREATE WS event missing channels/roles | ✅ **Addressed** | New `dispatcher.guildCreateFull()` method sends full payload including channels and roles. Client-side `gateway-subscriptions.ts` GUILD_CREATE handler now seeds channels via `setChannels()` and roles via `setRoles()` from the event payload. |

### Suggestions

| ID | Issue | Status | Notes |
|----|-------|--------|-------|
| **S1** | `icon` field lacks validation | ❌ **Not Addressed** | POST `/guilds` and PATCH `/guilds/:guildId` both accept `icon` as an arbitrary string with no type, length, or format validation. While icon upload is deferred to #420, the field is currently accepted and stored — an attacker could store arbitrary large strings or malicious content. The `<img src={guild.icon}>` in `GuildSidebar.tsx` renders it directly, making this an XSS surface if non-URL strings are injected. |
| **S2** | Unused import `generateSnowflake` in repos/guilds.ts | ❌ **Not Addressed** | `generateSnowflake` is imported in `packages/server/src/repos/guilds.ts` but never used — the snowflake is generated in `routes/guilds.ts`. Dead import. |
| **S3** | `saveLastChannel` coupling | ❌ **Not Addressed** | `saveLastChannel` is exported from the UI component `GuildSidebar.tsx` and imported by `Sidebar.tsx`. Utility logic leaks through a component boundary. Should live in a shared `lib/` or `utils/` module. |
| **S4** | Client GUILD_CREATE handler hardcodes `features: []` | ❌ **Not Addressed** | Still hardcoded in three places: `gateway-subscriptions.ts` GUILD_CREATE handler, `CreateServerDialog.tsx` addGuild call, and `repos/guilds.ts` create return. If features are ever sent from the server, they'll be silently dropped. |
| **S5** | Channel type magic number | ❌ **Not Addressed** | `c.type === 0` in `GuildSidebar.tsx` navigateToGuild and `ch.type === 11` in `session.ts` — still raw numbers instead of named constants. |
| **S6** | Guild name validation duplication | ❌ **Not Addressed** | Same 2–100 char, trim validation logic is duplicated in `CreateServerDialog.tsx`, `OverviewSection` in `ServerSettings.tsx`, and `routes/guilds.ts` (POST + PATCH). Four independent copies. |
| **S7** | Cascade delete documentation | ❌ **Not Addressed** | `repos/guilds.ts` `delete()` cascade handles: messages, read_states, permission_overwrites, channels, members, roles, webhooks — but doesn't mention threads, reactions, or pins. No inline documentation of what IS and ISN'T cascaded. |

**Escalation per re-review rules:** S1 was a 3/3 consensus suggestion in R1, not addressed in R2 → **Escalated to Critical** (see new issues section below).

### Product Impact

| ID | Issue | Status | Notes |
|----|-------|--------|-------|
| **P1** | Guild sidebar ordering non-deterministic | ❌ **Not Addressed** | `Object.values(guilds)` in `GuildSidebar.tsx` — JS object property order depends on insertion order, no explicit sort. Guild order will shift across page reloads if store hydration order changes. |
| **P2** | Double-navigation on guild delete | ❌ **Not Addressed** | When user deletes via `DangerSection`, both the local callback AND the incoming GUILD_DELETE gateway event perform navigation. Two navigations fire — the second may clobber the first or cause a flash. |
| **P3** | Duplicate store updates on guild creation | ❌ **Not Addressed** | `CreateServerDialog` manually calls `addGuild()`/`setChannels()` from the API response, AND the GUILD_CREATE websocket event triggers the same operations via `gateway-subscriptions.ts`. Store gets written twice. |

---

## 2. New Issues

### 🔴 Critical (Escalated)

#### C3. `icon` field stored and rendered without validation (Escalated from S1)

**Files:** `packages/server/src/routes/guilds.ts` (POST + PATCH), `packages/client/src/components/GuildSidebar.tsx`

**Severity:** Critical (escalated — 3/3 R1 consensus, not addressed)

The `icon` field passes from user input through to the database and then into an `<img src={guild.icon}>` tag without any validation:

```typescript
// routes/guilds.ts POST handler — icon goes straight to DB
const guild = repos.guilds.create({ id: guildId, name, icon: body.icon, owner_id: userId });

// GuildSidebar.tsx — rendered directly
{guild.icon ? (
  <img src={guild.icon} alt={guild.name} style={{ ... }} />
) : ( ... )}
```

**Risks:**
1. **Storage abuse:** No length limit on the icon string — could store megabytes per guild
2. **XSS via `javascript:` URLs:** While modern browsers block `javascript:` in `<img src>`, some edge cases exist with SVG data URIs or `onerror` attributes (not present here, but the lack of sanitization is the root issue)
3. **SSRF surface:** If icon URLs are ever fetched server-side (e.g., for thumbnails), arbitrary internal URLs could be targeted

**Recommendation:** Either (a) reject the `icon` field entirely until #420 lands (cleanest), or (b) validate it's a valid HTTPS URL with a max length (e.g., 512 chars) and allowlisted schemes.

### ⚠️ Suggestions (New)

#### S8. `session.ts` identify parameter sprawl

**File:** `packages/server/src/ws/session.ts`

The `identify()` method signature now has 8 parameters:
```typescript
identify(user, dispatcher, guildsRepo, channelsRepo, readStatesRepo, permissionsRepo?, rolesRepo?, membersRepo?)
```

This is getting unwieldy. Consider a single `context` or `deps` object parameter for cleaner extensibility.

#### S9. Cascade delete doesn't cover threads or reactions

**File:** `packages/server/src/repos/guilds.ts` `delete()`

The cascade explicitly handles messages, read_states, permission_overwrites, channels, members, roles, and webhooks — but threads (type 11 channels or separate table entries) and message reactions could be orphaned. If a `reactions` or `threads` table exists with FK references to deleted messages/channels without ON DELETE CASCADE at the DB level, these will leak.

---

## 3. Summary

### What's Improved Since R1
- ✅ **C1 fixed properly:** Transaction wrapping is clean — all 4 writes atomic, event dispatch after commit
- ✅ **C2 fixed properly:** `guildCreateFull()` sends channels + roles, client handles them in the subscription handler
- ✅ **Good test coverage added:** `guilds.test.ts` (235 lines) covers POST/PATCH/DELETE with permission checks, rate limits, cascade verification, and cross-guild isolation. `guild-events.test.ts` covers gateway event handling. `useGuildStore.test.ts` covers store operations.
- ✅ **GUILD_UPDATE event added:** Both server dispatch and client handler implemented
- ✅ **GUILD_DELETE navigation:** Gateway handler navigates to fallback guild or root when active guild is deleted
- ✅ **Bot channel permission filtering improved:** `session.ts` now uses `computePermissions` instead of raw `hasPermission` check

### What Remains
- **1 escalated critical (C3):** `icon` field has no validation and is rendered directly — should be blocked or validated before merge
- **7 unaddressed suggestions (S1–S7):** All from R1, none addressed. S1 was escalated to C3.
- **3 unaddressed product impacts (P1–P3):** Non-blocking but will cause UX jank (duplicate navigations, duplicate store writes, unstable sort)
- **2 new suggestions (S8, S9):** Parameter sprawl and incomplete cascade coverage

### Rating

## ⚠️ Needs Changes

**Blocking:** C3 (icon validation) — either reject the field or validate it before storing/rendering.

**Non-blocking but recommended:** P2/P3 are easy wins — guard against duplicate operations with a simple `if` check or by removing the manual store writes in `CreateServerDialog`/`DangerSection` and relying solely on the gateway events (or vice versa, but pick one source of truth).
