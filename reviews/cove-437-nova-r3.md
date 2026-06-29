# 🌠 Nova — PR #437 Round 3 Re-Review

**PR:** kagura-agent/cove#437 — `docs: multi-server support spec (#434, #212)`
**Branch:** `docs/434-multi-server-support`
**Latest Commit:** `06a5d9f`
**Round:** 3 (re-review)

---

## Previous Issues Status

### Critical / Blocker

| ID | Issue | Status | Notes |
|----|-------|--------|-------|
| **C1** | Guild creation not wrapped in transaction | ✅ Addressed (R2) | `repos.db.transaction()` wraps guild + role + channel + member creation in `routes/guilds.ts` |
| **C2** | GUILD_CREATE WS event missing channels/roles | ✅ Addressed (R2) | New `guildCreateFull()` dispatcher method sends full payload with channels and roles |
| **C3** | `icon` field has no validation | ✅ Addressed (R3) | `icon` parameter completely removed from POST/PATCH request body types. Route handlers now use `parseJsonBody<{ name: string }>` (POST) and `parseJsonBody<{ name?: string }>` (PATCH). Client `updateGuild` signature also stripped. Icon upload deferred to #420. |

### R1 Suggestions (non-blocking)

| ID | Issue | Status | Notes |
|----|-------|--------|-------|
| **S2** | Unused import `generateSnowflake` in `repos/guilds.ts` | ❌ Not Addressed | Line 2: `import { generateSnowflake, type Guild }` — `generateSnowflake` is never used in this file (snowflake generation happens in `routes/guilds.ts`). Third round unaddressed → escalated to **P-level**. |
| **S3** | `saveLastChannel` coupling (exported from `GuildSidebar`, imported in `Sidebar`) | ❌ Not Addressed | Still a cross-component coupling smell. Minor — works fine, just non-idiomatic. |
| **S4** | Client GUILD_CREATE handler hardcodes `features: []` | ❌ Not Addressed | Both `gateway-subscriptions.ts` and `CreateServerDialog.tsx` hardcode `features: []` instead of using `data.features ?? []`. |
| **S5** | Channel type magic number | ❌ Not Addressed | `GuildSidebar.tsx` line: `channels.find((c) => c.type === 0)`. Magic number for text channel type. |
| **S6** | Guild name validation duplication | ❌ Not Addressed | 2–100 char + trim logic duplicated across server route, `CreateServerDialog`, and `OverviewSection`. Standard practice (client UX + server security) but could share constants. |
| **S7** | Cascade delete documentation | ⚠️ Partially Addressed | Spec documents "V1 uses synchronous cascade delete." Implementation matches. No inline code comments on what `delete()` covers vs. what it might miss, but acceptable. |

### R1 Product Impact

| ID | Issue | Status | Notes |
|----|-------|--------|-------|
| **P1** | Guild sidebar ordering non-deterministic | ❌ Not Addressed | `Object.values(guilds)` in `GuildSidebar` depends on JS property insertion order. Server `listForUser` sorts by name, but the client store (`Record<string, Guild>`) doesn't preserve that order across add/remove operations. |
| **P2** | Double-navigation on guild delete | ✅ Addressed (R3) | `DangerSection` now only calls `onClose()` (closes settings panel). Store cleanup + redirect handled exclusively by `GUILD_DELETE` gateway event. Unused imports (`useNavigate`, `useChannelStore`, `routes`) cleaned up. Clean separation. |
| **P3** | Duplicate store updates on guild creation | ❌ Not Addressed | `CreateServerDialog` manually adds guild + channels to stores on API response, then the `GUILD_CREATE` gateway event does the same. Idempotent (overwrite) but wasteful. Contrast with the P2 fix which correctly centralized delete handling in the gateway event. |

### R2 New Suggestions

| ID | Issue | Status | Notes |
|----|-------|--------|-------|
| **N1** | `CreateServerDialog` doesn't seed roles | ❌ Not Addressed | Dialog seeds channels from API response but not roles. Gateway event fills the gap shortly after, but brief inconsistency window. |
| **N2** | `addGuildToUser` still sends minimal GUILD_CREATE | ❌ Not Addressed | Used for invite/join flows. Sends `guildsRepo.getById()` which lacks channels/roles. Only `guildCreateFull` sends full payload, but that's only used for guild creation, not member join. |
| **N3** | `guildCreateFull` payload typed as `unknown` | ❌ Not Addressed | `payload: unknown` — should be a proper interface. |
| **N4** | `session.identify` parameter sprawl | ❌ Not Addressed | Now 8 positional parameters (added `membersRepo`). An options object would improve readability. |
| **N5** | GUILD_UPDATE broadcasts full object | ❌ Not Addressed | `guildUpdate()` sends the entire guild object; Discord sends partial updates. Works but sends unnecessary data. |
| **N6** | No PATCH validation tests | ❌ Not Addressed | `guilds.test.ts` tests owner/non-owner PATCH but no validation edge cases (name too short, too long, empty body, whitespace-only). |

---

## New Issues (R3)

### N7. GUILD_DELETE doesn't clean up role/member/thread stores — Suggestion

**File:** `packages/client/src/lib/gateway-subscriptions.ts` (GUILD_DELETE handler)

The GUILD_DELETE handler cleans up `useGuildStore` and `useChannelStore`, but leaves stale data in:
- `useRoleStore` — roles for deleted guild persist in memory
- `useMemberStore` — members for deleted guild persist
- `useThreadStore` — threads for deleted guild's channels persist

`useRoleStore` doesn't even have a `removeGuildRoles()` method yet.

**Impact:** Memory leak / stale data. Non-critical at current scale but a correctness gap — especially since P2 centralized all cleanup in this handler.

**Suggested fix:** Add `removeGuildRoles(guildId)` to `useRoleStore` and clean up all guild-scoped stores in the GUILD_DELETE handler.

### N8. `repos/guilds.ts` `update()` still accepts `icon` in type signature — Suggestion

**File:** `packages/server/src/repos/guilds.ts`

```typescript
update(id: string, data: { name?: string; icon?: string }): Guild | null {
```

The route layer correctly strips `icon` from the request body, but the repo method still accepts and would process it. If a future caller passes `icon` to `update()`, it would be written to the DB without validation.

**Suggested fix:** Remove `icon` from the repo method signature to match the route-level decision to defer icon to #420. Or add a `// TODO(#420)` comment.

---

## Summary

### What's Fixed in R3
1. **C3 (Blocker):** Icon field completely removed from API surface — clean fix.
2. **P2 (Product):** Double-navigation race eliminated. Settings panel close and store cleanup/redirect are now properly separated between UI callback and gateway event. Unused imports cleaned up.

### What Remains
- **All previous suggestions (S2–S6, P1, P3, N1–N6)** remain unaddressed. These are non-blocking code quality items.
- **S2** (unused `generateSnowflake` import) is now in its third round unaddressed — escalated to P-level. It's a one-line fix.
- **2 new suggestions (N7, N8)** identified: stale store data on guild delete, vestigial icon type in repo.

### Rating: ✅ Ready to Merge

All three critical/blocker issues (C1, C2, C3) are resolved. The P2 product bug is fixed cleanly. The remaining items are non-blocking suggestions that can be addressed in follow-up PRs. The code is functional, well-tested (both server and client test suites), and the architecture is sound.

**Recommended follow-up PR(s):**
- Quick cleanup: S2 unused import, N8 repo type signature, N7 store cleanup
- Future: P3 (deduplicate create flow like the P2 delete pattern), N2 (full payload for invite-based GUILD_CREATE)
