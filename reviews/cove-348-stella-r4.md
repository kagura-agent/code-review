# PR #348 Round 4 Re-review — 🌟 Stella

Repo: `kagura-agent/cove`  
PR: #348 — `feat: custom display name (global_name) support (closes #186)`

## R3 Issue Status

| R3 Issue | Status | Verification |
|---|---:|---|
| 🔴 COALESCE regression in existing-user OAuth UPDATE | ✅ Fixed | `packages/server/src/routes/auth.ts` existing-user OAuth path now updates only `username`, `avatar`, `google_id`, `email`, `token`, `expires_at`, `updated_at`. No `global_name` / `COALESCE(global_name, ?)` remains in that UPDATE. User-cleared `global_name = NULL` is no longer re-filled on re-login by this code path. |
| 🔴 `given_name` length unbounded | ✅ Fixed | New-user OAuth seeding now uses `const givenNameNew = (rawGivenName && !validateDisplayName(rawGivenName) && rawGivenName.length <= 80) ? rawGivenName : null;`, so over-80 `given_name` is not stored. Existing-user OAuth no longer stores `given_name`. |
| 🟡 Optimistic self-message `global_name: null` | ✅ Fixed | `packages/client/src/components/MessageInput.tsx` now sets pending message author `global_name: user.global_name ?? null`. |
| 🟡 Mention map key collision | ❌ Not Fixed | The collision remains in `MessageInput.tsx`: `mentionMapRef` is still keyed by display text (`Map<string, string>` and `mentionMapRef.current.set(username, userId)`). If two users share the same display name, the last selected user overwrites the first. The claimed tracker `#339` exists only as a merged PR for mention autocomplete, not as an open tracking issue for this collision. Per escalation rule, this should not be treated as resolved/out-of-scope unless a real follow-up issue is opened. |
| 🟡 Missing OAuth re-login preservation test | ❌ Not Fixed | I found only the existing session TTL OAuth test, which verifies token/expiry atomicity. There is no regression test that sets `global_name`, re-logins via OAuth, and verifies it is preserved; nor one that clears `global_name` to `NULL`, re-logins, and verifies it remains `NULL`. Because this is the bug that regressed in R3, this remains important. |
| 🟡 Missing `resolveMentions` test | ⚠️ Partially Fixed / Not specifically fixed | The repo already has mention resolution tests, but they only assert id/username behavior. I do not see a new assertion that `resolveMentions` includes `global_name` in mention `User` objects. The new display-name test covers message author `global_name`, not mention resolution `global_name`. |
| 🟡 `findByToken` redundant cast | ❌ Not Fixed | `packages/server/src/repos/users.ts` still casts the selected row as `(UserRow & { expires_at: number | null }) | undefined` and still uses `discriminator: "0" as const`. This is a small readability/type-cleanup nit, but unchanged. |

## New Issues

### 🟡 Mention collision still causes wrong wire mentions with duplicate display names

This is the same R3 issue, but I re-verified it against the R4 code because the display-name changes make it more likely:

- `MentionAutocomplete` passes `member.user.global_name || member.user.username` as the text inserted into the composer.
- `MessageInput` stores selected mentions in `mentionMapRef` keyed by that visible display text.
- On submit, every `@${displayName}` occurrence is replaced with the single current user id for that display text.

So two users with the same `global_name` cannot be mentioned reliably; earlier selections can be silently rewritten to the later-selected user. Since display names are intentionally non-unique, this should be fixed by tracking selected mention spans/tokens by user id (or inserting an internal marker) rather than keying by display text.

No other new blocking correctness/security issues found in the R4 diff.

## Validation Performed

- `gh pr view 348 --repo kagura-agent/cove --json title,body,additions,deletions,changedFiles`
- `gh pr diff 348 --repo kagura-agent/cove`
- `gh issue view 339 --repo kagura-agent/cove --json number,title,state,url,body`
  - Result: #339 is a merged PR titled `feat: @mention with autocomplete and highlight (closes #332)`, not a tracking issue for the collision.
- `pnpm -F @cove/server exec vitest run src/__tests__/display-name.test.ts src/__tests__/session-ttl.test.ts --reporter=dot`
  - Result: 2 files passed, 18 tests passed.
- `pnpm -r build`
  - Result: passed for shared/server/client/plugin/claude-bridge. Vite emitted only the pre-existing large chunk warning.

## Summary + Verdict

The two R3 blockers are fixed: OAuth re-login no longer touches `global_name`, and OAuth `given_name` is capped at 80 characters before being seeded for new users. The optimistic self-message fix is also correct.

However, some R3 follow-ups remain unresolved, especially the missing OAuth re-login preservation regression test and the still-real duplicate-display-name mention collision. Because the collision is not actually tracked by #339, and because the OAuth regression already reappeared once without a targeted test, I would not call this fully ready yet.

**Verdict: ⚠️ Needs Changes**

Minimum before merge:
1. Add OAuth re-login regression tests for both preserved custom `global_name` and cleared `NULL` `global_name`.
2. Either fix the mention map collision now, or open a real follow-up issue and link it from this PR.
3. Add/extend a mention resolution test that asserts `mentions[].global_name` is populated.
