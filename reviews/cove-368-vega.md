# Code Review: PR #368 (kagura-agent/cove)

**Reviewer**: 💫 Vega  
**Verdict**: ✅ Ready  

## Summary
This PR updates the Cove plugin to support multiple accounts by integrating the `openclaw/plugin-sdk` account resolution helpers (`createAccountListHelpers`, `resolveMergedAccountConfig`). It correctly mirrors the multi-account architecture used in the Discord plugin, allowing multiple identities to be configured under `channels.cove.accounts` while successfully stripping out legacy environment variable fallbacks.

## Critical Issues
None. The code changes correctly implement the standard SDK patterns for multi-account support, and type safety is maintained throughout the refactor.

## Product Impact
- **Breaking Change**: All environment variable fallbacks (`COVE_BOT_TOKEN`, `COVE_AGENT_ID`, `COVE_AGENT_NAME`, `COVE_BASE_URL`) have been completely removed. Users must migrate to file-based config.
- **Enhancement**: Enables running multiple Cove bot accounts from a single OpenClaw instance, providing proper isolation and routing per `accountId`.
- **Nuance on Root Config**: Although the PR summary notes the root-level `token` config is removed, `resolveMergedAccountConfig` natively merges root-level properties as defaults. Legacy single-account root configs (`channels.cove.token` + `channels.cove.agentId`) will likely still evaluate correctly when `accountId` resolves to `"default"`, making the migration path softer than explicitly stated.

## Suggestions
- **Error swallowing in `resolveTargets`**: In `packages/plugin/src/channel.ts` around line 128, the `try/catch` block swallows all errors from `resolveAccount` (such as a missing `agentId`). It then falls through to `resolveTargetsWithOptionalToken(token: undefined)`, which statically outputs the note `"missing Cove bot token"`. If a user provides a token but forgets the `agentId`, this error message might be slightly confusing. Consider preserving the actual validation error in the soft-fail note if possible.

## Positive Notes
- Excellent cleanup of the test fixtures in `resolver.test.ts`. Eliminating the env var save/restore cycle makes the tests much cleaner and robust.
- Standardizing around SDK helpers significantly reduces boilerplate and keeps channel plugins behaviorally consistent.
