# Consolidated Review R5: PR #316 — channel permission overwrites (bot visibility)

**Reviewers:** 🌟 Stella ✅ | 🌠 Nova ✅ | 💫 Vega ⏱️ failed

---

## ALL issues resolved ✅

| ID | Finding | Final Status |
|----|---------|-------------|
| C1 | Admin auth on permission routes | ✅ |
| C2 | REST gating (VIEW_CHANNEL) | ✅ All routes gated + negative tests |
| C3 | Negative auth tests | ✅ Comprehensive (12+ tests with error codes) |
| C4 | Dispatcher event filtering | ✅ CREATE/DELETE intentionally unfiltered |
| C5 | BigInt validation | ✅ |
| READY leak | ✅ |
| Channel route tests (R4 gap) | ✅ 4 new tests added |

## R5 Verification

Both reviewers confirmed the 4 new negative tests in `permissions.test.ts`:
- `denied bot cannot GET /channels/:id` → 403
- `denied bot cannot PATCH /channels/:id` → 403
- `denied bot cannot DELETE /channels/:id` → 403
- `denied bot gets filtered guild channel list` → channel excluded from response

**223 tests pass. Build passes. CI green.**

## Suggestions (non-blocking, follow-up)

1. Add comment in `dispatcher.ts` explaining CREATE/DELETE intentional broadcast asymmetry (both reviewers)
2. Centralize `VIEW_CHANNEL` bigint constant — currently in 3 places (both reviewers)
3. Assert Discord error codes (50001/50013) in channel route tests (Nova)
4. Add positive test: bot WITH VIEW_CHANNEL CAN GET /channels/:id (Nova)

## Journey: R1 → R5

5 rounds, from 5 critical issues to fully resolved:
- R1: ❌ 5 criticals (self-grant, REST bypass, missing tests, event leak, BigInt crash)
- R2: ⚠️ C1/C5 fixed, C2 partially (2/10 routes), READY leak found
- R3: ⚠️ C2 re-escalated (GET/PATCH/DELETE /channels/:id), lifecycle bugs found
- R4: ⚠️ Code 100% fixed, Nova approved, Stella/Vega wanted tests
- R5: ✅ **Ready — tests added, all clear**

## Overall Verdict: ✅ Ready — 2/2 unanimous (Vega failed to run)
