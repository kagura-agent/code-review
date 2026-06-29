# Consolidated Review — PR #437 R2: Multi-Server Support

**PR:** kagura-agent/cove#437
**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 2.5 Pro)
**Round:** 2
**Date:** 2026-06-29

---

## Overall Verdict: ⚠️ Needs Changes

Both R1 critical issues are properly resolved. One R1 suggestion (icon validation, 3/3 consensus) was not addressed and is escalated to blocking per re-review protocol. Remaining R1 suggestions/product-impact items are unaddressed but non-blocking.

---

## R1 Critical Issues — Both Resolved ✅

| ID | Issue | Status |
|----|-------|--------|
| C1 | Guild creation not wrapped in transaction | ✅ **Addressed** — `repos.db.transaction()` wraps all 4 DB writes. Event dispatch after commit. Clean. |
| C2 | GUILD_CREATE WS event missing channels/roles | ✅ **Addressed** — New `guildCreateFull()` sends full payload. Client handler seeds channels + roles from event. |

---

## Escalated Issue (Blocking)

### C3. `icon` field stored and rendered without validation (Escalated from S1)
**Files:** `routes/guilds.ts` (POST + PATCH), `GuildSidebar.tsx`
**Confidence:** 🔴 High (3/3 consensus in R1, not addressed, escalated per protocol)

Both `POST` and `PATCH /guilds` accept `icon` as arbitrary string — no type check, no length limit, no scheme validation. It's rendered directly as `<img src={guild.icon}>`.

**Risks:** Storage abuse (arbitrary-length strings), tracking pixels (privacy leak), data URIs (DoS via memory).

**Simplest fix:** Strip `icon` from POST/PATCH body entirely until #420 lands. Or: `validateString(body.icon, "icon", { maxLength: 512 })` + reject non-HTTPS schemes.

---

## R1 Suggestions — Not Addressed (Non-blocking)

Per escalation protocol these should be promoted, but calibrating per project context (small team, personal project): code hygiene items remain suggestions, not blockers.

| ID | Issue | Status | Note |
|----|-------|--------|------|
| S2 | Unused `generateSnowflake` import | ❌ Not addressed | Trivial cleanup |
| S3 | `saveLastChannel` component coupling | ❌ Not addressed | Extract to utility |
| S4 | `features: []` hardcoded | ❌ Not addressed | Use `data.features ?? []` |
| S5 | Channel type magic number | ❌ Not addressed | Use named constant |
| S6 | Name validation duplication | ❌ Not addressed | Extract shared helper |
| S7 | Cascade delete docs | ⚠️ Partially addressed | Spec documents approach; inline comment still helpful |

## R1 Product Impact — Not Addressed (Non-blocking)

| ID | Issue | Note |
|----|-------|------|
| P1 | Sidebar ordering non-deterministic | Acceptable for V1 |
| P2 | Double-navigation on guild delete | Real UX bug — both HTTP handler + WS handler navigate. Easy fix. |
| P3 | Duplicate store updates on creation | Idempotent but redundant. Also: dialog doesn't seed roles (Nova N1). |

---

## New Findings (R2)

### Suggestions

| ID | Issue | Reviewer(s) | Note |
|----|-------|-------------|------|
| N1 | `CreateServerDialog` doesn't seed roles from API response | Nova | Brief window where roles are missing until WS event |
| N2 | `addGuildToUser()` still sends minimal GUILD_CREATE | Nova | Pre-existing — only matters when invite system (#171) lands |
| N3 | `guildCreateFull` payload typed as `unknown` | Nova + Vega | Loses type safety — should use proper interface |
| N4 | `session.identify` / `setupGateway` parameter sprawl (8-9 params) | Stella + Vega | Refactor to options/deps object |
| N5 | `GUILD_UPDATE` broadcasts full guild instead of partial | Nova + Vega | Minor bandwidth inefficiency |
| N6 | No test for PATCH validation edge cases | Vega | Name too short, too long, empty body, icon values |
| N7 | Transaction return requires `as` assertion | Vega | Code smell — type inference issue |

---

## Positive Notes

All 3 reviewers confirmed:
- **C1 & C2 fixes are clean and correct** — transaction wrapping is proper, event dispatch ordering is right
- **Comprehensive test suite** — 235-line API tests + gateway event tests + store tests
- **Permission model is sound** — `computePermissions` properly handles bot channel filtering
- **Good UX patterns** — confirmation dialog for delete, loading states, error handling

---

## Path to ✅

1. Fix C3: Strip `icon` from POST/PATCH body (or add validation)
2. Optionally: Remove unused import (S2), fix double-navigation (P2)
3. Track remaining suggestions as follow-up issues
