# PR #369 Round 3 Re-review — Stella

**Verdict: ⚠️ Needs Changes**

The Round 2 critical items are mostly addressed, but the implementation still violates a core requirement from #289: **old root-level single-account credentials are still accepted and even covered by existing tests**. I would not mark this ready until that is fixed or the design is explicitly changed.

## Findings

### 1. Major — Explicit `accounts` are still not enforced; legacy root credentials still work

#289 says “No backward compatibility” and “All accounts must be explicitly declared under `channels.cove.accounts`”; root-level `channels.cove.token` / `agentId` / `agentName` are supposed to be dropped.

Actual code still merges root-level credentials into every account:

- `packages/plugin/src/channel.ts:64-70` passes the whole `channelConfig` into `resolveMergedAccountConfig` without omitting `token`, `agentId`, or `agentName`.
- `packages/plugin/openclaw.plugin.json:21,28-29` still exposes root-level `token`, `agentId`, and `agentName` in the schema.
- `packages/plugin/src/resolver.test.ts:12-20` still builds its base fixture using root-level `token` and `agentId`, so the test suite currently enshrines the old single-account config path.

Consequence: a config like this still resolves successfully as account `default`, with no explicit account entry:

```yaml
channels:
  cove:
    token: old-token
    agentId: old-agent
```

It also means an account with no per-account token/agentId can inherit root credentials, despite the issue saying those are required per-account. This is the main blocker.

Recommended fix: remove root-level credential fields from the manifest and prevent `resolveMergedAccountConfig` from inheriting credential identity fields, e.g. omit `token`, `agentId`, and likely `agentName` from root-level merge while still allowing shared defaults such as `baseUrl`, `guildId`, `allowFrom`, and `dmSecurity`.

### 2. Minor / claimed fix incomplete — `account!` non-null assertions remain

The R3 summary says the `account!` non-null assertions were extracted to local variables. They still exist in the resolver path:

- `packages/plugin/src/channel.ts:122`
- `packages/plugin/src/channel.ts:130`
- `packages/plugin/src/channel.ts:131`

This is probably safe because `resolveTargetsWithOptionalToken` only invokes `resolveWithToken` when `account?.token` is present, but the claimed cleanup was not actually completed. If keeping this shape, assign `const resolvedAccount = account;` after successful resolution or inside the token path and use that instead.

### 3. Minor — New tests are meaningful but duplicated and miss the key negative case

The added tests do verify distinct account resolution, defaultAccount, merging, and forwarded error messages. However, the suite now contains two near-duplicate multi-account describe blocks (`resolveAccount — multi-account` and `multi-account resolution`), and it does not test the most important contract: root-level `token`/`agentId` should no longer resolve a usable account.

Given the design decision in #289, please add negative tests for:

- no `channels.cove.accounts` + root `token`/`agentId` should fail
- account entry missing `token` should not inherit root `token`
- account entry missing `agentId` should not inherit root `agentId`

## Fix verification from previous rounds

- ✅ Plugin manifest now includes `accounts`, `defaultAccount`, and `reactionNotifications`.
- ✅ Per-account schema now has `additionalProperties: false`.
- ✅ Resolver missing-token soft-fail now forwards the real `resolveAccount` error instead of always saying “missing Cove bot token”.
- ✅ `resolveAccount` applies `defaultAccount` when `accountId` is omitted.
- ✅ Error messages include config path hints.
- ⚠️ Tests were added, but they are partly duplicated and still rely on root-level legacy credentials.
- ⚠️ `account!` cleanup was claimed but not fully done.

## Local verification

Ran:

```bash
pnpm -F openclaw-cove test -- resolver.test.ts
pnpm -F openclaw-cove check
```

Both passed.
