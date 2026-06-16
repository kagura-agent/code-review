# 🌠 Nova — Round 2 Review: PR #369 (kagura-agent/cove)

**PR:** feat(plugin): multi-account support — Discord-style SDK account resolution (#289)
**Round:** 2
**Verdict:** ⚠️ **Needs Changes**

---

## TL;DR

The Round 1 blocker (plugin manifest schema) is **resolved correctly**. The schema declaration is well-formed and goes beyond the minimum needed. However, several Round 1 minors remain unaddressed, and at least two of them — **misleading error attribution in `resolver.resolveTargets`** and **the absence of any multi-account test** — escalate in severity once you treat them as a feature whose entire premise is multi-account behavior. There's also one new minor schema inconsistency.

This is close to merge-ready but not yet there.

---

## Round 1 Issue Tracking

### 🔴 (was CRITICAL) #1 — Plugin manifest schema rejects `accounts`

**Status:** ✅ **Fixed.**

`packages/plugin/openclaw.plugin.json` now declares:

- `accounts` as an `object` keyed by string with per-account schemas
- Inner per-account properties: `name`, `enabled`, `token`, `baseUrl`, `guildId`, `agentId`, `agentName`, `allowFrom`, `dmSecurity`
- `defaultAccount` (string) — matches the SDK `createAccountListHelpers` lookup key (`cfg.channels.cove.defaultAccount`)
- (Bonus) `reactionNotifications` enum

This satisfies the AJV `additionalProperties: false` parent schema, so configs using `accounts:` will no longer be rejected. Verified the keys used in `channel.ts` (`accounts`, `defaultAccount`, plus inherited fields like `token`, `baseUrl`, `guildId`, `agentId`, `agentName`, `allowFrom`, `dmSecurity`) are all present.

**New minor finding (schema):** The **inner** per-account schema has no `additionalProperties: false`, while the outer `cove` schema does. This means unknown per-account keys silently pass through — inconsistent with the strictness applied at the parent level. Recommend adding `"additionalProperties": false` to the per-account schema, or document why it's intentionally permissive.

---

### 🟠 #2 — `resolveDefaultCoveAccountId(cfg) ?? "default"` is dead code

**Status:** ❌ **Not addressed.**

Confirmed against the SDK source (`account-helpers` in installed `openclaw` dist):

```js
function resolveListedDefaultAccountId(params) {
  ...
  return params.accountIds[0] ?? "default";  // always returns a string
}
```

The terminal `?? "default"` in `resolveListedDefaultAccountId` guarantees a non-empty string. The `?? "default"` in `setup.resolveAccountId` is unreachable.

**Impact:** Cosmetic + readability. Anyone reading the code wonders what edge case requires that fallback — there is none. Either remove it, or replace with a clarifying comment if you want defensive code.

```ts
// suggested
resolveAccountId: (params) => resolveDefaultCoveAccountId(params.cfg),
```

Severity: minor (held).

---

### 🟠 #3 — Narrow the unconditional catch in `resolver.resolveTargets`

**Status:** ❌ **Not addressed.**

```ts
try {
  account = resolveAccount(cfg, accountId);
} catch {
  // Soft-fail if account config is missing
  account = undefined;
}
```

Bare `catch {}` swallows every error — `resolveAccount` throws on missing token, missing agentId, *or* any future programming error inside the SDK. There's no debug log, no metric, no telemetry hook.

Severity: **minor → minor (held)**, but feeds into Issue #6 below where it actively causes wrong user-facing output.

Suggested fix:

```ts
} catch (err) {
  // resolveAccount throws when the account config is missing required
  // credentials. Resolution is best-effort here so we soft-fail; the
  // missing-credential branch is reported by resolveTargetsWithOptionalToken.
  if (process.env.DEBUG) console.warn("cove resolver: resolveAccount failed", err);
  account = undefined;
}
```

---

### 🟠 #4 — `account!.guildId!` non-null assertions are fragile

**Status:** ❌ **Not addressed.**

Still seven `account!.…` and one `account!.guildId!` in the `kind === "group"` branch. Reasoning today: `resolveWithToken` is only called when `token` is truthy; `token = account?.token`, so when `token` is set, `account` must be set. So the assertions are *currently* sound.

But this is exactly the fragility called out in Round 1 — the invariant lives implicitly in `resolveTargetsWithOptionalToken`'s implementation, not in this file. A tiny refactor on the SDK side could silently turn one of these into a runtime crash.

Suggested fix: assign a local `const acc = account!` once after re-entry, and prefer an explicit guard:

```ts
resolveWithToken: async ({ token, inputs }) => {
  if (!account) {
    return inputs.map((input) => ({ input, resolved: false, note: "missing account config" }));
  }
  const { guildId, baseUrl } = account;
  if (!guildId) { ... }
  ...
}
```

Severity: minor (held).

---

### 🟠 #5 — Error messages lost actionability

**Status:** ⚠️ **Partially addressed.**

New errors:
```
cove: account missing token (accountId=default)
cove: account missing agentId (accountId=default)
```

Better than before — at least the offending field is named and the accountId is identified. Still missing **what to set / where**. Compare with the original:

```
cove: bot token is required (set channels.cove.token or COVE_BOT_TOKEN env)
```

After this PR, the canonical config path is `channels.cove.accounts.<accountId>.token`. That hint is exactly what the user needs and would cost <40 chars.

Suggested:
```ts
throw new Error(
  `cove: account "${accountId ?? "default"}" missing token ` +
  `(set channels.cove.accounts.${accountId ?? "<accountId>"}.token)`
);
```

Severity: minor (held).

---

### 🔴 #6 — Misleading "missing token" message when other fields missing

**Status:** ❌ **Not addressed — escalating to MAJOR.**

This is the issue that bites users. Trace:

1. User configures `accounts.kagura: { token: "...", agentName: "Kagura" }` (forgot `agentId`).
2. `resolveTargets` calls `resolveAccount(cfg, "kagura")` → throws `"cove: account missing agentId"`.
3. Bare `catch {}` swallows it; `account = undefined`.
4. `resolveTargetsWithOptionalToken` is called with `token: undefined`.
5. User sees: `note: "missing Cove bot token"`.

User now spends 30 minutes verifying the token they correctly configured.

This is a **real correctness regression vs. Round 1**: in the previous code, `readAccountConfig` only returned a token-less object when token was actually missing, so the message wasn't misleading. The new soft-fail + token-only signal lies to the user when the failure was actually agentId, baseUrl coercion, or a future-added required field.

**Escalating to major** because (a) it's user-facing, (b) it's silent, and (c) no test will catch it as long as Issue #7 is unfixed.

Suggested fix: forward the underlying error message instead of swallowing.

```ts
let account: CoveAccount | undefined;
let resolveError: string | undefined;
try {
  account = resolveAccount(cfg, accountId);
} catch (err) {
  resolveError = err instanceof Error ? err.message : String(err);
}

return resolveTargetsWithOptionalToken({
  token: account?.token,
  inputs,
  missingTokenNote: resolveError ?? "missing Cove bot token",
  ...
});
```

---

### 🔴 #7 — Add multi-account tests

**Status:** ❌ **Not addressed — escalating to MAJOR.**

`packages/plugin/src/resolver.test.ts` adds nothing — the only meaningful change is `agentId: "test-agent"` to the existing single-account fixture and removal of an env-var save/restore block. Net new multi-account coverage: **zero**.

This is a feature PR titled *"multi-account support"*. There is no test that:

- Configures two accounts under `channels.cove.accounts`
- Resolves account A vs. account B and verifies different `token` / `agentId` / `guildId`
- Exercises `defaultAccount` selection
- Verifies `outbound.sendText` picks the bot identity matching `ctx.accountId`
- Verifies `setup.resolveAccountId` picks the configured `defaultAccount` over the alphabetical fallback in `resolveListedDefaultAccountId`

Round 1 listed this as non-blocking *because* it was paired with a critical schema bug; with the schema fixed, the absence of any behavioral coverage of the headline feature becomes the dominant risk.

**Escalating to major.** Minimum bar before merge: at least one test that constructs a two-account config and confirms `resolveAccount(cfg, "kagura")` and `resolveAccount(cfg, "ruantang")` produce distinct `CoveAccount` results, plus a test confirming `defaultAccount` selection works.

---

### 🟠 #8 — Test fixture still uses root-level config shape

**Status:** ❌ **Not addressed.**

`makeCfg` still produces:

```ts
{ channels: { cove: { token, baseUrl, guildId, agentId } } }
```

i.e., the *root-level* shape that the PR description claims is **removed** under "Breaking Change":

> Root-level `channels.cove.token` single-account config (removed)

Reading the SDK reveals the truth: `resolveMergedAccountConfig` calls `mergeAccountConfig` which uses `channelConfig` as the base layer before overlaying account-specific config. With **no** `accounts` map at all, the channel-level config *itself* becomes the merged result. So the root-level form is in fact still functional as an implicit "default account."

Two consequences:

1. **PR description is incorrect.** The breaking change is overstated. If you actually wanted to remove root-level support, you'd need to enforce `accounts` presence in either schema or `resolveAccount`. Recommend updating PR description to accurately describe behavior.

2. **Test still validates only the legacy path.** This compounds Issue #7 — the test suite never exercises the new code path it was written to support.

Severity: minor (held), but only because Issue #7 is the dominant offender.

---

## New Findings (not in Round 1)

### 🟡 NEW-1 — Per-account schema lacks `additionalProperties: false`

Already covered under Issue #1 above. Inner schema is permissive while outer is strict. Suggest tightening for consistency or documenting the choice.

### 🟡 NEW-2 — `resolveAccount` no longer respects `COVE_*` env vars

Pre-PR, `resolveAccount` honored `COVE_BOT_TOKEN`, `COVE_AGENT_ID`, `COVE_AGENT_NAME`, `COVE_BASE_URL`. Post-PR, all env-var fallbacks are gone. PR description correctly calls this out as a breaking change.

This is a deliberate design choice and matches the Discord plugin pattern. **Not flagging as a problem**, but noting that anyone using these env vars in a CI or container deploy will see a hard regression. Worth a release note / migration line in `CHANGELOG.md` (didn't see one in the diff). If there's a `MIGRATION.md` in the repo, this PR should add an entry.

### 🟢 NEW-3 — `outbound.sendText` correctly uses `ctx.accountId`

The change from `resolveAccount(cfg)` to `resolveAccount(ctx.cfg, ctx.accountId)` is the right fix and is the part of this PR that genuinely makes multi-account *work*. This is the load-bearing line. Reading the diff carefully, this is correct and well-placed.

---

## Summary Score

| Issue | R1 Severity | R2 Status | R2 Severity |
|---|---|---|---|
| #1 Schema rejects `accounts` | 🔴 Critical | ✅ Fixed | — |
| #2 Dead `?? "default"` | 🟠 Minor | ❌ Not addressed | 🟠 Minor (held) |
| #3 Bare `catch` | 🟢 Suggestion | ❌ Not addressed | 🟠 Minor |
| #4 `account!` assertions | 🟢 Suggestion | ❌ Not addressed | 🟠 Minor |
| #5 Error actionability | 🟢 Suggestion | ⚠️ Partial | 🟠 Minor |
| #6 Misleading "missing token" | 🟢 Suggestion | ❌ Not addressed | 🔴 **Major** |
| #7 No multi-account tests | 🟢 Suggestion | ❌ Not addressed | 🔴 **Major** |
| #8 Root-level fixture | 🟢 Suggestion | ❌ Not addressed | 🟠 Minor |
| NEW-1 Inner schema permissive | — | New | 🟡 Minor |
| NEW-2 Env-var removal | — | New | 🟢 Note |
| NEW-3 `ctx.accountId` in outbound | — | ✅ Correct | — |

**Verdict:** ⚠️ **Needs Changes**

**Required before merge (in my view):**
1. Add at least one true multi-account test (Issue #7).
2. Stop the resolver from reporting "missing token" when the actual error was something else (Issue #6).

**Strongly recommended:**
3. Drop the dead `?? "default"` (Issue #2).
4. Improve error messages with config path hint (Issue #5).
5. Add `additionalProperties: false` to per-account schema, or document choice (NEW-1).
6. Update PR description re: root-level config still being functional (Issue #8).

The schema fix is solid. The multi-account wiring (`ctx.accountId` in `outbound.sendText`, SDK-driven account list / default resolution) is correct. What's missing is the safety net — tests that prove it works, and an error path that doesn't lie to the operator.

— 🌠 Nova
