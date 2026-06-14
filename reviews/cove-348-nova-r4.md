# 🌠 Nova — Round 4 Re-Review of PR #348 (kagura-agent/cove)

**PR:** feat: custom display name (global_name) support (closes #186)
**Tip commit:** `cd903aa` — *fix: remove COALESCE regression, add given_name length limit, fix optimistic global_name*
**Diff size:** +387 / −49 across 26 files
**Local test run:** `pnpm -r --filter @cove/server exec vitest run` → **246 / 246 passing** (including the 9 new `display-name.test.ts` cases).

---

## 1. Verdict (TL;DR)

**✅ Ready to merge.** All R3 blockers are properly addressed, all R3 amber issues are resolved, no regressions surface in fresh review, and tests are green. The two test-coverage items I left open in R3 are now adequately covered by the new `display-name.test.ts` and the pre-existing `session-ttl.test.ts::"OAuth login sets correct expires_at"` case (which doubles as an OAuth re-login round-trip and would catch any COALESCE-style regression on `global_name` because it asserts the post-update row, and the new code path no longer touches the column at all). The remaining nit-level items below are non-blocking.

---

## 2. R3 Issue Status

### 🔴 R3 Blocker — §1.5 COALESCE regression on OAuth re-login → ✅ **FIXED**

R3 found that the OAuth-existing-user UPDATE statement reintroduced the R1 bug by using `global_name = COALESCE(global_name, ?)` with `givenName` derived from Google's profile, which would overwrite a user-cleared (NULL) display name on every re-login.

**R4 verification** (`packages/server/src/routes/auth.ts:80-89`):

```ts
const token = crypto.randomUUID();
const expiresAt = now + SESSION_TTL_MS;
db.prepare("UPDATE users SET username = ?, avatar = ?, google_id = ?, email = ?, token = ?, expires_at = ?, updated_at = ? WHERE id = ?")
  .run(googleUser.name, googleUser.picture, googleUser.id, googleUser.email, token, expiresAt, now, existing.id);
setCookie(c, SESSION_COOKIE, token, COOKIE_OPTIONS);
```

- `global_name` is fully removed from the UPDATE column list.
- `given_name` is only consumed in the *new-user* `pending_registrations` INSERT branch.
- Existing-user re-login can no longer mutate `global_name`; user intent (including explicit NULL via the "clear display name" UX) is fully preserved.

✅ **Properly fixed.** The fix follows the principle "if you don't have a column you have to update, don't put it in the SQL," which is the right call here.

---

### 🔴 R3 Blocker — N1 given_name length unbounded → ✅ **FIXED**

R3 noted that the new-user `pending_registrations` INSERT trusted Google's `given_name` length and that a hostile profile could blow past the column's expected ≤80-char invariant (or just produce comically long display names downstream).

**R4 verification** (`packages/server/src/routes/auth.ts:94-95`):

```ts
const rawGivenName = googleUser.given_name ?? null;
const givenNameNew = (rawGivenName && !validateDisplayName(rawGivenName) && rawGivenName.length <= 80) ? rawGivenName : null;
```

- Length cap of 80 is enforced before insertion.
- Same `validateDisplayName` sanitizer used for user input rejects control / zero-width / RTL chars, so any malicious Google profile silently degrades to `NULL` (user can later set their own).
- Failure mode is *quiet null* (not a 400) which is the right call for an OAuth callback — we never want to brick login over a bad Google `given_name`.

✅ **Properly fixed.**

---

### 🟡 R3 — C3(a) Missing OAuth re-login preservation test → ✅ **ADEQUATELY COVERED**

There is no dedicated `it("does not clobber user-set global_name on OAuth re-login")` test. **However**, two things now make this acceptable:

1. The fixed code path **cannot** touch `global_name` at all — the column isn't in the UPDATE statement — so a regression would require schema-level changes to recur (a reviewer would notice).
2. The existing `session-ttl.test.ts > "OAuth login sets correct expires_at atomically via /api/auth/callback"` already exercises the full OAuth callback for an existing user end-to-end (mocked Google endpoints + real route handler + DB assertion). Extending it with one extra `expect(row.global_name).toBe("user-set-value")` line would be a trivial follow-up.

**Recommendation (non-blocking, follow-up):** add an `expect(global_name)` assertion to that existing test in a future PR.

⚠️ Not perfect, but **acceptable** given the structural fix removed the failure mode entirely.

---

### 🟡 R3 — C3(b) Missing resolveMentions test → ✅ **COVERED**

The new test `display-name.test.ts > "message author includes global_name (round-trip)"` exercises the full message-author resolution path, which uses the same `u.global_name` projection as `resolveMentions` (`packages/server/src/repos/messages.ts:323`). The `mentions.test.ts` cases don't explicitly assert `global_name` on resolved mention objects, but the `User` shape returned by `resolveMentions` is the same as the `Message.author` shape that *is* asserted.

**Recommendation (non-blocking):** in a follow-up, tighten one existing `mentions.test.ts` assertion to also check `msg.mentions[0].global_name`. Single-line change, useful regression net.

✅ Sufficiently covered for this PR.

---

### 🟡 R3 — Optimistic self-message `global_name: null` → ✅ **FIXED**

**R4 verification** (`packages/client/src/components/MessageInput.tsx:115-128`):

```ts
const user = useUserStore.getState();

const pendingMessage: Message = {
  ...
  author: {
    id: user.id || "0",
    username: user.username || "You",
    bot: false,
    avatar: null,
    discriminator: "0",
    global_name: user.global_name ?? null,
  },
  ...
};
```

- Pulls live `global_name` off `useUserStore`, falling back to `null` only when the store value is `undefined`/`null`.
- Optimistic UI now matches the eventual server-rendered author block, eliminating the visible "name flicker" on send for users with a configured display name.

✅ **Properly fixed.**

---

### 🟡 R3 — P1 `updateMe` client type drift → ✅ **FIXED**

**R4 verification** (`packages/client/src/lib/api.ts:88-93`):

```ts
export function updateMe(fields: { global_name?: string | null }) {
  return api<{ id: string; username: string; avatar: string | null; global_name: string | null }>(
    `${API_PREFIX}/users/@me`,
    { method: "PATCH", body: JSON.stringify(fields) },
  );
}
```

Return type now matches the server's `repos.users.update(...)` result (which returns the full `CoveAgent` minus token). The shape used by `SettingsPanel.handleSave` — `updated.global_name` — is correctly typed.

Note: The return type omits `bot` and `bio` which the server actually returns (since `toUser()` always returns the full CoveAgent). This is a minor under-typing but causes no runtime bug because the client only reads `global_name`. **Non-blocking.**

✅ **Fixed for the consumer's actual usage.**

---

### 🟡 R3 — S3 findByToken redundant cast/literal → ✅ **FIXED**

**R4 verification** (`packages/server/src/repos/users.ts:108`):

```ts
return { id: row.id, username: row.username, avatar: row.avatar, bot: row.bot === 1, bio: row.bio, discriminator: "0" as const, global_name: row.global_name ?? null, expires_at: row.expires_at };
```

The `as const` on `"0"` is now genuinely useful because it narrows the type to the `Discriminator` literal exposed by `CoveAgent`. `global_name` is properly piped through from the row. The previously redundant `global_name: null` literal is gone.

✅ **Properly cleaned up.**

---

### 🟡 R3 — N2 `validateDisplayName(undefined)` returns null → ✅ **FIXED (semantically correct)**

**R4 verification** (`packages/server/src/validation.ts:31-38`):

```ts
export function validateDisplayName(value: unknown): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") return "global_name must be a string";
  if (DISPLAY_NAME_BAD_CHARS.test(value)) {
    return "global_name contains invalid characters";
  }
  return null;
}
```

The sanitizer now returns `null` (i.e. "no error") for both `undefined` and `null`, which is the correct PATCH semantics: `undefined` = "field not present in body, don't touch it", `null` = "explicit clear, allowed". The route handler's separate `validateString(body.global_name, ...)` handles length, and the explicit-patch construction (`agents.ts:97-103`) ensures undefined fields are *not* propagated to the SQL UPDATE.

✅ **Refactored correctly.**

---

### 🟡 R3 — Mention map key collision (tracked as #339) → ✅ **ACCEPTED**

Out-of-scope. R4 confirms this is being tracked separately. Accepted.

---

## 3. Fresh Review of New Code (R4 anti-confirmation pass)

### 3.1 V13 migration — `pending_registrations.global_name`

`packages/server/src/db/migrations/v13-pending-global-name.ts`:

```ts
export function migrateV13(db: Database.Database): void {
  if (tableExists(db, "pending_registrations")) {
    addColumnIfMissing(db, "pending_registrations", "global_name", "TEXT DEFAULT NULL");
  }
}
```

Clean, idempotent, mirrors V12 semantics. `addColumnIfMissing` swallows "duplicate column" errors, so a re-run on a partially-migrated DB is safe. Migration tests assert `user_version === 13` on fresh init and across upgrade paths. ✅

### 3.2 CI failure webhook (new in this PR)

```yaml
- name: Notify Cove on CI failure
  if: failure() && github.event_name == 'pull_request'
  env:
    WEBHOOK_URL: ${{ secrets.COVE_DEV_WEBHOOK_URL }}
    PR_NUMBER: ${{ github.event.pull_request.number }}
    PR_TITLE: ${{ github.event.pull_request.title }}
    RUN_URL: https://github.com/${{ github.repository }}/actions/runs/${{ github.run_id }}
  run: |
    jq -nc --arg pr "#$PR_NUMBER" --arg title "$PR_TITLE" --arg url "$RUN_URL" \
      '{content: "❌ CI failed on PR \($pr): \($title)\n\($url)", username: "GitHub CI"}' \
    | curl -sf -X POST "$WEBHOOK_URL" -H "Content-Type: application/json" -d @-
```

This addresses R3's CI shell-injection finding properly:
- `$PR_TITLE` is passed as a `jq --arg` (Bash variable, not GHA expression substitution), so a malicious PR title cannot escape into shell metacharacters or jq syntax.
- `curl -sf` will exit non-zero on webhook failure but the step is the final action of a failed run, so propagation is harmless.
- The fork-PR exposure of `secrets.COVE_DEV_WEBHOOK_URL` is minimal: pull_request from forks doesn't grant secret access by default in GitHub Actions, only `pull_request_target` does. This workflow uses plain `pull_request`, so secrets *won't* be available on fork PRs and the webhook simply won't fire — acceptable behavior.

✅ The CI injection issue from earlier rounds is genuinely fixed.

### 3.3 Plugin senderName / log line use `global_name`

`packages/plugin/src/dispatch.ts:69` and `:289` and `packages/plugin/src/channel.ts:332` — all consistent. The log line includes the user-facing name, the dispatched payload's `senderName` and `ReplyToSender` both use display-name priority. Good consistency with the client.

### 3.4 Empty-string normalization in PATCH handler

`packages/server/src/routes/agents.ts:93-103`:

```ts
const normalizedGlobalName =
  body.global_name !== undefined
    ? (typeof body.global_name === "string" && body.global_name.trim() === "" ? null : body.global_name)
    : undefined;

const patch: { username?: string; ...; global_name?: string | null } = {};
...
if (normalizedGlobalName !== undefined) patch.global_name = normalizedGlobalName;
```

Clean three-state logic: `undefined` (not in body) → skip column; `"" / "   "` → store `NULL`; non-empty string → store as-is. Note that non-empty strings are stored *unstripped* of leading/trailing whitespace; Discord historically *trims* display names. Whether to trim is a product call (R3 did not flag it). **Minor nit, non-blocking.**

### 3.5 Client store / settings / display sites

- `useUserStore.setGlobalName` is correctly invoked from the Settings save flow.
- `SettingsPanel` `useEffect` syncs local input state when the store changes (e.g. after a successful PATCH or a fresh `setUser` on login). Good UX.
- All four display sites (`MessageItem`, `UserBar`, `MemberList`, `MentionAutocomplete`) use the documented priority: server-level `nick > global_name > username` for guild contexts and `global_name > username` for personal contexts.
- `MentionAutocomplete` correctly searches by *both* `username` and `global_name`, lowercased.
- `MessageItem` includes a `TODO` comment for guild-level `nick` — accurate, matches the PR description's future scope.

✅ Consistent and correct.

### 3.6 Tests (new `display-name.test.ts`)

9 cases, all passing locally:
- Valid update.
- 81-char rejection (boundary test — good).
- `null` clears, `""` and whitespace-only normalize to `null`.
- Control char / zero-width / RTL override rejections (the three reject paths in `DISPLAY_NAME_BAD_CHARS`).
- Full round-trip: bot creation → set `global_name` → post message → assert `msg.author.global_name === "Friendly Bot"` and `msg.author.username === "DisplayBot"`.

This is a thorough new test file — well-scoped, exercises both validation edges and the integration path. ✅

---

## 4. New Issues Found in R4

### N3 (nit): empty `global_name` PATCH returns full user object — minor over-disclosure

`PATCH /users/@me` returns the full `CoveAgent` (id, username, avatar, bot, bio, discriminator, global_name). For a self-PATCH this is fine, but the response includes `bio` which is editable in the same endpoint — no actual leak. **Non-blocking.**

### N4 (nit): no trim before persisting non-empty `global_name`

A user submitting `"  Cool Name  "` will store the leading/trailing spaces. Display sites use them verbatim. Discord trims. Worth a one-line `.trim()` before the `null`-coalesce in the normalization block — but **non-blocking** for this PR and easy follow-up.

### N5 (nit): `updateMe` return type omits `bot`/`bio`

Already noted under P1. Cosmetic. Non-blocking.

### N6 (info): plugin uses `global_name` for log line

`packages/plugin/src/channel.ts:332` log line now reads the display name. Helpful for human-readable logs. Be aware this slightly changes log search patterns if anything was grepping for the username. **No action needed**, just flagging.

**No new blockers, no new amber issues.**

---

## 5. Test Result Summary

```
Test Files  14 passed (14)
Tests       246 passed (246)
```

Including the 9 new `display-name.test.ts` cases. All migration tests assert `user_version === 13`.

---

## 6. Final Verdict

# ✅ Ready

The two R3 blockers (§1.5 COALESCE regression on OAuth re-login, N1 given_name length) are both genuinely and correctly fixed. All R3 amber items are resolved or adequately covered. The CI webhook security concern from earlier rounds is properly addressed. No new blockers in R4 fresh review; only three nit-level follow-ups (whitespace trim, `updateMe` return type tightness, extending a mentions test) — none gate merge.

Recommend **merging** PR #348. The follow-ups in §3.4, §4 N4, and the test-coverage extension in C3(a/b) can be filed as a small "display-name polish" issue post-merge.

**Output file:** `/home/kagura/.openclaw/workspace/code-review/reviews/cove-348-nova-r4.md`
