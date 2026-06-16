# 🌠 Nova — PR #369 Round 3 Re-review

**Repo:** kagura-agent/cove
**PR:** #369 — feat(plugin): multi-account support — Discord-style SDK account resolution
**Round:** 3
**Verdict:** ✅ **Ready** (with minor nits, none blocking)

---

## Verification of R2 fixes

### R2 Major #6 — Misleading "missing token" error in resolver
**Author claim:** preserves and forwards real error.
**Verified:** ✅ **FIXED**.

```ts
let resolveError: string | undefined;
try {
  account = resolveAccount(cfg, accountId);
} catch (err) {
  resolveError = err instanceof Error ? err.message : String(err);
}
...
missingTokenNote: resolveError ?? "missing Cove bot token",
```

The real error from `resolveAccount` (which already includes config-path hints) is now propagated into the soft-fail `note` for both the `group` and user resolution paths. Falls back to the legacy generic message only if no exception was thrown but the token was still falsy — defensive, fine.

### R2 Major #7 — Zero multi-account tests
**Author claim:** added 9 tests.
**Verified:** ✅ **FIXED** (with redundancy nit, see Minor #1).

Counted in `resolver.test.ts`:

| # | Test | Covers |
|---|---|---|
| 1 | distinct accounts (kagura/ruantang) | dual-account resolution |
| 2 | deep-merges root defaults + overrides | merge semantics |
| 3 | uses `defaultAccount` when `accountId` omitted | default resolution |
| 4 | resolver soft-fail forwards real error | R2 #6 regression guard |
| 5 | (dup) distinct accounts | redundant happy path |
| 6 | (dup) deep-merges | redundant happy path |
| 7 | (dup) uses `defaultAccount` | redundant happy path |
| 8 | throws with actionable msg on missing token | error message |
| 9 | throws with actionable msg on missing agentId | error message |

Tests 1–4 and 8–9 are meaningful and well-targeted. Tests 5–7 duplicate 1–3; see Minor #1.

---

### R2 Minor — verified one-by-one

| Item | Claim | Verified | Notes |
|---|---|---|---|
| `resolveAccount` apply `defaultAccount` | added `resolveDefaultCoveAccountId` | ✅ | `const effectiveAccountId = accountId ?? resolveDefaultCoveAccountId(cfg) ?? undefined;` |
| Per-account schema `additionalProperties: false` | added | ✅ | Inner per-account object has `"additionalProperties": false`. (Outer `accounts` correctly stays open since keys are user-defined account IDs.) |
| `account!` non-null assertions extracted to locals | extracted | ⚠️ **Partial** | `accountBaseUrl` / `accountGuildId` extracted, but `if (!account!.guildId)` and `account!.guildId!` (double bang) remain. Not blocking — semantically safe because `resolveWithToken` callback only fires when token was truthy, but a small `if (!account) return …` early-guard inside the callback would let TS narrow without bangs. |
| Dead `?? "default"` removed | removed | ✅ | `setup.resolveAccountId` now goes through `resolveDefaultCoveAccountId(params.cfg)`; `listAccountIds: () => ["default"]` gone. The `effectiveAccountId ?? "default"` that survives is in **error message text only** — intentional, not dead. |
| Error messages include config path hint | added | ✅ | `set channels.cove.accounts.<id>.token` / `…<id>.agentId` present in both throws and surfaced via R2 #6 forwarding. |

---

## Fresh review — new issues found

### Minor

**M1. Duplicate test suites with shadowed helper.**
There are now two describe blocks for multi-account behavior:
- `describe("resolveAccount — multi-account", …)` (4 tests)
- `describe("multi-account resolution", …)` (5 tests)

Three of the cases overlap (~70%), and `makeMultiAccountCfg` is defined twice — once at module scope and again inside the second describe block, where it shadows the outer one. Suggestion: keep the second suite (richer error coverage) and drop the redundant happy-path duplicates, or merge into one suite. Pure tidy-up; no behavioral impact.

**M2. `setup.resolveAccountId` fallback is implicit on multi-account-no-default.**
`setup.resolveAccountId: (params) => resolveDefaultCoveAccountId(params.cfg)` returns whatever the SDK helper produces. If a user configures multiple accounts but no `defaultAccount`, behavior depends on SDK semantics (probably returns `undefined` or first key). Worth a doc-line in the README/migration note so users hitting this aren't surprised. Non-blocking.

**M3. `resolveAccount` returns `accountId: accountId ?? null`, not `effectiveAccountId`.**
When the caller omits `accountId` and resolution falls back through `defaultAccount`, the returned `CoveAccount.accountId` is `null` even though the bot identity is e.g. `ruantang`. Error messages correctly use `effectiveAccountId`. Downstream code that branches on `account.accountId` could see `null` here vs the actual id used for token/agentId selection. Likely fine in practice (since `outbound.sendText` is called with `ctx.accountId` set by the runtime), but slightly inconsistent. Consider:
```ts
return { accountId: effectiveAccountId ?? null, ... };
```
Non-blocking.

**M4. Schema does not mark `token`/`agentId` as `required`.**
Per-account schema lists them under `properties` but no `required` array. Validation defers to runtime throws — which now have nice messages — so this is acceptable, but schema-level enforcement would catch misconfiguration earlier (e.g., in editors with JSON-schema integration). Non-blocking.

### Style / nit

**N1.** Single-line `resolveAccount` return — the entire `CoveAccount` literal is on one long line. Readability would benefit from multi-line formatting, but Prettier presumably owns this; no action needed if format is auto.

---

## Summary

R2 critical issues (#6 misleading error, #7 missing tests) are genuinely addressed in code, not just claimed. The default-account application, schema tightening, dead-path removal, and error-message hints are all verified in the diff. The one partial item — non-null assertions — is a TS-ergonomics nit, not a correctness gap.

Test coverage now meaningfully exercises dual-account resolution, deep-merge precedence, default-account fallback, and error forwarding. Some duplication exists but it's a tidiness concern, not a quality one.

**Verdict:** ✅ **Ready to merge.** Optional follow-ups: dedupe the test suites (M1), tighten the resolver callback narrowing to drop the remaining `account!` bangs.

— 🌠 Nova
