# Consolidated Review — PR #437: Multi-Server Support

**PR:** kagura-agent/cove#437
**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 2.5 Pro)
**Date:** 2026-06-29

---

## Overall Verdict: ⚠️ Needs Changes

All 3 reviewers independently rated ⚠️ Needs Changes, converging on the same 2 critical issues. Both are straightforward fixes. The rest of the PR is well-structured with excellent spec, thorough tests, and sound architecture.

---

## Critical Issues (Consensus — all 3 reviewers)

### C1. Guild creation is not wrapped in a transaction
**File:** `packages/server/src/routes/guilds.ts` (lines 37–49)
**Confidence:** 🔴 High (3/3 agree)

`POST /guilds` performs 4 sequential DB writes (guild → @everyone role → #general channel → member) without a transaction. If any intermediate step fails, the database is left with orphaned data — a guild without its required role, channel, or creator membership.

Compare with `GuildsRepo.delete()` which correctly uses `this.db.transaction(...)`.

**Fix:** Wrap the create sequence in a transaction, or add a repo-level `createGuildWithDefaults()` method.

### C2. `GUILD_CREATE` gateway event missing channels/roles
**File:** `packages/server/src/ws/dispatcher.ts` (`addGuildToUser`, lines ~152–162)
**Confidence:** 🔴 High (3/3 agree)

`addGuildToUser` dispatches `GUILD_CREATE` with only the base guild object from `guildsRepo.getById()` — no channels or roles. The spec states GUILD_CREATE should include the full guild object with channels and roles.

Currently works for the creator (HTTP response seeds stores first), but:
- Violates the spec contract
- Multi-tab scenarios: second tab receives bare guild with no channels
- When invite system (#171) lands, invited users will see an empty guild until page reload

**Fix:** Enrich the GUILD_CREATE payload to include channels and roles. The route handler already has `everyoneRole` and `generalChannel` — pass them through, or have `addGuildToUser` query them.

---

## Product Impact

### P1. Guild sidebar ordering is non-deterministic (Stella + Nova + Vega)
`Object.values(guilds)` in `GuildSidebar.tsx` relies on JS property insertion order. Guilds may reorder after page refresh (READY loads them alphabetically via `listForUser`). Discord uses a stable user-defined order. Acceptable for V1 but worth noting.

### P2. Double-navigation on guild delete (Stella + Nova)
When deleting a guild from Settings UI, both the HTTP response handler and the `GUILD_DELETE` WS event handler trigger `navigate()`, potentially causing a visible navigation flash. Consider deduplicating — either skip navigation in the dialog and let the WS handler handle it, or check if the guild still exists in the store before navigating in the WS handler.

### P3. Duplicate store updates on guild creation (Nova)
`CreateServerDialog` adds the guild to stores from the HTTP response, then the `GUILD_CREATE` WS event re-adds it. Functionally harmless (addGuild overwrites) but could cause brief UI flicker.

---

## Suggestions

### S1. `icon` field lacks validation (Stella + Nova + Vega)
Both `POST` and `PATCH /guilds` accept `icon` with no type check or max-length enforcement. Even with icon upload deferred (#420), a malicious client could store arbitrarily long strings. Add `validateString(body.icon, "icon", { maxLength: 2048 })`.

### S2. Unused import: `generateSnowflake` in `repos/guilds.ts` (Stella + Nova + Vega)
Imported but never used in this file. Remove.

### S3. `saveLastChannel` coupling (Stella + Nova)
`Sidebar.tsx` imports `saveLastChannel` from `GuildSidebar.tsx`, creating component-to-component dependency. Consider extracting to a shared utility (e.g., `lib/guild-navigation.ts`).

### S4. Client `GUILD_CREATE` handler hardcodes `features: []` (Stella)
If the server ever sends `features` in the payload, they'd be silently dropped. Use `features: data.features ?? []`.

### S5. Channel type magic number (Nova)
`channels.find((c) => c.type === 0)` uses a magic number. Use named constant from `@cove/shared` if available.

### S6. Guild name validation duplication (Nova)
Both POST and PATCH validate name with `validateString` then separately check `trim().length < 2`. Extract a `validateGuildName()` helper.

### S7. Cascade delete documentation (Stella + Vega)
The delete transaction explicitly handles some tables while relying on FK cascades for others (reactions, attachments, channel_files). Consider adding a comment noting which tables are covered by CASCADE.

---

## Positive Notes

All 3 reviewers highlighted:
- **Spec-first development** — The 164-line spec is thorough with Discord reference, constraints, scope boundaries, and test plan
- **Strong test coverage** — API tests cover happy paths, auth rejections, rate limiting, seed guild protection, cross-guild isolation; client tests cover store CRUD and gateway events
- **Correct cascade delete** — `GuildsRepo.delete()` properly uses transactions
- **Security improvement** — WebSocket session identify now uses `computePermissions` instead of raw `hasPermission`, properly handling bot channel filtering with role inheritance
- **Confirmation UX** — Delete requires typing exact server name
- **Clean architecture** — Follows existing repo/route/dispatcher patterns consistently
