# 🌠 Nova Review — PR #437: Multi-Server Support

**PR:** kagura-agent/cove#437
**Branch:** `docs/434-multi-server-support`
**Scope:** 21 files, +1422 / −22 lines
**Reviewer:** Nova
**Date:** 2026-06-29

---

## Summary

This PR introduces multi-server (guild) support across client and server, implementing `POST/PATCH/DELETE /guilds` API endpoints, a new guild sidebar component, create-server dialog, server settings overview/danger sections, gateway event handling for `GUILD_CREATE/UPDATE/DELETE`, and improved bot permission filtering during WebSocket identify. The code is well-structured with a clear spec document, good test coverage for guild CRUD and gateway events, and follows existing patterns. There are a few issues around atomicity and input validation that should be addressed before merge.

---

## Critical Issues

### 1. Guild creation is not atomic — partial state on failure
**File:** `packages/server/src/routes/guilds.ts` lines 37–48

The `POST /guilds` handler performs four sequential write operations (create guild, create @everyone role, create #general channel, add member) without wrapping them in a database transaction. If role creation or channel creation fails (e.g., constraint violation, disk error), the guild row exists without its required @everyone role or #general channel, leaving the database in an inconsistent state.

**Fix:** Wrap lines 37–48 in `repos.guilds.db.transaction(...)()` or expose a transactional `createGuildWithDefaults` method on the repo layer, similar to how `GuildsRepo.delete()` correctly uses a transaction.

### 2. `icon` field accepts arbitrary strings without validation
**File:** `packages/server/src/routes/guilds.ts` lines 19, 39, 85

Both `POST /guilds` and `PATCH /guilds/:guildId` accept an `icon` field from user input but perform no validation — no type check, no max-length enforcement, no content filtering. A client could store an arbitrarily long string (megabytes of data) or inject content that could be problematic when rendered.

Per the spec, icon upload is deferred until #420. If accepting `icon` now, at minimum add `validateString(body.icon, "icon", { maxLength: 2048 })`. Alternatively, strip/ignore the `icon` field entirely until #420 is implemented.

---

## Product Impact

### 1. GUILD_CREATE WebSocket event lacks channels/roles for the creating user
**File:** `packages/server/src/ws/dispatcher.ts` line 153

`addGuildToUser()` dispatches `GUILD_CREATE` with only the basic guild object from `guildsRepo.getById()`, which lacks `channels` and `roles`. The creating user doesn't notice because `CreateServerDialog` already populates the stores from the HTTP response before the WS event arrives. However, if another tab is open or the HTTP response is slow, the second tab's `gateway-subscriptions.ts` handler for `GUILD_CREATE` won't receive channels/roles, leaving the new guild empty in that tab until a refresh.

**Suggestion:** Either enrich the `GUILD_CREATE` WS payload to include channels/roles (matching the READY format as the spec states), or accept the limitation and note it.

### 2. Duplicate store updates on guild creation
**Files:** `packages/client/src/components/CreateServerDialog.tsx` lines 34–44, `packages/client/src/lib/gateway-subscriptions.ts` lines 227–235

After `POST /guilds`, the `CreateServerDialog` manually adds the guild and channels to stores, then the WS `GUILD_CREATE` event fires and the subscription handler re-adds the guild. This is functionally harmless (addGuild just overwrites the entry) but could cause brief UI flicker or unnecessary re-renders.

### 3. Delete navigation race between dialog and WS handler
**File:** `packages/client/src/components/ServerSettings.tsx` lines 135–155, `packages/client/src/lib/gateway-subscriptions.ts` lines 242–255

`DangerSection.handleDelete()` removes the guild from stores and navigates away. When the `GUILD_DELETE` WS event arrives (milliseconds later), `gateway-subscriptions.ts` also tries to navigate. Because the guild is already removed from the store by then, the WS handler's `data.id === activeGuildId` check should still match (the guildId comes from the router, not the store). This could cause a double navigation. Not blocking, but worth considering deduplication — e.g., skip navigation in the dialog since the WS handler will handle it.

---

## Suggestions

### 1. Unused import: `generateSnowflake` in `repos/guilds.ts`
**File:** `packages/server/src/repos/guilds.ts` line 2

`generateSnowflake` is imported but never used — the ID is generated in the route handler. Remove the unused import.

### 2. Guild name length validation is duplicated
**File:** `packages/server/src/routes/guilds.ts` lines 23–27, 91–96

Both `POST` and `PATCH` handlers validate name with `validateString` then separately check `trim().length < 2`. Consider extracting a `validateGuildName()` helper to keep validation consistent and DRY.

### 3. `PATCH /guilds/:guildId` should validate `icon` type if present
**File:** `packages/server/src/routes/guilds.ts` line 85

Even if icon content validation is deferred, at minimum ensure `body.icon` is a string if provided, to prevent non-string values from reaching the database.

### 4. Consider limiting guild name to `validateDisplayName` rules
**File:** `packages/server/src/routes/guilds.ts`

The existing `validateDisplayName` utility checks for control characters and zero-width characters. Guild names should probably have the same restrictions to prevent invisible or confusing server names.

### 5. `GuildSidebar` guild ordering is non-deterministic
**File:** `packages/client/src/components/GuildSidebar.tsx` line 148

`Object.values(guilds)` relies on JavaScript object property order, which for snowflake IDs (numeric-looking strings) follows insertion order. This is fine for now but fragile — if the store is ever rehydrated from an unordered source, guild order could change unexpectedly. A sort by `created_at` or name would be more robust.

### 6. Error messages in delete section could expose info
**File:** `packages/client/src/components/ServerSettings.tsx` line 153

`message.error("Failed to delete server")` swallows the server error. For owner-facing operations, showing the actual error message (when available) would help debugging.

### 7. `saveLastChannel` is exported from `GuildSidebar.tsx` and imported by `Sidebar.tsx`
**File:** `packages/client/src/components/GuildSidebar.tsx` line 133, `packages/client/src/components/Sidebar.tsx` line 11

This creates a dependency from Sidebar → GuildSidebar. Consider moving `saveLastChannel` and `getLastChannelForGuild` to a shared utility (e.g., `lib/guild-utils.ts`) to keep component dependencies clean.

### 8. Channel type hardcoded as `0` for text channel detection
**File:** `packages/client/src/components/GuildSidebar.tsx` line 158

`channels.find((c) => c.type === 0)` uses a magic number. If a `ChannelType` enum exists in `@cove/shared`, prefer using the named constant for clarity.

---

## Positive Notes

- **Excellent spec document** (`docs/specs/434-multi-server-support.md`) — clear problem statement, Discord reference, scoped decisions, and an honest "out of scope" section. This is spec-driven development done right.
- **Thorough test coverage** — API tests cover happy paths, auth rejections, rate limiting, seed guild protection, and cross-guild isolation. Client tests cover store operations and gateway event handling.
- **Security-conscious permission improvements** — The WebSocket session identify change from raw `hasPermission` to `computePermissions` is a meaningful security upgrade for bot channel filtering, properly handling role inheritance.
- **Cascade delete is comprehensive** — The transaction in `GuildsRepo.delete()` correctly handles messages, read_states, permission_overwrites, channels, members, roles, and webhooks. FK cascades cover reactions, attachments, channel_files, and thread_members.
- **Clean gateway event architecture** — The `GUILD_CREATE/UPDATE/DELETE` event handlers in `gateway-subscriptions.ts` correctly handle store updates and navigation fallbacks. The redirect-on-delete logic is well thought out.
- **Good seed guild protection** — Both `DELETE` (403 for NULL owner_id) and `PATCH` (falls through to permission check) handle the legacy seed guild correctly.
- **Consistent style** — The new code follows existing patterns: Hono route structure, Zustand store patterns, Ant Design component usage, and inline styles matching the rest of the client.

---

## Rating: ⚠️ Needs Changes

The guild creation atomicity issue (Critical #1) can cause database inconsistency on partial failures. The icon validation gap (Critical #2) is a straightforward fix. Both are small changes. The rest of the PR is solid work.
