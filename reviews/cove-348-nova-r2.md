# 🌠 Nova — Round 2 Re-Review: PR #348 (kagura-agent/cove)

**PR:** feat: custom display name (global_name) support (closes #186, #349)
**Stats:** +378 / −48, 25 files
**Head SHA:** verified against current PR head

---

## 1. R1 Issue Status

### Consensus / Cross-Reviewer

| ID | Issue | Status | Notes |
|---|---|---|---|
| **C1** | Empty / whitespace-only `global_name` not normalized → empty string stored | ✅ **Fixed** | `routes/agents.ts` now does `body.global_name.trim() === "" ? null : body.global_name` before persisting. Tests cover both `""` and `"   "` → `null`. |
| **C2** | Missing control-char / zero-width / RTL-override validation | ✅ **Fixed** | New `validateDisplayName` in `validation.ts` rejects `\u0000-\u001F`, `\u007F-\u009F`, `\u200B-\u200F`, `\u2028-\u202F`, `\u2060-\u2064`, `\uFEFF`. Tests cover `\x00`, `\u200B`, `\u202E`. |
| **C3** | Missing tests for PATCH /users/@me, resolveUser fix, OAuth fallback | ⚠️ **Partially Fixed** | New `display-name.test.ts` covers PATCH (set/clear/empty/whitespace/maxlen/control/ZWS/RTL) and a message round-trip exercising the messages.ts `global_name` join (proxy for resolveUser/resolve path). **Still missing:** dedicated test for `resolveMentions` populating `global_name`, and a test that OAuth re-login does **not** overwrite a user-customized `global_name`. |
| **C4** | Misleading Settings hint "Leave empty to use your Google account name" | ✅ **Fixed** | Now reads `"Leave empty to use your account name."` |

### My (Nova) R1 Findings

| ID | Issue | Status | Notes |
|---|---|---|---|
| **C1 (me)** | PATCH accepts `""` and stores empty string | ✅ **Fixed** | See C1. |
| **C2 (me)** | `validateString` does not enforce charset | ✅ **Fixed** | Dedicated `validateDisplayName` added and wired into PATCH path. |
| **C3 (me)** | `repos.users.update(id!, body)` passes whole request body (fragile) | ✅ **Fixed** | Now constructs explicit `patch` object with only known fields (`username`, `avatar`, `bio`, `global_name`). |
| **P1** | Settings hint misleading for non-OAuth users | ✅ **Fixed** | See C4. |
| **P2** | OAuth re-link seeds `given_name` with no signup choice | ⚠️ **Partially Fixed** | New code stores `googleUser.given_name ?? null` into `pending_registrations.global_name` and carries it through to `users.global_name` on register. User can immediately edit/clear in Settings, but there is **no signup-time choice prompt**. Acceptable for v1; document or surface in onboarding later. |
| **P3** | MentionAutocomplete insertion vs server-side mention divergence | ⚠️ **Partially Fixed** | Autocomplete now inserts `@${global_name||username}` and the client mention map (`MessageInput.tsx`) escapes regex specials and uses a `(?!\w)` lookahead so the textarea→`<@id>` conversion still works when the picked display name contains whitespace (e.g. `"Cool Admin"`). However: **manually-typed `@name`** that doesn't go through the picker is still never converted to wire format — it stays as plain text on the wire. This is pre-existing behavior, but the rename amplifies it because display names are far more likely to contain spaces and special chars than usernames were. Not a blocker. |
| **P4** | nick chain incomplete in `MessageItem` | ⚠️ **Partially Fixed** | Now `message.author.global_name \|\| message.author.username` (skips `nick`). A `// TODO: add nick (guild member nickname) when server-level nick support lands` comment was added. `MessageList`/mentions Map uses the same fallback. Consistent within current scope, but the inconsistency with `MemberList` (which already uses `member.nick || user.global_name || user.username`) means the same author renders as "nick" in the sidebar and as "global_name" in messages until #?? lands. Worth a follow-up issue. |
| **S3** | `findByToken` redundant cast / hand-built return | ❌ **Not Fixed** | Still hand-builds the `{ id, username, avatar, bot, bio, discriminator, global_name, expires_at }` literal instead of `{ ...toUser(row), expires_at: row.expires_at }`. Trivial nit; no behavior risk. Per the escalation rule this stays at S3 — minor style. |
| **S4** | Plugin log line leaks display name with potential control chars | ✅ **Fixed (mitigated)** | Server-side `validateDisplayName` rejects all control/format chars before they can reach the log. The log line itself is unchanged but the input is now sanitized at the boundary, which is the right fix. |

### Other Reviewers' R1 Findings

| Source | Issue | Status | Notes |
|---|---|---|---|
| Stella | `toUser()` in `members.ts` hardcoded `global_name: null` | ✅ **Fixed** | Now `row.global_name ?? null`, and `UserRow` extended with the column. |
| Vega | OAuth `COALESCE(global_name, ?)` overwrites user-cleared names | ✅ **Fixed (different approach)** | Existing-user OAuth path in `routes/auth.ts` does **not** touch `global_name` at all on re-login (`UPDATE users SET username=?, avatar=?, google_id=?, email=?, token=?, expires_at=?, updated_at=?`). Cleared names stay cleared. Good. |
| Vega | `validateString` may reject `null` for `global_name` | ✅ **Fixed** | `validateString` early-returns `null` on `undefined`/`null` unless `required`. `global_name` is passed without `required:true`, so explicit `null` is accepted, exactly matching the documented "null to clear" contract. PATCH tests confirm. |

---

## 2. New Issues (fresh review of updated diff)

### ⚠️ M1 — `validateDisplayName` runs *before* normalization
**File:** `packages/server/src/routes/agents.ts`

`validateString(body.global_name, ...)` and `validateDisplayName(body.global_name)` both run on the **raw** value, then trim/empty→null normalization happens afterward. This is fine functionally (whitespace passes the bad-char regex), but it means a 81-space string `" ".repeat(81)` is rejected as `> 80 chars` even though it would normalize to `null`. Edge case, not a real bug. **No change required**, just noting.

### ⚠️ M2 — `given_name` from Google is persisted without validation
**File:** `packages/server/src/routes/auth.ts`, ~L92

```ts
... googleUser.picture, googleUser.given_name ?? null, now);
```

`given_name` is stored into `pending_registrations.global_name` and later copied into `users.global_name` on `/api/auth/register` **with no `validateDisplayName` call**. Google rarely returns control chars, but for consistency the PATCH-path validation should apply here too. If a malicious or accidental upstream value contains, say, `\u202E`, it bypasses every check in the rest of the codebase.

**Suggestion:** sanitize at the boundary:
```ts
const safeGivenName =
  googleUser.given_name && !DISPLAY_NAME_BAD_CHARS.test(googleUser.given_name)
    ? googleUser.given_name.slice(0, 80) || null
    : null;
```

### ⚠️ M3 — CI webhook payload interpolates PR title into shell-quoted JSON
**File:** `.github/workflows/ci.yml`

```yaml
-d "{\"content\": \"❌ CI failed on PR #${{ github.event.pull_request.number }}: ${{ github.event.pull_request.title }}\\n..."
```

A PR title containing `"`, `\`, `$`, backticks, or newlines will produce malformed JSON, fail the webhook, or — worst case — execute as shell. GitHub Actions does interpolate `${{ }}` directly into the script text before shell parsing, so this is a real shell-injection vector reachable by any contributor who can open a PR with a crafted title.

**Suggestion:** pass the title via an `env:` block and use `jq -nc` to build the JSON, e.g.
```yaml
env:
  PR_NUM:   ${{ github.event.pull_request.number }}
  PR_TITLE: ${{ github.event.pull_request.title }}
  RUN_URL:  https://github.com/${{ github.repository }}/actions/runs/${{ github.run_id }}
run: |
  payload=$(jq -nc --arg c "❌ CI failed on PR #$PR_NUM: $PR_TITLE
$RUN_URL" '{content:$c, username:"GitHub CI"}')
  curl -sf -X POST "$COVE_DEV_WEBHOOK_URL" -H 'Content-Type: application/json' -d "$payload"
```
This is the highest-severity issue I see in R2 — it's unrelated to the display-name feature itself, but it ships in the same PR.

### 🟢 P1 (new) — `updateMe` client type drift
**File:** `packages/client/src/lib/api.ts`

```ts
return api<{ id; username; avatar; global_name }>(...);
```

The server actually returns full `CoveAgent` (includes `bot`, `bio`, `discriminator`). Harmless because the call site only reads `global_name`, but it's a type lie. Suggest typing as `CoveAgent` from `@cove/shared`.

### 🟢 P2 (new) — `validateString` length is UTF-16 code units
**File:** `packages/server/src/validation.ts`

`value.length > 80` counts code units. A ZWJ-joined emoji like `👨‍👩‍👧‍👦` (11 code units, 1 grapheme) can exhaust the budget. Not a regression — `username` has the same behavior — but documenting for completeness. Not blocking.

### 🟢 P3 (new) — Missing `discriminator` / `bio` in `/api/auth/me` response
**File:** `packages/server/src/routes/auth.ts`

`/api/auth/me` returns `{id, username, avatar, bot, global_name, expires_at}` — no `discriminator`, no `bio`. The client store doesn't need them, but `resolveUser` is now the canonical user-resolution path and its callers may want the full `CoveAgent`. Currently a deliberate slim payload; consider widening once the client uses `discriminator` for the new display chain.

---

## 3. Summary + Verdict

R2 substantially addresses the R1 critical findings:

- ✅ Server-side normalization of empty/whitespace `global_name` to `null` — implemented and tested
- ✅ Charset validation against control chars, zero-width, RTL overrides, BOM — implemented and tested
- ✅ Explicit `patch` object in `PATCH /users/@me` (no more whole-body passthrough) — implemented
- ✅ Settings UI hint corrected ("account name" instead of "Google account name")
- ✅ Stella's `toUser()` hardcoded null — fixed in `members.ts`, `users.ts`, `messages.ts`, `auth.ts`, `ws/index.ts`
- ✅ Vega's OAuth COALESCE concern — sidestepped by not updating `global_name` on re-login at all
- ⚠️ Tests now cover the PATCH endpoint thoroughly, but still lack explicit OAuth-relogin-preserves-custom-name and resolveMentions tests
- ⚠️ Nick chain still incomplete in MessageItem (acknowledged via TODO)
- ⚠️ Mention conversion still fragile for manually-typed `@name` (pre-existing)
- ❌ **New M3 (CI webhook shell-injection via PR title)** is the only material new concern

### Recommended actions before merge
1. **Must:** Patch the CI webhook (M3) — switch to env-var + `jq` payload construction. Cheap, eliminates a real injection vector.
2. **Should:** Add the OAuth-relogin regression test (C3 partial) and the `resolveMentions` test.
3. **Should:** Validate `googleUser.given_name` with `validateDisplayName` before storing it (M2).
4. **Nice to have:** Tighten `api.updateMe` return type; drop the redundant hand-built literal in `findByToken` (S3).

### Verdict: ⚠️ **Needs Changes**

The display-name feature itself is in good shape and would ship at "Ready" status. The blocker is **M3 (CI workflow shell-injection)** that landed in the same PR. Fix M3 (≤5 lines), apply the OAuth `given_name` sanitization, and this is a clean merge.

— 🌠 Nova
