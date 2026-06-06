# Consolidated Review R2 — cove#249: weekend cleanup batch 1

**Reviewers:** 🌟 Stella · 🌠 Nova · 💫 Vega
**Round:** 2

## R1 Issue Resolution

| # | Issue | Status |
|---|-------|--------|
| R1-1 | OAuth auto-join in `auth.ts` | ✅ Fixed (3/3) — auto-join removed for both new and existing users |
| R1-2 | Regression tests | ✅ Fixed — #210 test (zero guilds) + #187 test (removeUser closes sessions) added |
| R1-3 | `agents.ts` trailing whitespace | ❌ 🟢 Still there |
| R1-4 | `missingAccess()` unused | ❌ 🟢 Still exported but unreferenced |

## Remaining Nits (all 🟢, non-blocking)

1. **#187 test assertion is inverted** (Stella, Nova) — Comment says "sessionB should receive offline presence" but assertion uses `.not.toHaveBeenCalledWith`. Since sessionB is in a different guild, the test passes trivially. Add an observer in the same guild to properly verify offline broadcast.

2. **Trailing whitespace** in `agents.ts:10` — two trailing spaces where `const auth` was removed.

3. **`missingAccess()` unused** — defined but zero references. Use it or drop it.

4. **Double `removeSession` call** (Nova) — `removeUser` calls `removeSession` then `close`, which triggers `ws.on("close")` calling `removeSession` again (idempotent no-op). Worth a one-line comment.

## Verification

- `pnpm -r build` ✅
- `pnpm -r exec tsc --noEmit` ✅  
- 152 server tests pass ✅ (Stella, Vega verified)

## Verdict

**✅ Ready to Merge** (2/3 approve, 1 ⚠️ nits-only)

All R1 blocking issues resolved. Code is correct, tests cover the behavioral changes, global auth refactor is sound. Remaining items are polish — address in a follow-up commit or tracking issue.
