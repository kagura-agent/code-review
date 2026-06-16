# Review: PR #368 — feat(plugin): multi-account support — Discord-style SDK account resolution (#289)

## Summary

This PR moves the Cove channel plugin toward SDK-backed account discovery/resolution by wiring `createAccountListHelpers` and `resolveMergedAccountConfig`, removing env-var fallbacks from the runtime path, passing `ctx.accountId` through outbound delivery, and adjusting resolver tests. It is a good direction for multi-account support, but I do **not** think it is ready yet: the implementation still accepts the legacy root-level `channels.cove.token`/`agentId` shape despite the stated breaking-change contract, and the plugin manifest schema still rejects the new `channels.cove.accounts` config shape.

**Rating: ⚠️ Needs Changes**

## Critical Issues

1. **New `accounts` config is not allowed by the plugin manifest schema**  
   `packages/plugin/openclaw.plugin.json:17-31` still has `additionalProperties: false` and only declares root-level fields (`token`, `baseUrl`, `guildId`, `allowFrom`, `agentId`, `agentName`, `dmSecurity`). There is no `accounts` property and no `defaultAccount` property. That means the documented new config under `channels.cove.accounts` can be rejected or hidden/misrepresented by config validation/setup/UI surfaces, while the UI hint still labels root `token` as `Bot token (COVE_BOT_TOKEN)` at `packages/plugin/openclaw.plugin.json:33-36`. For a breaking config migration, this is a blocker.

2. **Legacy root-level token/account config still works, contrary to the PR contract**  
   `resolveAccount()` passes the entire channel config into `resolveMergedAccountConfig()` at `packages/plugin/src/channel.ts:68-74`. Since SDK merging omits only `accounts` by default, root-level `token`, `agentId`, and `agentName` are still merged into the resolved account and returned at `packages/plugin/src/channel.ts:76-90`. The updated test fixture also continues to use root-level `token`/`agentId` at `packages/plugin/src/resolver.test.ts:12-21`, which codifies the legacy shape. If the intended breaking change is “all account credentials must live under `channels.cove.accounts`,” this needs to reject or ignore credential-only root fields while still allowing shared defaults such as `baseUrl`/`guildId` as intended.

## Product Impact

- Users following the PR body’s new YAML example may hit config-schema validation/setup failures because `accounts` is not declared.
- Users with old root-level config may appear migrated successfully even though they are still on the removed shape, making the breaking change inconsistent and harder to diagnose later.
- Env var fallbacks are removed from runtime resolution, so deployments relying only on `COVE_BOT_TOKEN`/`COVE_AGENT_ID` will fail as expected; the error messages now point to “account missing token/agentId,” which is acceptable but should be backed by valid config schema/docs.

## Suggestions

- Add tests for real multi-account behavior: two entries under `channels.cove.accounts`, default account selection, explicit `accountId` resolution, and outbound `sendText` using the selected account.
- Add a negative test that root-level `channels.cove.token`/`agentId` does not satisfy account resolution if that is the intended breaking-change behavior.
- Consider account-scoped DM security paths/messages in `security.resolveDmPolicy()`: it currently reports `channels.cove.allowFrom` at `packages/plugin/src/channel.ts:121`, which may be misleading once allowlists can be per-account.
- Update docs/README or migration notes in the same PR so operators know the env vars and root credential fields no longer apply.

## Positive Notes

- The shift to SDK account helpers matches the platform direction and reduces bespoke account-listing logic.
- `outbound.sendText()` now uses `ctx.accountId` at `packages/plugin/src/channel.ts:208-214`, which is the important fix for sending with the correct bot identity.
- Resolver soft-fail behavior for missing credentials is preserved, avoiding hard failures during target lookup.
- The change set is small and readable; once the schema and root-credential handling are fixed, this should be straightforward to re-review.

## Testing Notes

I fetched the PR diff/details and inspected the PR head worktree. I attempted `pnpm --dir /tmp/cove-pr-368/packages/plugin test -- --runInBand`, but the isolated worktree lacked installed workspace dependency links and failed to resolve `@cove/shared`; I did not count that as a PR test failure.
