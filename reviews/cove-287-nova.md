# 🌠 Nova — PR #287 Round 2 Review

**Repo:** kagura-agent/cove
**PR:** #287 — feat: add resolver.resolveTargets to Cove plugin

---

## R1 Issue Status

1. **`resolveAccount()` throws on missing token — `missingTokenNote` dead code** → ✅ **Fixed**
   New `readAccountConfig(cfg)` returns `{ token?, baseUrl, guildId }` without throwing. `resolveTargets` uses it instead of `resolveAccount`, so `resolveTargetsWithOptionalToken` actually receives an `undefined` token and the `missingTokenNote` branch is now reachable. Confirmed by the new `"soft-fails when token is missing"` test.

2. **`mapResolved` leaks `guildId` into `id`/`name` on unresolved entries** → ✅ **Fixed**
   `mapResolved` now does `id: entry.resolved ? entry.channelId : undefined` and `name: entry.resolved ? entry.channelName : undefined`. Unresolved entries no longer carry `guildId` at all (it's dropped from the output shape), so there's no possibility of leakage. Verified by `"returns resolved: false for unknown channel"` and `"returns note when guildId is missing"` tests.

3. **No new tests for resolver** → ✅ **Fixed**
   New `resolver.test.ts` covers: resolve-by-id, case-insensitive name resolve, unknown channel, missing `guildId`, missing token, `getChannels` failure, and the user-kind unsupported path. Solid coverage of all branches.

4. **Stella's finding — `resolveAccount` also throws on missing `agentId`** → ✅ **Fixed** (resolver no longer calls `resolveAccount` at all).

5. **Nova/Vega — `getChannels()` errors unhandled** → ✅ **Fixed**
   Wrapped in `try/catch`; failure returns soft-fail entries with `note: "failed to fetch channels: <msg>"`. Verified by test.

---

## Summary

Round 2 cleanly addresses every R1 finding. The split between throwing `resolveAccount` (kept for outbound paths that legitimately require a token) and the new non-throwing `readAccountConfig` (used by the resolver) is the right shape. `mapResolved` is now leak-safe, errors from `getChannels` are caught, and a fresh `resolver.test.ts` exercises every branch including the previously-dead missing-token path. Only minor TypeScript hygiene nits remain.

---

## Critical Issues

None. All R1 critical issues are resolved.

---

## Suggestions

1. **`cfg: any` in `readAccountConfig`** — no justification comment. A minimal shape (`{ channels?: { cove?: { token?: string; baseUrl?: string; guildId?: string | null } } }`) would improve safety without coupling to the full config type. Non-blocking.

2. **`err: any` + `err.message` in the catch block** — if a non-Error value is thrown (e.g. a string), `err.message` is `undefined`, producing `"failed to fetch channels: undefined"`. Prefer `err instanceof Error ? err.message : String(err)`. Minor.

3. **`mapResolved` drops `guildId` even on resolved entries** — the inner `resolveWithToken` populates `guildId: account.guildId` but `mapResolved` doesn't forward it. If downstream consumers expect `guildId` on resolved targets (worth checking against the SDK contract / sibling plugins like Discord), restore it for the resolved branch only: `guildId: entry.resolved ? entry.guildId : undefined`. Otherwise drop the unused field from the inner type to avoid confusion. Non-blocking but worth a glance.

4. **Inline result type duplication** — the `Array<{ input; resolved; channelId?; channelName?; guildId?; note? }>` shape is declared inline at the `resolveWithToken` callsite. Extracting a named type would improve readability and keep `mapResolved`'s contract explicit. Stylistic.

5. **Test fixture realism** — `fakeChannels` includes Discord-shaped fields (`permission_overwrites`, `rate_limit_per_user`, etc.) but the resolver only touches `id` and `name`. Trimming to the used fields would make tests easier to maintain. Stylistic.

6. **`"soft-fails when getChannels throws"` test relies on retry internals** — the loop `for (let i = 0; i < 20; i++) await vi.advanceTimersByTimeAsync(30_000)` couples the test to the retry policy of `getRestClient`. If the retry schedule changes, this test gets brittle. Consider mocking at a higher level or asserting on the eventual outcome with `vi.runAllTimersAsync()`. Non-blocking.

---

## Positive Notes

- ✨ **Clean separation of concerns** — `readAccountConfig` vs `resolveAccount` precisely captures "resolver may operate without credentials" vs "outbound requires credentials". This is the right abstraction.
- ✨ **Defense in depth on `mapResolved`** — even with `entry.resolved` set, fields are still gated by the boolean. Easy to maintain.
- ✨ **User-kind path returns soft-fail with a clear note** instead of throwing — good forward-compatibility for when user resolution is implemented.
- ✨ **All R1 findings actually addressed** — including Stella's `agentId` and the unique error-handling notes from Nova/Vega. Disciplined response to review feedback.
- ✨ **Test for the previously-dead missing-token branch** — explicitly proves the regression is fixed, not just plausibly fixed.

---

## Rating: ✅ Ready

Suggestions are all non-blocking polish. Safe to merge.
