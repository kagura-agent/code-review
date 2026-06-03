# PR #165 — fix: useBotStore type mismatch, auth cleanup, dead code removal

**Repo**: kagura-agent/cove
**Reviewed**: 2026-06-04
**Files**: 14 (+48/-65)
**FlowForge**: #3460

## Verdicts
| Reviewer | Verdict |
|----------|---------|
| Stella | ⚠️ Needs Changes |
| Nova | ✅ Ready |
| Vega | ✅ Ready |

## Overall: ⚠️ Needs Changes

## Key Findings
1. **Build failure** (Stella) — `c.get("botUser")` untyped in Hono → tsc error. Tests pass (runtime transpilation) but `pnpm -r build` fails.
2. **Dead 401 path** (Nova+Vega) — `/api/v10/users/@me` redundant auth check
3. **SELECT * in findByToken** (Nova) — minor security smell

## Reviewer Assessment
- Stella: 21/21 (100%). Only reviewer who ran `pnpm -r build` and caught a real tsc failure. Critical catch.
- Nova: 21/21 (100%). Most detailed suggestions. Noted the cast workaround but didn't flag as build-breaking.
- Vega: 15/21 (71%). 4th consecutive clean run. Good auth redundancy observation.

## Process Notes
- Stella's build test caught what Nova and Vega missed — value of running actual compilation, not just tests.
- Split verdict (1 ⚠️ / 2 ✅) correctly resolved toward ⚠️ because Stella had evidence (actual tsc output).
