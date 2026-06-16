# 🌠 Nova — PR #368 Review (cove)

**PR:** feat(plugin): multi-account support — Discord-style SDK account resolution (#289)
**Repo:** kagura-agent/cove
**State:** CLOSED (head `17d5b73`, base `ca487d6`)
**Diff size:** +44 / -51 across 2 files

Verdict: **⚠️ Needs Changes** — one real blocker in the plugin manifest, plus a couple of correctness regressions worth fixing before reopening / re-merging.

---

## 1. Summary

This PR rewires `packages/plugin/src/channel.ts` to use the OpenClaw SDK helpers `createAccountListHelpers("cove")` and `resolveMergedAccountConfig(...)` so Cove finally supports multiple bot accounts the same way the Discord plugin does. It also drops three things at once: the `readAccountConfig()` helper, all `COVE_*` env‑var fallbacks, and the root‑level `channels.cove.token` / `agentId` / `agentName` single‑account shape — every account must now live under `channels.cove.accounts.<id>`. The SDK wiring itself is correct, the new test fixture is reasonable, the Discord‑style flow is genuine (not cargo‑cult), and the soft‑fail in `resolver.resolveTargets` is a nice touch. But the plugin manifest was not updated to match this new config shape, so config validation will reject the new `accounts` map outright. Combined with the breaking removal of every fallback path, this can't merge as‑is.

---

## 2. Critical Issues (blocking)

### C1. **Plugin manifest schema rejects the new `accounts` field — config validation will fail.** 🔴

File: `packages/plugin/openclaw.plugin.json` (lines 14–34, untouched in this PR).

```json
"channelConfigs": {
  "cove": {
    "schema": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "token": {...},
        "baseUrl": {...},
        "guildId": {...},
        "allowFrom": {...},
        "agentId": {...},
        "agentName": {...},
        "dmSecurity": {...}
      }
    }
  }
}
```

The other reviewer is correct, and this is a real, user-visible blocker. Tracing the SDK in `node_modules/openclaw/dist/io-DnGGugrj.js`:

- `collectChannelSchemaMetadata(...)` reads `record.channelConfigs[channelId].schema` from each plugin manifest and registers it as the validation schema for `channels.<channelId>` (lines ~2400–2415).
- `validateConfigObjectWithPluginsBase(...)` builds a `channelSchemas` map from `GENERATED_BUNDLED_CHANNEL_CONFIG_METADATA` plus `collectChannelSchemaMetadata(info.registry)` (lines ~3070–3083).
- Then for every key under `config.channels`, it runs `validateJsonSchemaValue({ schema: channelSchema, value: config.channels[trimmed], applyDefaults: true })` (lines ~3270–3290) and turns every error into an issue at `channels.<id>.<path>`.

There is no SDK code path that "auto-injects" an `accounts` property, no `expandAccountsSchema` pass, no special-casing for channel schemas with `additionalProperties: false`. Compare with `@openclaw/discord`'s `openclaw.plugin.json`, which **explicitly** declares an `accounts` property (full per‑account sub-schema mirroring root keys) plus `defaultAccount`, `name`, `enabled`, etc. The bundled `clickclack`, `feishu`, `googlechat`, `imessage`, `irc` (etc.) schemas embedded in `io-DnGGugrj.js` all do the same — every one of them ships a hand-written `accounts: { type: "object", propertyNames: { ... }, additionalProperties: { type: "object", properties: { ... }, additionalProperties: false } }` block.

Concrete impact: with the schema as it stands, the moment a user writes the new YAML the PR description recommends:

```yaml
channels:
  cove:
    baseUrl: "http://localhost:3400"
    accounts:
      kagura:
        token: "..."
        agentId: "kagura"
        ...
```

`validateConfigObjectWithPluginsBase` will produce an issue like `channels.cove.accounts: invalid config: must NOT have additional properties` and the gateway will refuse to start (or, depending on call site, drop the cove channel from the runtime config). Worse: now that this PR has also deleted every env-var and root-level fallback, there is no escape hatch — the *only* way to configure Cove is the very shape the manifest forbids.

In other words: **after this PR lands, valid configs are unreachable.** The runtime tests (`pnpm test`) pass because they call `resolveAccount` / `resolveTargets` directly with a hand-built `cfg` object that bypasses the manifest validator entirely.

**Required fix:** extend `packages/plugin/openclaw.plugin.json` to declare:
- `accounts`: `{ type: "object", propertyNames: { type: "string" }, additionalProperties: <per-account schema> }`
- `defaultAccount`: `{ type: "string" }` (since `resolveListedDefaultAccountId` reads `channelConfig.defaultAccount`)
- `enabled` / `name` (for parity with how other plugins gate accounts and for `describeAccountSnapshot`)

The per-account schema should mirror the root channel schema's keys (`token`, `baseUrl`, `guildId`, `allowFrom`, `agentId`, `agentName`, `dmSecurity`) — and probably make `additionalProperties: false` on the inner object too, to stay consistent with the rest of the channel.

Suggest also adding an end-to-end test that runs the validator (e.g. `validateConfigObjectWithPlugins` from the SDK, or whatever the server's `validateConfig` boundary is) against a fixture that uses the new `accounts:` block. Without this, the same regression can ship again.

### C2. **`resolveDefaultCoveAccountId` does not return `null` — the `?? "default"` fallback in `setup.resolveAccountId` is dead code, and the apparent intent is wrong.** 🟠

File: `packages/plugin/src/channel.ts:111`

```ts
setup: {
  resolveAccountId: (cfg) => resolveDefaultCoveAccountId(cfg) ?? "default",
  ...
}
```

Reading the SDK (`account-helpers-B8hw5Y0t.js` `resolveListedDefaultAccountId`), `resolveDefaultAccountId` is built so it **always** returns a string — when `accountIds` is empty it falls through to `params.accountIds[0] ?? "default"`. Combined with `listAccountIds` which itself defaults `fallbackAccountIdWhenEmpty: DEFAULT_ACCOUNT_ID`, the result is *always* a non-empty string. So `?? "default"` is unreachable.

That alone is just dead code. The deeper concern is **what value the helper actually returns when no accounts are configured**. With zero configured accounts and no `implicitDefaultAccount` option (the PR passes none — Discord and Feishu pass `implicitDefaultAccount: { channelKeys: ["token"] }` to support legacy single-account configs), `listAccountIds` returns `["default"]` and `resolveDefaultAccountId` returns `"default"`. Then `resolveAccount(cfg, "default")` is called, finds no `accounts.default` entry, falls back to merging only the root-level channel config — but the root-level schema has been intentionally stripped of `token`/`agentId` from the user's perspective by the PR description, and `resolveAccount` will throw `"cove: account missing token (accountId=default)"`.

Net result: even if you fix C1, a misconfigured user with no `accounts:` map gets a confusing error pointing at `accountId=default` for a default that they never declared.

**Suggested fix (one of):**

a. Pass `implicitDefaultAccount: { channelKeys: ["token"] }` to `createAccountListHelpers("cove", { ... })` so a root-level token (if the manifest re-allows it) keeps working as a single-account config — matching Discord exactly.

b. Or, if the breaking-change story is firm and root-level token is gone forever, refuse to start cove when `accounts` is empty with a clear error (`"cove: channels.cove.accounts must declare at least one account"`) instead of letting it degrade into a default-id NPE-flavored message. The `setup.resolveAccountId` and the `config.listAccountIds` paths are the right place to surface that.

The current code does neither — it pretends to fall back, but the fallback can never produce a working bot.

---

## 3. Product Impact

- **Breaking change confirmed.** Any existing deployment relying on `channels.cove.token` or any of `COVE_BOT_TOKEN` / `COVE_AGENT_ID` / `COVE_AGENT_NAME` / `COVE_BASE_URL` will stop working after upgrading. The PR description calls this out, but there is **no migration helper, no doctor warning, no startup log line** pointing users at the new shape. For a user-facing channel plugin, please add at minimum:
  - A README/CHANGELOG note (none touched in this PR).
  - A startup log warning in `gateway.startAccount` when `cfg.channels.cove.token` is set at root (legacy shape) so users discover the migration without grepping commits.

- **Error messages got worse for the empty/misconfigured case.** Before: `"cove: bot token is required (set channels.cove.token or COVE_BOT_TOKEN env)"` — that string told users exactly what to do. After: `"cove: account missing token (accountId=default)"` — this references an `accountId=default` that the user never typed and gives no path forward. Consider including a hint like `"set channels.cove.accounts.<id>.token"` in the thrown error.

- **C1 means the bot can't actually run on a fresh install.** If a new user follows the PR description verbatim, the gateway rejects the config. That is full breakage, not "could be cleaner."

- **Multi-bot identity routing in `outbound.sendText` is genuinely fixed.** Previously `resolveAccount(cfg)` was always called with no accountId, so even if there had been two bots wired up they would have used identical credentials. The new `resolveAccount(ctx.cfg, ctx.accountId)` is a real correctness improvement once C1/C2 are sorted.

---

## 4. Suggestions (non-blocking)

1. **`resolver.resolveTargets` swallows non‑credential errors.** `channel.ts:130–135`:
   ```ts
   try {
     account = resolveAccount(cfg, accountId);
   } catch {
     // Missing token or agentId — fall through with null to soft-fail
   }
   ```
   The catch is unconditional, but `resolveAccount` only throws for missing token / agentId — at least today. If anyone later adds e.g. a baseUrl URL parse, an `accounts` lookup error, or an account-disabled check, that error gets eaten and turned into a misleading `"missing Cove bot token"` note. Narrow the catch by checking `err.message` for the credential errors, or by introducing typed errors (`MissingCoveCredentialsError`).

2. **`account!.guildId!` non-null assertions in the resolver.** `channel.ts:148, 151, 171`:
   The assertions are correct *today* because the surrounding `if (!account?.guildId) return ...` and `resolveTargetsWithOptionalToken` token check guarantee non-null before they're used, but this is fragile. A small refactor — pull `account` and `account.guildId` into local consts after the guards — removes the `!`s and avoids future "looks fine, refactor breaks it" bugs.

3. **`dmPolicy: merged?.dmSecurity` field-name asymmetry.** The channel-level schema in the manifest exposes `dmSecurity`, but the runtime `CoveAccount.dmPolicy` consumes it. Discord et al. expose `dmPolicy` directly on the channel config. Consider renaming (with backward-compat read of `dmSecurity` if you want zero churn for existing users — though there are arguably none, given C1).

4. **Tests don't exercise the new helpers' edge cases.** `resolver.test.ts` was just adapted to the shape change. Worth adding:
   - A test that puts two accounts under `accounts:` and asserts `listCoveAccountIds(cfg)` returns both.
   - A test that asserts `resolveAccount(cfg, "kagura")` deep-merges per-account `baseUrl` overrides over the root.
   - A test that asserts the resolver soft-fails *cleanly* when `accounts` is missing entirely (i.e. nothing throws with an accountId-default error).

5. **`outbound.sendText` builds a fresh REST client keyed by `${baseUrl}::${token}` (line ~52).** For multi-account this means N REST clients, but `restClients` is a process-wide `Map` that never evicts. Not new in this PR, but multi-account makes it more visible. Consider an LRU cap or per-account lifecycle binding.

6. **`channel.ts:110` declares `defaultAccountId: resolveDefaultCoveAccountId` in `config`, but `setup.resolveAccountId` reimplements the same call with a `?? "default"`.** Pick one. If `config.defaultAccountId` is the canonical SDK contract, drop the duplicated call in `setup.resolveAccountId` (or have it just `return resolveDefaultCoveAccountId(cfg);`).

---

## 5. Positive Notes

- **Clean structural alignment with Discord.** `createAccountListHelpers("cove")` + `resolveMergedAccountConfig({ channelConfig, accounts, accountId })` is exactly how the SDK is intended to be consumed; this is a real reduction in custom code, not just a rename.
- **`outbound.sendText` correctly threads `ctx.accountId`** — the previous code would have silently sent everything as the same bot identity in a multi-account world. This is the PR's main payoff and it's done right.
- **`resolver.resolveTargets` soft-fail pattern** is properly aligned with `resolveTargetsWithOptionalToken`'s contract; the previous direct call to `readAccountConfig` was muddier.
- **Test-fixture update is minimal and on-target** (just adding `agentId: "test-agent"` and removing the env-var save/restore dance).
- **The diff is small and focused** — +44/-51, two files. Easy to reason about, easy to revert.

---

## TL;DR

The runtime code is solid and the SDK migration is the right move. But **the plugin manifest schema (`packages/plugin/openclaw.plugin.json`) was not updated** to declare `accounts` / `defaultAccount`, and combined with the breaking removal of all root-level / env-var fallbacks, that means *every* config that follows the new documented shape will be rejected by `validateConfigObjectWithPlugins`. Add an `accounts` block to the manifest schema (mirroring Discord/Feishu/Imessage), wire `implicitDefaultAccount` or fail-fast properly when no accounts are declared, and the PR is good to ship.
