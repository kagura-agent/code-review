# 🌟 Stella Review — PR #437: Multi-Server Support

**PR:** kagura-agent/cove#437
**Branch:** `docs/434-multi-server-support`
**Stats:** +1422 / -22, 21 files changed

## Summary

This PR adds multi-server (guild) support: `POST/PATCH/DELETE /guilds` API endpoints, guild list sidebar UI, server settings (overview + delete), gateway event handlers for `GUILD_CREATE/UPDATE/DELETE`, and a comprehensive spec document. The architecture is sound — it follows the existing repo/route/dispatcher pattern consistently, includes proper authorization checks, cascade deletion within a transaction, and has good test coverage. There are a couple of correctness issues around atomicity and the gateway GUILD_CREATE payload that should be addressed before merge.

---

## Critical Issues

### 1. `POST /guilds` — Multi-step creation is not wrapped in a transaction
**File:** `packages/server/src/routes/guilds.ts`, lines 37–50

The guild creation flow performs four sequential DB writes (guild → role → channel → member) without a transaction. If `repos.channels.create()` or `repos.members.add()` throws, the database is left with orphaned data (a guild with a role but no channel or member).

Compare with `GuildsRepo.delete()` which correctly uses `this.db.transaction(...)`. The create path should do the same.

**Fix:** Wrap the create sequence in a transaction, or add a repo-level `createGuildWithDefaults()` method that encapsulates the atomic creation.

### 2. `addGuildToUser` dispatches `GUILD_CREATE` without channels/roles
**File:** `packages/server/src/ws/dispatcher.ts`, lines 152–162

The spec (line 60) explicitly states: *"GUILD_CREATE — Full guild object (with channels, roles)"*. But `addGuildToUser` calls `guildsRepo.getById(guildId)` which returns only `{ id, name, icon, owner_id, features }` — no channels or roles.

For the current V1 flow (only the creator receives this event), it works because `CreateServerDialog` seeds channels/roles from the HTTP response before the gateway event arrives. But:
- The spec contract is violated
- When invite system (#171) lands and `addGuildToUser` is called for invited users, they'll see the guild in the sidebar with **no channels** until page reload
- Race condition: if the gateway event arrives after the HTTP response, `addGuild` overwrites the guild store entry (harmless for now since channel/role data lives in separate stores, but fragile)

**Fix:** Enhance `addGuildToUser` to fetch and include channels and roles in the GUILD_CREATE payload, or add a new overload that accepts the full payload.

---

## Product Impact

### Guild sidebar ordering is non-deterministic
**File:** `packages/client/src/components/GuildSidebar.tsx`, line 142

`Object.values(guilds)` iterates in JS property insertion order, which depends on when guilds were added to the store. This means:
- Guilds may reorder after page refresh (since READY loads them in `name` sort order from `listForUser`)
- Newly created guilds appear at the end, then jump to alphabetical position on reload

Users expect a stable guild order. Consider sorting `guildList` explicitly (e.g., by name, or by join date, or by a future user-defined order).

### Double-navigation on guild delete from Settings
**File:** `packages/client/src/components/ServerSettings.tsx` (DangerSection, ~line 148) + `packages/client/src/lib/gateway-subscriptions.ts` (GUILD_DELETE handler, ~line 244)

When a user deletes a guild via the Settings UI:
1. The HTTP response triggers store cleanup + `navigate()` in `DangerSection`
2. The WebSocket `GUILD_DELETE` event arrives and the gateway subscription handler also calls `navigate()` if it was the active guild

This can cause a visible navigation flash. Consider either: (a) deduplicating the navigation (check if guild still exists in store before navigating in the gateway handler), or (b) having the DangerSection skip navigation and let the gateway handler handle it exclusively.

---

## Suggestions

### 1. Unused import: `generateSnowflake` in `repos/guilds.ts`
**File:** `packages/server/src/repos/guilds.ts`, line 2

`generateSnowflake` is imported but never used in this file (it's used in `routes/guilds.ts` instead). Remove to keep imports clean.

### 2. `icon` field lacks validation in POST and PATCH
**Files:** `packages/server/src/routes/guilds.ts`, lines 20 and 91

The `icon` field is accepted as-is with no type check or length constraint. While icon upload is deferred (per spec), the field is writable. A malicious client could store arbitrary large strings. Add at minimum a `typeof === 'string'` check and a max length (e.g., 2048 chars for a URL).

### 3. Consider membership check in POST /guilds rate limit
**File:** `packages/server/src/routes/guilds.ts`, line 33

`countByOwner` counts only guilds where the user is the **owner**. This means a user who is a member of 50 guilds but owns 0 can still create 10 more. This is consistent with Discord's model (which limits server creation, not membership), so this is correct behavior — just noting for awareness.

### 4. `saveLastChannel` exported from `GuildSidebar.tsx` and imported by `Sidebar.tsx`
**Files:** `packages/client/src/components/GuildSidebar.tsx` (line 125), `packages/client/src/components/Sidebar.tsx` (line 11)

This creates a circular-ish coupling where `Sidebar` imports from `GuildSidebar`. Consider extracting `saveLastChannel` / `getLastChannelForGuild` into a shared utility (e.g., `lib/guild-navigation.ts`) for cleaner separation.

### 5. Client GUILD_CREATE handler hardcodes `features: []`
**File:** `packages/client/src/lib/gateway-subscriptions.ts`, line 226

```ts
useGuildStore.getState().addGuild({ ..., features: [] });
```

If the server ever sends `features` in the GUILD_CREATE payload, they'd be silently dropped. Consider `features: data.features ?? []`.

### 6. Guild cascade delete — `reactions` table relies on FK cascade
**File:** `packages/server/src/repos/guilds.ts`, lines 80–97

The delete transaction explicitly handles messages, read_states, channel_permission_overwrites, channels, guild_members, roles, and webhooks. Reactions rely on `ON DELETE CASCADE` from messages, and channel_files/thread_members rely on CASCADE from channels. This works because `PRAGMA foreign_keys = ON`, but it's implicit. Consider adding a comment noting the FK-cascade-covered tables for future maintainers, or explicitly deleting them for defense-in-depth.

---

## Positive Notes

- **Spec-first development**: The 164-line spec document is thorough — it covers Discord reference behavior, constraints, out-of-scope items, migration notes, and a test plan. This is excellent engineering practice.
- **Authorization model is correct**: Owner check for DELETE, owner-or-MANAGE_GUILD for PATCH, seed guild protection (owner_id NULL → 403 on DELETE). The permission computation uses `computeBasePermissions` properly.
- **Cascade delete is transactional**: `GuildsRepo.delete()` wraps all cascading deletes in `db.transaction()`, preventing partial deletion states.
- **Confirmation UX for destructive action**: The DangerSection requires typing the exact server name to confirm deletion — good safety pattern.
- **Test coverage is solid**: API tests cover the happy path, authorization rejection, rate limiting, cascade verification, and cross-guild isolation. Client tests cover store operations and gateway event handlers including edge cases (minimal GUILD_CREATE without channels, DELETE with redirect).
- **Session permission filtering improvement**: The `identify()` method now uses `computePermissions` instead of raw `hasPermission`, properly handling inherited permissions for bot users.
- **Clean gateway event wiring**: GUILD_UPDATE handler added to client, GUILD_DELETE handler enhanced with navigation fallback logic.

---

## Rating: ⚠️ Needs Changes

The non-transactional guild creation (Critical #1) risks data corruption on partial failure, and the incomplete GUILD_CREATE gateway payload (Critical #2) will break the invite flow when #171 lands. Both are straightforward fixes. The rest of the PR is well-structured and ready.
