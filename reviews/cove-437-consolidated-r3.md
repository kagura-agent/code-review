# Consolidated Review — PR #437 R3: Multi-Server Support

**PR:** kagura-agent/cove#437
**Reviewers:** 🌟 Stella · 🌠 Nova · 💫 Vega
**Round:** 3
**Date:** 2026-06-29

---

## Overall Verdict: ✅ Ready to Merge (3/3 unanimous)

All critical and blocking issues from R1–R2 are resolved. R3 fixes are clean and focused.

---

## Issue Resolution Summary

| ID | Issue | Fixed In | Status |
|----|-------|----------|--------|
| C1 | Guild creation not in transaction | R2 | ✅ Confirmed |
| C2 | GUILD_CREATE missing channels/roles | R2 | ✅ Confirmed |
| C3 | `icon` field no validation (escalated S1) | R3 | ✅ Confirmed — completely removed from API surface |
| P2 | Double-navigation on guild delete | R3 | ✅ Confirmed — DangerSection only closes panel, WS event handles cleanup |

## R3 Verification

**C3 fix:** `icon` removed from POST/PATCH body types, route handlers, client API signatures. Clean deferral to #420.

**P2 fix:** DangerSection → `onClose()` only. Store cleanup + redirect → GUILD_DELETE gateway event exclusively. Unused imports (useNavigate, useChannelStore, routes) cleaned up. Single source of truth.

## New R3 Observations (non-blocking)

- **N7** (Nova): GUILD_DELETE handler doesn't clean up roleStore/memberStore/threadStore — stale data persists
- **N8** (Nova + Stella + Vega): `GuildsRepo.update()` still accepts `icon` in type signature — dead code path
- **S8** (Vega): OverviewSection double-updates guild store (same pattern as old P3) — inconsistent with new DangerSection pattern

## Remaining Non-blocking Items (for follow-up)

From R1: S2 (unused import), S3 (saveLastChannel coupling), S4 (features hardcode), S5 (magic number), S6 (validation duplication), S7 (cascade docs), P1 (sidebar ordering), P3 (duplicate store updates)

From R2: N1-N6 (roles seeding, addGuildToUser payload, type safety, parameter sprawl, PATCH tests)

---

## Positive Notes

- **3-round review produced clean results** — each round addressed exactly what was asked, no regressions
- **P2 fix demonstrates good architectural thinking** — separating UI concerns from state management
- **Comprehensive test suite** — API tests, gateway event tests, store tests all passing
- **Spec-first development** maintained throughout
