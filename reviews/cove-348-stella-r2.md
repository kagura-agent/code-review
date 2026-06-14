# Stella Round 2 Re-Review — PR #348

PR: `kagura-agent/cove#348` — `feat: custom display name (global_name) support (closes #186)`

## 1. R1 Issue Status

### Consensus Critical

- ⚠️ **Partially Fixed — C1: Empty string / whitespace-only `global_name` not normalized server-side**
  - Empty string and short whitespace-only strings are now normalized to `null` in `packages/server/src/routes/agents.ts:93-104`, with tests in `display-name.test.ts:89-117`.
  - **Remaining R1 edge, escalated:** normalization happens *after* `validateString(... maxLength: 80)` at `agents.ts:87-88`. A whitespace-only value longer than 80 chars is still rejected instead of normalized to `null`. Since the R1 requirement was whitespace-only normalization, normalize/trim first, then apply length validation to the non-empty value.
  - Also, non-empty names are not trimmed before persistence, so direct API clients can store leading/trailing spaces even though the settings UI trims before submit.

- ⚠️ **Partially Fixed — C2: Missing control char / zero-width / RTL validation on `global_name`**
  - PATCH validation now rejects controls/zero-width/bidi formatting characters via `validateDisplayName()` in `validation.ts:29-38`, and tests cover NUL, zero-width space, and RTL override (`display-name.test.ts:119-143`).
  - **Remaining R1 validation gap:** OAuth-derived `given_name` is stored into `pending_registrations.global_name` without going through the same normalization/length/invalid-character validation (`routes/auth.ts:91-95`) and later copied into `users.global_name` (`routes/register.ts:49-50`). This is still an external input path into `global_name`.

- ⚠️ **Partially Fixed — C3: Missing tests for PATCH `/users/@me`, `resolveUser` fix, OAuth fallback**
  - PATCH coverage was added for valid update, max length, clear/null, empty/whitespace normalization, and invalid characters.
  - A message-author round-trip test was added, which helps cover persisted `global_name` in message output.
  - Still missing direct coverage for `resolveUser()` / `/api/auth/me` preserving `global_name`, websocket auth preserving `global_name`, and OAuth fallback behavior (`given_name` into pending/new user, existing user not overwriting a cleared custom name).
  - Test note: I attempted `pnpm -F @cove/server test -- --runInBand packages/server/src/__tests__/display-name.test.ts` in an isolated worktree, but the worktree had empty/missing package dependencies (`Cannot find package 'hono'`, `@hono/node-server`), so I could not execute the tests there.

- ✅ **Fixed — C4: Settings hint misleading**
  - The hint now says “Leave empty to use your account name.” in `SettingsPanel.tsx`, which no longer claims it will use the Google account name.

### Stella R1 Unique Finding

- ✅ **Fixed — `toUser()` in `members.ts` hardcoded `global_name: null`**
  - `members.ts:24-33` now maps `row.global_name ?? null`, so MemberList/MentionAutocomplete can receive display names from REST member lists.

### Other Reviewer Findings

- ✅ **Fixed — `repos.users.update(id!, body)` passed the whole request body**
  - The route now constructs an explicit `patch` object with only allowed/sent fields before calling `repos.users.update()` (`agents.ts:99-106`).

- ❌ **Not Fixed — `findByToken` redundant cast**
  - The cast remains in `repos/users.ts:99-100`. This is low-risk/readability-only, but it was not addressed.

- ❌ **Not Fixed — nick chain incomplete in `MessageItem`**
  - `MessageItem` still renders only `message.author.global_name || message.author.username` (`MessageItem.tsx:274-279`). A TODO was added, but guild member nick is still not part of the message display chain. Per R2 protocol, this R1 item remains unaddressed.

- ✅ **Fixed — OAuth `COALESCE(global_name, ?)` overwrote user-cleared names**
  - Existing-user OAuth login no longer writes `global_name` (`routes/auth.ts:80-86`), so a user-cleared custom display name stays cleared.

- ✅ **Fixed — `validateString` may reject `null`**
  - `validateString()` accepts `undefined`/`null` for optional fields, and `global_name: null` now clears successfully.

## 2. New Issues

### 🔴 Critical — GitHub Actions notification step is shell-injection vulnerable via PR title

The new CI failure notification interpolates the PR title directly into a shell `run:` script inside a double-quoted argument:

- `.github/workflows/ci.yml:46-51`

A malicious or accidental PR title containing shell metacharacters/command substitution (for example `$()`, backticks, or quotes) can be evaluated by the shell after GitHub expression interpolation. Because this step also references a secret webhook URL, this is a security-sensitive workflow change.

**Recommendation:** do not interpolate untrusted PR metadata directly into shell. Pass the title through `env:` and JSON-escape with `jq -n --arg`, or use `actions/github-script`/a small Node script to build the JSON payload safely. Also guard missing `COVE_DEV_WEBHOOK_URL` so the failure notifier does not add noisy secondary failures.

### 🟠 Major — Mention insertion now uses non-unique display names as the replacement key

`MentionAutocomplete` now passes `global_name || username` to `onSelect()` (`MentionAutocomplete.tsx:91,120`), and `MessageInput` stores `mentionMapRef` keyed by that display string (`MessageInput.tsx:159-166`). Display names are not unique and can contain spaces/similar-looking characters. If two users share the same display name, the map key collides and all matching `@Display Name` occurrences can be converted to the last selected user ID.

**Recommendation:** keep the stable mention token/key as username or user ID, or track selected mention ranges/IDs instead of using the visible display name as the map key. The UI can still show display names in the dropdown.

### 🟡 Minor — Optimistic self-message ignores current `global_name`

Pending messages created in `MessageInput` still set `author.global_name: null`, so the user’s own just-sent message may briefly render with username until reconciliation returns the server message. This is cosmetic, but easy to fix by using `user.global_name` from `useUserStore`.

## 3. Summary + Verdict

❌ **Major Issues**

Round 2 addressed several important R1 findings, especially member serialization, explicit patching, PATCH validation/tests, and avoiding OAuth overwrite of cleared names. However, there are still partial R1 gaps around full whitespace normalization, OAuth validation/test coverage, and nick rendering. More importantly, the newly added CI webhook notification introduces a critical shell-injection risk from untrusted PR titles. I would block this until the workflow injection issue and the remaining `global_name` normalization/validation gaps are fixed.
