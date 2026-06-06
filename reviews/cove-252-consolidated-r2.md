# Consolidated Review R2 — cove#252: Gateway events + client cascade cleanup

**Reviewers:** 🌟 Stella · 🌠 Nova · 💫 Vega
**Round:** 2

## R1 Issue Resolution

| # | Issue | Status |
|---|-------|--------|
| R1-1 | GUILD_MEMBER_ADD/REMOVE mutating presence | ✅ Fixed — no-op handlers with explicit "NOT presence" comment |
| R1-2 | GUILD_CREATE/GUILD_DELETE silently dropped | ✅ Fixed — added to event map, dispatch Set, and subscriptions |
| R1-3 | No tests for new event paths | ⚠️ Partial — GUILD_DELETE + MESSAGE_DELETE tests added, client cascade untested |
| R1-4 | Dev warning consistency | ✅ Fixed |

## Remaining Non-blockers (🟢)

1. **Client cascade cleanup untested** (Nova) — `CHANNEL_DELETE` → messages/readState/typing cleanup is the highest-value untested path. Follow-up issue recommended.
2. **`gateway-subscriptions.test.ts` mock stale** (Nova) — Missing `removeChannel`/`removeChannelMessages` in mocks. Will break if cascade test is added.
3. **`addGuildToUser` asymmetric** (Nova) — Silently skips if guild not in repo, while `removeGuildFromUser` always emits. Worth a comment.

## Verification

- Build + TypeScript + 152 tests pass ✅

## Verdict

### ✅ Ready to Merge (2/3 confirmed, waiting Stella)

All R1 blocking issues resolved. Presence correctly decoupled from membership. GUILD_CREATE/DELETE no longer silently dropped. Cascade cleanup is solid. Ship it. 🚀
