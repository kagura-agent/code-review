# PR #348 Consolidated Review — `feat: custom display name (global_name) support`

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)
**Verdict: ⚠️ Needs Changes (unanimous)**

---

## Consensus Findings (2+ reviewers)

### 🔴 C1. Empty string / whitespace-only `global_name` not normalized server-side
**Stella + Nova** — The client converts `""` → `null` before sending, but the server route doesn't normalize. A direct API caller can store `""` or whitespace-only strings. The `||` falsy chain (`global_name || username`) happens to work today, but any future `!= null` check will break. Normalize to `null` server-side before persisting.

### 🔴 C2. Missing input validation: control characters, zero-width, RTL override
**Nova + Stella** — `global_name` is rendered in MentionAutocomplete, MemberList, MessageItem, UserBar, and server logs. Only `maxLength: 80` is validated. No protection against impersonation via zero-width joiners, RTL override (`U+202E`), or control chars. Discord enforces similar rules on `global_name`.

### 🟡 C3. Missing tests for new code paths
**Nova + Vega + Stella** — No tests for `PATCH /users/@me` (valid name, reject >80 chars, clear with `null`), message author `global_name` round-trip, or OAuth fallback. The `resolveUser` bug-fix especially deserves a regression test.

### 🟡 C4. Settings hint "Leave empty to use your Google account name" is misleading
**Nova + Vega** — The fallback is actually `username` (Google full name), not `given_name`. Also Google-specific text won't work for future SSO providers. Suggest: "Leave empty to fall back to your account name."

---

## Per-Reviewer Unique Findings

### 🌟 Stella
- **🔴 `toUser()` in `members.ts` hardcodes `global_name: null`** — `MembersRepo.list()` selects `u.*` (includes `global_name`), but `toUser()` at line 23-32 always returns `global_name: null`. MemberList and MentionAutocomplete fetched via REST won't show custom display names. This directly contradicts the PR's stated scope.

### 🌠 Nova
- **🟡 `repos.users.update(id!, body)` passes full request body** — The repo whitelists fields, but passing `body` directly is fragile. Build the patch object explicitly: `{ username, avatar, bio, global_name }`.
- **🟡 `findByToken` redundant cast** — `(row as UserRow).global_name` when row is already typed with `UserRow`.
- **🟡 Plugin log line** — `channel.ts:335` logs `global_name` which could contain control chars (moot once C2 is fixed).
- **💬 `nick` chain incomplete** — MessageItem only uses `global_name || username`, ignoring `nick`. Add a TODO comment for when guild `nick` support lands.

### 💫 Vega
- **🟡 OAuth `COALESCE(global_name, ?)` overwrites user-cleared names** — If a user explicitly clears their display name (`null`), the next OAuth login repopulates it from Google `given_name` via `COALESCE(null, given_name)`. Can't distinguish "never set" from "explicitly cleared". (Note: Nova flagged this same pattern as a *positive* — "never clobber user-customized name". Both perspectives are valid — the question is product intent for the "user cleared it" case.)
- **🟡 `validateString` may reject `null`** — Verify that sending `{ global_name: null }` to clear the name doesn't hit a 400.

---

## Summary

| Reviewer | Rating | Key Concern |
|----------|--------|-------------|
| 🌟 Stella | ⚠️ Needs Changes | `toUser()` drops `global_name` for member list |
| 🌠 Nova | ⚠️ Needs Changes | Empty string normalization + control char validation |
| 💫 Vega | ⚠️ Needs Changes | OAuth COALESCE overwrites user-cleared names |

**Priority fixes before merge:**
1. Fix `toUser()` in `members.ts` to propagate `global_name` (Stella's C1)
2. Normalize empty/whitespace `global_name` to `null` server-side (C1)
3. Add control character / zero-width / RTL validation (C2)
4. Decide product intent for OAuth re-login when user cleared name (Vega's finding)
5. Add basic tests for `PATCH /users/@me` and resolveUser regression (C3)

None of these are structural — once addressed, this should be a quick re-review. The overall implementation is clean and thorough.
