# 🌠 Nova — Round 3 Re-Review: PR #348 (kagura-agent/cove)

**PR:** feat: custom display name (global_name) support (closes #186)
**Stats:** +388 / −50, 25 files
**Head SHA:** `061f1fc7808d7bca970ced2d1cc73b881a78568c`

---

## 1. R2 Outstanding Issue Status

### Consensus / Cross-Reviewer

| ID | Issue | R3 Status | Notes |
|---|---|---|---|
| **M3 / CI webhook shell injection** | Crafted PR title could break/inject JSON or shell | ✅ **Fixed** | `.github/workflows/ci.yml` now uses an `env:` block (`PR_NUMBER`, `PR_TITLE`, `RUN_URL`) and pipes `jq -nc --arg pr … --arg title … --arg url …` into `curl -d @-`. Title is never expanded by the shell or by JSON; `jq --arg` handles quoting safely. Clean, idiomatic fix. |
| **M2 / OAuth `given_name` not validated** | Upstream value bypassed `validateDisplayName` | ✅ **Fixed** | Both branches in `routes/auth.ts` (existing user + new pending registration) now compute `givenName = (!validateDisplayName(googleUser.given_name)) ? (googleUser.given_name ?? null) : null` before persisting. Control / ZWSP / RTL-override values are coerced to `null`. |
| **OAuth re-login `COALESCE(global_name, ?)`** | R3 claim: "added COALESCE(global_name, ?) to UPDATE" | ❌ **Not Fixed → 🔴 regression (escalated)** | See §1.5 below — this re-introduces the exact R1 concern that R2 had eliminated. |

### 1.5 — 🔴 Critical regression: OAuth re-login `COALESCE` overwrites user-cleared `global_name`

**File:** `packages/server/src/routes/auth.ts` (existing-user branch)

```ts
db.prepare(
  "UPDATE users SET ..., global_name = COALESCE(global_name, ?) WHERE id = ?"
).run(..., givenName, existing.id);
```

In R1, Vega flagged that touching `global_name` on every OAuth re-login would silently clobber the user's preference. R2 fixed it by **not** touching `global_name` on re-login at all (my R2 review explicitly verified this: *"Existing-user OAuth path … does not touch `global_name` at all on re-login. Cleared names stay cleared. Good."*).

R3 re-adds the column to the UPDATE list, just behind `COALESCE`. Walking the semantics:

| Pre-login `users.global_name` | Action |
|---|---|
| `NULL` (never set, **or user just cleared it in Settings**) | `COALESCE(NULL, givenName)` → overwritten with Google `given_name` |
| `'My Cool Name'` (user chose one) | `COALESCE('My Cool Name', givenName)` → preserved ✅ |

**The first row is the regression.** A user who deliberately clears their display name in Settings (Discord-aligned UX: "revert to account name") will have it silently re-filled with `given_name` on their next OAuth re-login — which on a server with cookie expiry happens routinely. They will have to clear it *again*, and *again*. The Settings hint literally says *"Leave empty to use your account name"* — but OAuth re-login then refuses to honour that.

Worse, there's **no test for this path** (see C3 below), and the only way the user discovers the bug is by re-clearing every login cycle.

Per the escalation rule (R1 → R2 fix → R3 reverted) this is now **🔴 critical / blocker**. The R2 approach (don't touch `global_name` on re-login at all) was correct.

**Minimum fix:** drop `global_name = COALESCE(...)` from the existing-user UPDATE entirely — leave it only on the *new-user* `pending_registrations` insert (which is fine; pending rows have no prior value to preserve).

If we *do* want a seed-on-first-time path for legacy users who pre-date the column, gate it explicitly:

```ts
const currentRow = db.prepare("SELECT global_name, created_at, updated_at FROM users WHERE id = ?").get(existing.id);
// Only seed when never set AND user has never been near a Settings save
// Better: don't seed at all for legacy users; let them pick in Settings.
```

But the safer answer is just: don't.

### From my (Nova) R2 findings

| ID | Issue | R3 Status | Notes |
|---|---|---|---|
| **M2** | OAuth `given_name` bypasses `validateDisplayName` | ✅ **Fixed** | See above. Both branches validated. |
| **M3** | CI webhook shell injection | ✅ **Fixed** | See above. |
| **S3** | `findByToken` redundant hand-built literal | ❌ **Not Fixed** | `repos/users.ts:findByToken` still constructs `{ id, username, avatar, bot, bio, discriminator, global_name, expires_at }` manually instead of `{ ...toUser(row), expires_at: row.expires_at }`. Trivial nit, no behavior risk. **Severity unchanged at S3** per escalation rule (was already a stylistic flag). |
| **C3 (a)** | Missing OAuth re-login preservation test | ❌ **Not Fixed → 🟡 escalated** | `display-name.test.ts` contains no test exercising the OAuth UPDATE path. Critical now because §1.5 shows the path is broken — a regression test would have caught it. Adding one is now a blocker, not just nice-to-have. |
| **C3 (b)** | Missing `resolveMentions` test | ❌ **Not Fixed** | The new "message author round-trip" test exercises the `MSG_SELECT` join, but `resolveMentions` in `MessagesRepo.create` (lines 320-336) — which assembles `Message.mentions[].global_name` — is not covered by any new assertion. Easy add: send `"hi <@display-bot>"`, assert the persisted/returned message has `mentions[0].global_name === "Friendly Bot"`. **Severity unchanged at S/C-tier** — not a blocker, but should land. |
| **P1 (new in R2)** | `api.updateMe` client return type drift | ❌ **Not Fixed** | `packages/client/src/lib/api.ts` still types the response as `{ id; username; avatar; global_name }` — server actually returns full `CoveAgent` (includes `bot`, `bio`, `discriminator`). Harmless at current call site; should be `Promise<CoveAgent>` from `@cove/shared`. |
| **P3 (new in R2)** | Missing `discriminator` / `bio` in `/api/auth/me` | ❌ **Not Fixed** | Response is still `{ id, username, avatar, bot, global_name, expires_at }`. No `discriminator`, no `bio`. Deliberate slim payload; only worth widening when client actually starts using `discriminator` for the new display chain. Stays at P3. |

### From other reviewers (Stella)

| Issue | R3 Status | Notes |
|---|---|---|
| **Mention map keyed by non-unique display name** | ❌ **Not Fixed** | `MessageInput.tsx` line ~165 still does `mentionMapRef.current.set(username, userId)` (here `username` is the display string the user clicked, i.e. `global_name || username`). Two members with display name `"Cool Admin"` collide: only the second user's id survives in the map, and any `@Cool Admin` in the textarea resolves to that one. Compound issue with R3's COALESCE seeding (§1.5), which makes collisions more likely because everyone whose Google `given_name` is `"David"` now ships with `global_name = "David"` by default. **Status: 🟡 medium, worth a follow-up issue** even if not blocking this PR. |
| **Optimistic self-message ignores current `global_name`** | ❌ **Not Fixed** | `MessageInput.tsx` `handleSubmit` still builds `pendingMessage.author` with `global_name: null` hardcoded, even though `useUserStore.getState()` now exposes it. The optimistic bubble for your own message therefore shows `username` until the WS roundtrip replaces it with the server-rendered one with `global_name`. Visible flicker for any user with a custom name. One-line fix: `global_name: user.global_name`. |
| **Whitespace >80 chars rejected instead of normalized** | ❌ **Not Fixed** | I noted this in R2 as M1 (validation runs before normalization). Order in `routes/agents.ts` is unchanged: `validateString({maxLength:80})` runs on the raw string, so `" ".repeat(81)` is 400 instead of normalising to `null`. Edge case; not blocking. |
| **Nick chain incomplete in MessageItem (TODO in R2)** | ⚠️ **Acknowledged, not fixed** | TODO comment still present (`// TODO: add nick (guild member nickname) when server-level nick support lands`). Same as R2. Inconsistency with `MemberList` persists. Stays at follow-up issue. |

---

## 2. New Issues (fresh review of R3 changes)

### 🔴 N1 — Length not enforced on `given_name` ingestion path
**File:** `packages/server/src/routes/auth.ts`

```ts
const givenName = (!validateDisplayName(googleUser.given_name)) ? (googleUser.given_name ?? null) : null;
db.prepare(... global_name = COALESCE(global_name, ?) ...).run(..., givenName, ...);
```

`validateDisplayName` only checks the **charset** (control / ZWSP / RTL). It does **not** enforce the 80-char `maxLength` contract that PATCH `/users/@me` enforces. A Google `given_name` longer than 80 characters (rare but possible for legal/transliterated names) is stored unsanitised. The same value would be rejected if the user typed it into Settings.

**Fix:** mirror the PATCH limit at the boundary:
```ts
const raw = googleUser.given_name;
const givenName =
  raw && !validateDisplayName(raw) && raw.length <= 80
    ? raw
    : null;
```
Apply in both the existing-user and pending-registration paths. (When §1.5 is fixed by dropping the existing-user COALESCE, this only needs to apply to the pending-registration path.)

**Severity:** medium — data-integrity, not security. Combined with §1.5, the existing-user UPDATE could write an arbitrarily long `global_name` that a Settings save would then refuse to round-trip.

### 🟡 N2 — `validateDisplayName(undefined)` returns `null` (= "valid"), conflating "absent" with "valid present"
**File:** `packages/server/src/validation.ts`

```ts
export function validateDisplayName(value: unknown): string | null {
  if (value === undefined || value === null) return null;
  ...
}
```

Returning `null` (no-error) for `undefined` is correct for the PATCH path (field is optional). But in the OAuth path, the call site uses

```ts
(!validateDisplayName(googleUser.given_name))
```

as a boolean predicate — so `undefined` (Google didn't return `given_name`) and *"non-empty, validated string"* are both "truthy good". That happens to work because the **only** other read is `googleUser.given_name ?? null`, which correctly falls back to `null` on `undefined`. So no current bug, but the pattern is fragile: any future call site that reads `validateDisplayName` as "definitely a valid display name" will misfire on `undefined`.

**Suggested cleanup:** name the predicate clearly:
```ts
function sanitizeOptionalDisplayName(raw: unknown, max = 80): string | null {
  if (typeof raw !== "string") return null;
  if (validateDisplayName(raw)) return null;
  if (raw.length === 0 || raw.length > max) return null;
  return raw;
}
```
and use it in both OAuth call sites. This also folds in N1.

### 🟢 N3 — `migration.test.ts` numeric assertions
**File:** `packages/server/src/__tests__/migration.test.ts`

Multiple `expect(version).toBe(13)` calls now appear under `describe` blocks titled `"fresh DB gets user_version = 10"`, `"V2→V3 migration (UUID→Snowflake)"`, etc. The titles are stale (they still claim `10` / `3`). Cosmetic, but mildly confusing if a regression bisects to one of these tests. Suggest a rename pass next time the file gets touched.

### 🟢 N4 — `MentionAutocomplete` `displayName` derivation duplicated
**File:** `packages/client/src/components/MentionAutocomplete.tsx`

`m.user.global_name || m.user.username` is computed inline in four places (filter, two `onSelect` calls, label render). Extracting once would reduce drift risk if the chain ever grows to include `nick`. Cosmetic.

### 🟢 N5 — Migrations split V12 / V13 with `pending_registrations` only touched in V13
**Files:** `db/migrations/v12-global-name.ts`, `v13-pending-global-name.ts`

Splitting one logical change ("add `global_name` everywhere it lives") across two versioned migrations is fine but slightly noisy — a fresh `initDb()` runs both, and pending DBs that never had `pending_registrations` (none today) silently skip V13 via `tableExists`. No correctness issue. The migrations themselves are idempotent and correctly guarded. Just observing: this is the kind of split that becomes painful in a few releases — consider merging when the underlying logical unit is small.

---

## 3. Summary + Verdict

R3 delivers two real fixes I called out in R2:
- ✅ **CI webhook shell-injection (M3)** — clean env+`jq` rewrite
- ✅ **OAuth `given_name` charset validation (M2)** — wired into both OAuth branches

And it introduces one critical regression:
- 🔴 **§1.5 — OAuth re-login COALESCE re-fills user-cleared `global_name`**: the R2 fix was deliberately "don't touch `global_name` on re-login"; R3 added a `COALESCE` that, by construction, overwrites the user's deliberate "clear → revert to username" choice on every subsequent OAuth login. This is the exact R1 concern Vega raised, re-introduced under a slightly different code shape.

Plus one new medium and several stylistic issues:
- 🔴/🟡 **N1 — `given_name` length unbounded on ingestion** (compounds §1.5)
- 🟡 Stella's mention-map collision and optimistic self-message regressions remain unaddressed
- ❌ Tests for OAuth re-login preservation and for `resolveMentions` still missing — the former would have caught §1.5 before it shipped

### Recommended actions before merge

**Must (blockers):**
1. **Revert §1.5** — drop `global_name = COALESCE(global_name, ?)` from the existing-user OAuth UPDATE. Leave the seeding only on the *new-user* `pending_registrations` insert.
2. **Add OAuth-relogin regression test** — drive the OAuth callback twice for the same `google_id`: (a) user sets `global_name = "Mine"` → re-login → still `"Mine"`; (b) user clears to `null` → re-login → still `null`.
3. **Bound `given_name` to 80 chars** at OAuth ingestion (N1).

**Should:**
4. Add a `resolveMentions` test that asserts `Message.mentions[i].global_name` is populated from the DB.
5. Fix optimistic self-message `global_name: null` hardcode in `MessageInput.tsx`.
6. Tighten `api.updateMe` return type to `CoveAgent`.

**Nice to have:**
7. Refactor `validateDisplayName` into a sanitizer (N2). Fix mention-map keying collision. Drop hand-built literal in `findByToken` (S3). Update stale `describe` titles in `migration.test.ts` (N3).

### Verdict: ❌ **Major Issues**

The CI/security fixes from R2 landed correctly, but R3 re-introduced a confirmed R1-class regression in the OAuth path (§1.5) — and shipped it without the regression test that would have caught it. Per the escalation rule, an issue that was reported in R1, fixed in R2, and re-broken in R3 cannot ship at "Needs Changes". Block until §1.5 is reverted and a re-login preservation test exists.

Once §1.5 is fixed and the OAuth-relogin + `resolveMentions` tests land, this PR is one small refactor pass away from clean merge.

— 🌠 Nova
