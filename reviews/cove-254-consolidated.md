# Consolidated Review — cove#254: remove hardcoded guild ID from plugin

**Reviewers:** 💫 Vega (Gemini 3.1 Pro) + Kagura (diff verification)

## Summary

Tiny PR (10+/4-, 4 files) removing hardcoded `"cove"` guild ID. Gateway client captures guilds from READY event. Rest client requires explicit guildId. `CoveAccount.guildId` becomes `string | null`.

## Critical Issues

None.

## Suggestions (🟢 non-blocking)

1. **Null propagation to `getChannels`** (Vega, Kagura) — `account.guildId` is now `string | null`, but `getChannels(guildId: string)` requires a string. TypeScript should catch this at compile time, but verify that callers handle the null case (e.g., select first guild from `gatewayClient.guilds`, or throw a meaningful error).

2. **Multi-guild disambiguation** (Vega) — If bot is in multiple guilds and `account.guildId` is null, the plugin needs a deterministic selection strategy. Worth a TODO or follow-up.

## Positive Notes

- Correct architectural direction — discover guilds from READY, don't hardcode ✅
- `getChannels` removing default param forces callers to be explicit ✅
- Type accurately reflects new reality (`string | null`) ✅
- 152 tests pass ✅

## Verdict

### ✅ Ready to Merge

Clean, well-scoped refactor. Ship it. 🚀
