# PR #369 Round 2 Re-review — Stella

**Verdict: ⚠️ Needs Changes**

I re-reviewed the updated diff and checked each Round 1 item. The manifest blocker is fixed, but several Round 1 items remain, and there is a more serious account-resolution correctness issue in the new SDK migration path.

## Blocking / needs changes

### 1. Default account selection is not applied inside `resolveAccount`

`resolveAccount(cfg, accountId)` passes `accountId ?? undefined` directly to `resolveMergedAccountConfig`:

```ts
resolveMergedAccountConfig({ channelConfig, accounts: channelConfig?.accounts, accountId: accountId ?? undefined })
```

When `accountId` is omitted/null and the config uses the new format:

```yaml
channels:
  cove:
    defaultAccount: ruantang
    accounts:
      ruantang:
        token: ...
        agentId: ...
```

`resolveMergedAccountConfig` does not select `defaultAccount`; with `accountId` undefined it only merges the top-level channel config and no account entry. That means `resolveAccount(cfg)` can report missing token/agentId even though a default account is configured.

This is not Discord-style behavior: Discord resolves `accountId ?? resolveDefaultDiscordAccountId(cfg)` before merging account config. Cove should do the same, and return/store the resolved account id rather than `null` for account-scoped configs.

Suggested shape:

```ts
const resolvedAccountId = accountId ?? resolveDefaultCoveAccountId(cfg);
const merged = resolveMergedAccountConfig({
  channelConfig,
  accounts: channelConfig?.accounts,
  accountId: resolvedAccountId,
});
```

This also needs a regression test for `defaultAccount` and for single named-account fallback.

### 2. Round 1 resolver error swallowing remains and is now more severe

The resolver still catches every `resolveAccount` error and replaces it with `account = undefined`:

```ts
try {
  account = resolveAccount(cfg, accountId);
} catch {
  account = undefined;
}
```

This means a configured account with `token` but missing `agentId` is reported as `missing Cove bot token`, which is misleading. It also hides whether the requested account id was unknown, whether `agentId` was missing, or whether another config error occurred.

Round 1 called this out as a non-blocking suggestion / soft-fail problem; since it is still unaddressed, I am escalating it. Please catch only the specific missing-token case if resolver soft-fail is required, or preserve the actual actionable failure note.

## Round 1 checklist

1. **Plugin manifest schema rejects `accounts` field** — ✅ Addressed. `channels.cove.schema.properties.accounts` is now declared, so root `additionalProperties: false` no longer rejects `accounts`. `defaultAccount` was also added.
   - Minor schema note: per-account objects do not set `additionalProperties: false`, unlike many bundled channel schemas, so typos inside account configs will be accepted silently.

2. **`resolveDefaultCoveAccountId(cfg) ?? "default"` dead code** — ❌ Still present. SDK `createAccountListHelpers(...).resolveDefaultAccountId` returns a string because `listAccountIds` falls back to `default` when empty. This should be simplified unless the SDK contract changes.

3. **Narrow unconditional catch in `resolver.resolveTargets`** — ❌ Not addressed; see blocking item 2.

4. **`account!.guildId!` non-null assertions are fragile** — ❌ Still present. They are currently protected indirectly by the optional-token helper, but this remains brittle and unnecessary once `account` is narrowed explicitly.

5. **Error messages lost actionability** — ⚠️ Partially addressed for `resolveAccount` (`account missing token/agentId` includes accountId), but messages still do not tell the user which config path to set, and resolver errors still collapse to `missing Cove bot token`.

6. **Error swallowing in resolver soft-fail produces misleading `missing token` message** — ❌ Not addressed; escalated above.

7. **Add multi-account tests** — ❌ Not addressed. Current tests still only exercise top-level `channels.cove.token/baseUrl/guildId/agentId` and do not cover `accounts`, `defaultAccount`, per-account inheritance, or outbound `ctx.accountId` routing.

8. **Test fixture still uses root-level config shape** — ❌ Still true. `makeCfg()` continues to place credentials at `channels.cove.*`, despite the PR description saying all accounts must now be under `channels.cove.accounts`.

## Fresh review notes

- The schema now still permits root-level `token` and `agentId`, and runtime merging still accepts them as shared/default credentials. That may be intentional for SDK-style inheritance, but it contradicts the PR description's stated breaking change that root-level single-account config was removed. Please align the implementation, schema, tests, and PR docs.
- The plugin does not appear to expose `enabled` on `CoveAccount` or implement `config.isEnabled`, so `accounts.<id>.enabled: false` is accepted by schema but ignored by runtime startup. If account-level `enabled` is part of the SDK account shape, Cove should honor it or remove it from the schema.

## Verification run

- `pnpm -F openclaw-cove test -- resolver.test.ts` passed (55 tests), but these tests do not cover the new multi-account behavior above.
