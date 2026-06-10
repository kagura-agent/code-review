# 🌠 Nova — Review of cove#287

**PR:** feat: add `resolver.resolveTargets` to Cove plugin
**Scope:** `packages/plugin/src/channel.ts` (+67/-0)
**Verdict:** ⚠️ Needs Changes

## Summary
Adds a `resolver.resolveTargets` implementation to `coveChannelPlugin`, mirroring the Discord plugin pattern via `resolveTargetsWithOptionalToken`. Group resolution fetches the guild's channels and matches by id or case-insensitive name; user resolution is stubbed as unsupported. The shape is reasonable and aligns with the SDK helper, but several details break the “missing token / unresolved-with-note” contract that the helper is designed to enforce, and the `mapResolved` fallback chain produces surprising values that may confuse downstream `openclaw message send`.

## Critical Issues (must fix before merge)

1. **`resolveAccount` throws on missing token — defeats `missingTokenNote`.**
   `resolveAccount(cfg, accountId)` (existing code, lines ~70–73) throws `Error("cove: bot token is required …")` when no token is configured. Because `resolveTargets` calls `resolveAccount` *before* calling `resolveTargetsWithOptionalToken`, the “missing Cove bot token” path is unreachable — the whole resolver throws instead of returning each input with `resolved: false, note: "missing Cove bot token"`. This will surface as an uncaught exception inside the resolver runtime rather than the soft-fail UX the helper promises.
   **Fix:** read token directly inside the resolver (mirroring Discord plugin), or split `resolveAccount` into a throwing form for outbound and a non-throwing form for the resolver. At minimum, wrap and return unresolved entries when token is absent.

2. **`mapResolved` fallback chain leaks `guildId` into channel fields.**
   ```ts
   id: entry.channelId ?? entry.guildId ?? undefined,
   name: entry.channelName ?? (entry.guildId && !entry.channelId ? entry.guildId : undefined),
   ```
   When a channel is **not found**, the entry still includes `guildId`, so the mapped result returns `id = guildId` and `name = guildId`. A consumer doing `openclaw message send --target <unknown>` would see a result that *looks resolved to the guild* even though `resolved: false`. That is misleading and arguably a correctness bug.
   **Fix:** only populate `id`/`name` when `entry.resolved` (i.e. a real channel match). Don't substitute `guildId` for either field on miss.

## Product Impact
- Enables `openclaw message send --channel cove --target <channelName|channelId>` to actually resolve and dispatch — net positive, unblocks #283 step 1.
- User-kind targets fail soft with a clear note (good).
- Behaviour on misconfigured tenants degrades from “soft unresolved with note” to “hard throw” (see Critical #1). For users without a configured token or `guildId`, the resolver will not behave as the SDK contract advertises.
- The misleading `id = guildId` on unresolved entries could cause downstream send tooling to display or log the guild id as if it were the target — small UX trap.

## Suggestions (non-blocking)
- **Channel cache.** `getChannels(account.guildId)` is called on every resolve. For agents that resolve frequently this is an unnecessary REST round-trip. The gateway code already re-fetches on reconnect — consider a TTL cache (e.g. 30s) keyed by `guildId`, or reuse the cache populated on reconnect (the existing `// TODO: update channel cache` hook).
- **Import style.** `import { resolveTargetsWithOptionalToken } from "openclaw/plugin-sdk/target-resolver-runtime";` lacks the `.js` extension that the rest of the file uses for relative imports. That's fine for package imports, but verify it matches the path Discord plugin uses for consistency (and that `target-resolver-runtime` is a published subpath in the SDK exports map, not just a build artifact).
- **Whitespace.** Two blank lines before `coveChannelPlugin` (pre-existing); the resolver block is fine but `// User target resolution — not supported yet` could be a JSDoc on a named helper if the user branch grows.
- **Type safety.** `cfg: any` and `id: "cove" as any` are pre-existing. The new resolver inherits the inferred types from the helper, which is good — no new `any` introduced. Worth a follow-up to type `cfg` properly across the file.
- **Helper duplication.** The user-kind branch wraps `resolveTargetsWithOptionalToken` only to return “not supported” notes. You don't actually need `resolveWithToken` semantics here — a plain `inputs.map(...)` returning the unresolved shape is shorter and avoids forcing a token requirement on a feature that has nothing to do with the token. Suggest:
  ```ts
  return inputs.map((input) => ({
    input,
    resolved: false,
    note: "user target resolution not supported",
  }));
  ```
- **Match precedence.** `ch.id === input || ch.name.toLowerCase() === inputLower` — fine, but if a channel is named after another channel's id (unlikely but possible since both are strings), id wins. Document that or leave as-is; current order is sensible.

## Testing
- PR body claims `pnpm -F openclaw-cove test` passes (53 tests), but **no new test was added** for `resolveTargets` in this diff. The resolver has at least four behavior paths worth covering:
  1. group + valid id match
  2. group + case-insensitive name match
  3. group + miss → `resolved: false, note: "channel not found"`
  4. group + missing `guildId` → `resolved: false, note: "guildId not configured"`
  5. user kind → unresolved with note
  6. missing token path (see Critical #1)
  Please add unit tests with a mocked `CoveRestClient.getChannels`.

## Positive Notes
- Reuses the shared SDK helper instead of hand-rolling token/optional logic — good consistency with Discord plugin.
- Case-insensitive name matching is the right default for human-typed targets.
- Graceful no-`guildId` branch returns a clear note instead of throwing.
- Diff is tightly scoped to a single file; no incidental refactors.
- PR description ties cleanly to issue #283 and labels itself as step 1 — clear scope control.

---
**Rating:** ⚠️ Needs Changes — primarily Critical #1 (resolver throws instead of soft-failing on missing token) and Critical #2 (guildId leaks into channel `id`/`name` on miss). Both are small mechanical fixes; happy to re-review.
