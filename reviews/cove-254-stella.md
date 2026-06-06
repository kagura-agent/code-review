# PR #254 Review — refactor: remove hardcoded guild ID from plugin

## Summary
This PR is directionally correct: the source fallback in `resolveAccount()` is changed from `"cove"` to `null`, `CoveRestClient.getChannels()` now requires an explicit guild ID at the TypeScript API boundary, and the gateway client records guilds from the READY payload.

I verified locally:
- `pnpm --filter openclaw-cove check` ✅
- `pnpm --filter openclaw-cove test` ✅ — 38 plugin tests passed
- `pnpm -r test` ✅ — workspace tests passed, including server `152` tests

However, I do not think this fully removes the hardcoded guild ID from the plugin/config surface yet.

## Critical Issues
1. **Hardcoded guild default remains in the plugin manifest**

   `packages/plugin/openclaw.plugin.json:23` still declares:

   ```json
   "guildId": { "type": "string", "default": "cove" }
   ```

   This is part of the plugin configuration contract. If OpenClaw applies schema defaults before `resolveAccount()`, then `section?.guildId` will still be populated as `"cove"`, so the new `section?.guildId ?? null` path in `packages/plugin/src/channel.ts:131` will not actually remove the default in normal configured installs.

   Even if defaults are not currently materialized into `cfg`, the plugin still advertises `"cove"` as the default guild ID, which contradicts the PR goal and leaves a single-guild assumption in the plugin package.

   Suggested fix: remove the `default: "cove"` from the manifest, or explicitly mark `guildId` as an optional legacy override with no default. If `null` is a valid internal value, the schema/docs should make that clear rather than defaulting to a concrete guild.

## Suggestions
- **Align the README with the new behavior.** `packages/plugin/README.md:41` still shows `guildId: cove` in the recommended config. That will encourage new installs to keep the old hardcoded guild. Prefer omitting `guildId` from the default example, with a short note that it is only needed as an explicit legacy/manual override.

- **Clarify or implement READY-based discovery.** `packages/plugin/src/types.ts:23` says the guild ID “comes from config override or discovered from READY event”, but `CoveAccount.guildId` is never updated from `gatewayClient.guilds`; the gateway client only stores `guilds` on itself (`gateway-client.ts:131`). If account-level guild discovery is intended, wire it through. If not, adjust the comment to avoid implying behavior that does not exist.

- **Add a small regression test for `resolveAccount()` without `guildId`.** The important behavior here is that an omitted config value resolves to `null`, not `"cove"`. A focused test would catch both source fallback regressions and any future schema/default reintroduction.

- **Consider runtime validation in `getChannels()`.** The TypeScript signature now requires `guildId: string`, which is good, but JS callers or `any` can still call `getChannels()` without an argument and get `/guilds/undefined/channels`. A short guard with a clear error would make the API safer.

- **Check tracked generated/legacy artifacts.** `packages/plugin/bundle.js` is tracked and still contains the old `getChannels(guildId = "cove")` / `guildId: ... ?? "cove"` behavior. It may be legacy and not used by package `main`, but if any install path still consumes it, the hardcoded guild remains there too. Either regenerate it, remove it from distribution, or document that it is obsolete.

## Positive Notes
- The source-level changes are small and easy to reason about.
- Making `getChannels(guildId: string)` explicit is the right API direction for multi-guild support.
- Capturing READY guilds in the gateway client is a useful foundation for later multi-guild behavior.
- Existing tests and typecheck pass cleanly.

## Verdict ⚠️
Request changes before merge. The main source fallback was fixed, but the plugin manifest still hardcodes `guildId` to `"cove"`, so the PR does not yet fully satisfy “remove hardcoded guild ID from plugin” / closes #237.