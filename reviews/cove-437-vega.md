# 💫 Vega Review — PR #437: Multi-Server Support

**PR:** kagura-agent/cove#437
**Branch:** `docs/434-multi-server-support`
**Files changed:** 21 (+1422 / -22)
**Reviewer:** Vega
**Date:** 2026-06-29

---

## Summary

This PR implements multi-server (guild) support for Cove, covering: guild CRUD API endpoints (`POST`, `PATCH`, `DELETE /guilds`), a guild list sidebar UI component, a create-server dialog, server settings overview/rename/delete sections, gateway events (`GUILD_CREATE`, `GUILD_UPDATE`, `GUILD_DELETE`), updated WebSocket session identify with proper permission-based channel filtering, and a comprehensive spec document. The implementation is well-structured and follows Discord's model closely. The test coverage is solid for the new store, gateway events, and API endpoints. However, there are a few correctness and robustness issues that should be addressed before merge.

---

## Critical Issues

### 1. Guild creation is not wrapped in a transaction
**File:** `packages/server/src/routes/guilds.ts` (lines 37–49)

The `POST /guilds` handler performs 4 sequential DB writes — create guild, create @everyone role, create #general channel, add member — without a transaction. If any intermediate step fails (e.g., `createEveryoneRole` throws due to a duplicate key or constraint violation), the database is left in an inconsistent state: a guild exists without its required @everyone role, default channel, or creator membership. This guild would be partially functional or broken.

Compare with `GuildsRepo.delete()` which correctly uses `this.db.transaction(...)`. The create path needs the same treatment.

**Fix:** Wrap the guild+role+channel+member creation in a single transaction, either at the repo level (a `createGuildWithDefaults` method) or in the route handler.

### 2. `GUILD_CREATE` gateway event missing channels and roles
**File:** `packages/server/src/ws/dispatcher.ts` (lines 159–167, `addGuildToUser`)

The `addGuildToUser` method dispatches `GUILD_CREATE` using `guildsRepo.getById(guildId)`, which returns only the base guild object (`{id, name, icon, owner_id, features}`). Per the spec (line 62–63) and the client handler (gateway-subscriptions.ts lines 231–238), `GUILD_CREATE` should include `channels` and `roles` arrays.

Currently this works for the guild creator because `CreateServerDialog` manually seeds channels/roles from the HTTP response. But:
- The gateway event is inconsistent with the spec's own definition
- When invite flows (#171) are implemented, users added to existing guilds will receive `GUILD_CREATE` without channels/roles, breaking their client state

**Fix:** Pass the full guild object (with channels and roles) to `addGuildToUser`, or have it query channels/roles before dispatching. The route handler already has `everyoneRole` and `generalChannel` — pass them through.

---

## Product Impact

### Guild sidebar always visible on mobile
**File:** `packages/client/src/components/GuildSidebar.tsx`

The spec mentions mobile considerations (line 115: "On mobile, it could be hidden behind the existing hamburger menu"), but the `GuildSidebar` component renders with fixed 72px width and no responsive hiding. On narrow viewports, this steals significant horizontal space from the channel sidebar and chat area. Worth verifying on mobile breakpoints and hiding behind the existing hamburger menu if needed.

### Guild list order may shift on rename
**File:** `packages/server/src/repos/guilds.ts` (line 37, `listForUser`)

Guilds are returned `ORDER BY g.name`. If a user renames a guild, it will jump position in the sidebar on next load/reconnect. Discord uses a stable user-defined order. This is acceptable for V1 but worth noting as a known limitation.

---

## Suggestions

### 1. `icon` field lacks validation on POST and PATCH
**Files:** `packages/server/src/routes/guilds.ts` (lines 19, 85)

The `icon` field is accepted as an arbitrary string with no length or format validation. While icon upload is deferred (#420), the field is still stored in the DB. A malicious client could send a very long string. Add `validateString(body.icon, "icon", { maxLength: 2048 })` or similar to both endpoints.

### 2. Unused import: `generateSnowflake` in `guilds.ts` repo
**File:** `packages/server/src/repos/guilds.ts` (line 2)

`generateSnowflake` is imported but never used in this file (the route handler generates the ID and passes it in). Remove the import.

### 3. `guildDelete` doesn't broadcast `GUILD_DELETE` before removing guild from sessions
**File:** `packages/server/src/ws/dispatcher.ts` (lines 174–179)

The `guildDelete` method calls `removeGuildFromUser` for each member, which internally sends `GUILD_DELETE` and then removes the guild from session tracking. However, it does NOT use `broadcastToGuild` first — it iterates member user IDs from the DB. This works correctly but differs from other guild-scoped broadcasts. The ordering is fine (notify then clean up), but consider documenting why this pattern is intentionally different.

### 4. Redundant manual CASCADE deletes in `GuildsRepo.delete()`
**File:** `packages/server/src/repos/guilds.ts` (lines 76–81)

The manual `DELETE FROM messages`, `DELETE FROM read_states`, and `DELETE FROM channel_permission_overwrites` are redundant because these tables have `ON DELETE CASCADE` from `channels(id)`. The subsequent `DELETE FROM channels WHERE guild_id = ?` would trigger cascades for all three. The manual deletes are harmless (belt-and-suspenders) but add maintenance surface. Consider removing them or adding a comment explaining the intentional redundancy.

### 5. `CreateServerDialog` doesn't reset state on reopen
**File:** `packages/client/src/components/CreateServerDialog.tsx`

The dialog uses `destroyOnClose` on the Modal, which remounts the component on reopen, effectively resetting `name` and `loading` state. This works but is fragile — if `destroyOnClose` is ever removed, stale state would persist. Consider using `afterClose` or `afterOpenChange` to explicitly reset.

### 6. Consider deduplicating guild add logic between HTTP response and gateway event
**File:** `packages/client/src/components/CreateServerDialog.tsx` (lines 33–43) and `packages/client/src/lib/gateway-subscriptions.ts` (lines 228–238)

Both the `CreateServerDialog` (after HTTP response) and the `GUILD_CREATE` gateway handler add the guild to the store. For the creator, the gateway event from `addGuildToUser` fires *after* the HTTP response is processed, causing a redundant `addGuild` call. This is harmless but could cause a brief flicker if the gateway event arrives with incomplete data (no channels/roles). Once Critical Issue #2 is fixed, this becomes a non-issue.

### 7. `DangerSection` client-side seed check
**File:** `packages/client/src/components/ServerSettings.tsx` (line 131)

The check `guild?.owner_id === null` to determine if a guild is the "seed guild" is correct per current logic, but it's a client-side guard only. The server also enforces this (403 on DELETE), so it's defense-in-depth. Consider adding a comment explaining why `owner_id === null` means "seed guild."

---

## Positive Notes

- **Well-structured spec document** — The spec at `docs/specs/434-multi-server-support.md` is thorough, covers Discord reference behavior, migration strategy, scope boundaries, and a test plan. Good engineering discipline.
- **Strong test coverage** — `guilds.test.ts` covers all major API paths including edge cases (max guild limit, seed guild protection, cross-guild isolation, non-member access). Client tests cover store CRUD and gateway event handling with proper mock isolation.
- **Correct cascade delete** — `GuildsRepo.delete()` uses a transaction and handles cascading cleanup for messages, channels, members, roles, webhooks, etc.
- **Permission model is sound** — PATCH uses `computeBasePermissions` for guild-level checks. The session identify now correctly uses `computePermissions` with overwrites for bot channel filtering, replacing the previous raw overwrite check.
- **Clean gateway event design** — The `GUILD_UPDATE` handler and enhanced `GUILD_DELETE` with redirect logic are well-implemented. The `removeGuildFromUser` correctly notifies before cleaning up session state.
- **Confirmation UX for delete** — The `DangerSection` requires typing the server name to confirm deletion, preventing accidental data loss.
- **GuildSidebar UI** — Clean implementation with pill indicators, hover effects, abbreviation fallback, unread aggregation, and localStorage-based last-channel memory. Matches Discord's UX closely.

---

## Rating: ⚠️ Needs Changes

The two critical issues (missing transaction on guild creation, incomplete GUILD_CREATE gateway payload) are real correctness problems. The first can cause database inconsistency on partial failure. The second creates a spec-implementation divergence that will cause bugs when invite flows land. Both are straightforward fixes. Once addressed, this is a solid PR.
