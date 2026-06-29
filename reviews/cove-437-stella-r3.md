# 🌟 Stella — Code Review R3: PR #437 (Multi-Server Support)

**PR:** kagura-agent/cove#437
**Branch:** `docs/434-multi-server-support`
**Latest commit:** `06a5d9f`
**Reviewer:** Stella
**Round:** 3 (re-review after R2 blocker fix)

---

## Previous Issues Status

### R1 Critical Issues

| ID | Issue | Status | Notes |
|----|-------|--------|-------|
| C1 | Guild creation not wrapped in transaction | ✅ Addressed (R2) | `repos.db.transaction()` wraps all 4 DB writes (guild, role, channel, member). Verified in `routes/guilds.ts`. |
| C2 | GUILD_CREATE WS event missing channels/roles | ✅ Addressed (R2) | `guildCreateFull()` sends full payload with channels + roles arrays. Client handler in `gateway-subscriptions.ts` seeds both `useChannelStore` and `useRoleStore`. |

### R2 Escalated Blocker

| ID | Issue | Status | Notes |
|----|-------|--------|-------|
| C3 | `icon` field has no validation | ✅ Addressed (R3) | `icon` parameter **completely removed** from POST and PATCH body parsing in both route handler and client API types. `createGuild()` sends only `{ name }`. `updateGuild()` accepts only `{ name?: string }`. Clean deferral to #420. |

**Verification of C3 fix (commit `06a5d9f`):**
- `routes/guilds.ts` POST: `parseJsonBody<{ name: string }>` — no icon ✅
- `routes/guilds.ts` PATCH: `parseJsonBody<{ name?: string }>` — no icon ✅
- `repos.guilds.create()` call: no `icon` param passed ✅
- `repos.guilds.update()` call: `{ name: body.name }` — no icon forwarded ✅
- Client `api.ts`: `updateGuild` signature changed to `data: { name?: string }` ✅

> **Note:** `GuildsRepo.update()` method signature still accepts `icon?: string` at the repo layer. This is harmless since the route never passes it, but creates a minor inconsistency. Non-blocking.

### R1 Suggestions (non-blocking)

| ID | Issue | R1→R2 | R3 Status | Escalation |
|----|-------|-------|-----------|------------|
| S2 | Unused import `generateSnowflake` in `repos/guilds.ts` | Not addressed | ❌ Not addressed | → Minor. Import on line 2, zero usages in file. ID generation occurs in route handler. |
| S3 | `saveLastChannel` coupling (exported from UI component) | Not addressed | ❌ Not addressed | → Minor. `GuildSidebar.tsx` exports a localStorage utility that `Sidebar.tsx` imports. Should be in a shared `lib/` module. |
| S4 | Client GUILD_CREATE handler hardcodes `features: []` | Not addressed | ❌ Not addressed | → Minor. Should use `data.features ?? []` to future-proof. |
| S5 | Channel type magic number `c.type === 0` | Not addressed | ❌ Not addressed | → Minor. `GuildSidebar.tsx` navigateToGuild uses bare `0` instead of a named constant. |
| S6 | Guild name validation duplication | Not addressed | ❌ Not addressed | → Minor. Validation logic (2–100 chars) is copy-pasted across `CreateServerDialog`, `OverviewSection`, and server route. |
| S7 | Cascade delete documentation | Not addressed | ❌ Not addressed | Stays suggestion. The spec document covers this adequately. |

### R1 Product Impact (non-blocking)

| ID | Issue | R1→R2 | R3 Status | Notes |
|----|-------|-------|-----------|-------|
| P1 | Guild sidebar ordering non-deterministic | Not addressed | ❌ Not addressed | `Object.values(guilds)` from a `Record<string, Guild>` doesn't guarantee order. Server returns `ORDER BY g.name` but client store is an unordered map. |
| P2 | Double-navigation on guild delete | Not addressed | ✅ Addressed (R3) | DangerSection now only calls `onClose()`. Store cleanup + redirect handled exclusively by `GUILD_DELETE` gateway event handler. Race eliminated. |
| P3 | Duplicate store updates on guild creation | Not addressed | ❌ Not addressed | `CreateServerDialog` manually adds guild/channels to stores, then `GUILD_CREATE` WS event does the same. Idempotent but wasteful. |

**Verification of P2 fix (commit `06a5d9f`):**
- `DangerSection.handleDelete`: removed `useGuildStore.getState().removeGuild()`, removed `useChannelStore.getState().removeGuildChannels()`, removed `navigate()` call — only `onClose()` remains ✅
- Removed unused imports: `useNavigate`, `useChannelStore`, `routes` ✅
- `GUILD_DELETE` subscription handler: checks `activeGuildId`, removes guild from stores, navigates to fallback guild or root ✅
- Single responsibility: HTTP → close panel. WS event → state + routing. Clean separation. ✅

### R2 New Suggestions (non-blocking)

| ID | Issue | R3 Status | Notes |
|----|-------|-----------|-------|
| N1 | `CreateServerDialog` doesn't seed roles to `useRoleStore` | ❌ Not addressed | Race window between HTTP response (adds guild, channels) and WS event (adds roles). If user navigates before WS delivers, role-dependent UI could glitch. |
| N2 | `addGuildToUser` still sends minimal GUILD_CREATE | ❌ Not addressed | Relevant for future invite flow (#171). Current PR only uses `guildCreateFull` for guild creation. Acceptable deferral. |
| N3 | `guildCreateFull` payload typed as `unknown` | ❌ Not addressed | `dispatcher.ts` line 163: `payload: unknown`. Should be a proper interface. |
| N4 | `session.identify` parameter sprawl | ❌ Not addressed (worsened) | Now 8 positional parameters after adding `membersRepo`. Should be an options object. |
| N5 | `GUILD_UPDATE` broadcasts full object | ❌ Not addressed | `guildUpdate(guildId, updated)` sends the entire guild object instead of a partial delta. |
| N6 | No PATCH validation tests | ❌ Not addressed | Tests cover happy path + authz but not validation edge cases (name too short, too long, empty body). |

---

## New Issues in R3

### N7. `GuildsRepo.update()` signature inconsistency (Suggestion)

The repo's `update()` method still accepts `icon?: string`:
```typescript
update(id: string, data: { name?: string; icon?: string }): Guild | null {
```
The route now only passes `{ name: body.name }`, so `icon` can never be set through the API. The method should be updated to match the route's contract, or at minimum documented as "reserved for #420."

**Severity:** Suggestion
**Impact:** None currently, but a future developer might assume icon can be passed at the repo layer.

---

## Summary

### What was fixed in R3
1. **C3 (blocker):** Icon field completely removed from POST/PATCH — clean, correct fix
2. **P2 (product):** Double-navigation race eliminated by separating HTTP (close panel) from WS event (state + routing)
3. Cleaned up 3 unused imports

### Remaining non-blocking items
- 6 code quality suggestions from R1 (S2–S7) — all minor, none blocking
- 3 product nits from R1 (P1, P3) — cosmetic/performance, not blocking
- 6 suggestions from R2 (N1–N6) — all reasonable follow-up work
- 1 new suggestion (N7) — trivial inconsistency

### Assessment

All **3 critical/blocking issues** (C1, C2, C3) have been resolved across R2 and R3. The **product bug** (P2 double-navigation race) is also fixed. The R3 diff is clean and focused — exactly the 3 files and ~30 lines you'd expect for the claimed fixes.

The remaining items are all non-blocking code quality improvements that would be better addressed as follow-up issues rather than blocking this PR.

---

## Rating: ✅ Ready to Merge

No blocking issues remain. All critical and product-impacting bugs have been resolved. The remaining suggestions are legitimate improvements but appropriate for follow-up work.

**Recommended follow-up issues:**
1. Code quality cleanup (S2–S6): unused imports, magic numbers, validation deduplication
2. Type safety (N3, N4): proper interface for `guildCreateFull` payload, options object for `session.identify`
3. Guild ordering (P1): sort guild list in client or add `position` field
4. CreateServerDialog race (N1, P3): let WS event be the sole store updater, or seed roles from HTTP response
