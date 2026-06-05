# 🌠 Nova Review — PR #222 (cove) — Round 3

**refactor: API protocol alignment and infrastructure fixes**
Branch: `refactor/api-protocol-alignment` → `main` · 21 files · +221/-68 · 4 commits
Latest: `fix: MESSAGE_DELETE_BULK allowlist, @me alias, bulk-delete TODO`

## R2 Issue Status

### Critical

**C3 — Bulk-delete permission / age / dedup gaps**: ⚠️ **Partially Fixed**
- ✅ **TODO comment**: added at `messages.ts:138` (route-level) and `messages.ts:128` (single-delete), explicitly referencing `#113`. This satisfies the *documentation* half of my R2 verdict option #1.
- ❌ **Follow-up issue**: I have no evidence of a tracked GitHub issue covering the four open gaps (bulk-delete permission, 14-day age limit, dedup, single-DELETE author check). The PR body / commit message doesn't link one. If #113 doesn't already enumerate these specifically, please add a short issue or update #113's checklist — otherwise the TODO is a comment-only paper trail that fades on rebase.
- ❌ **14-day age limit**: still not implemented (Discord `50034`). Unchanged.
- ❌ **Dedup**: still not implemented (Discord `50016`). Caller batching with accidental duplicates still gets a misleading 204. Unchanged.
- ❌ **Zero-deleted = 204**: still returns 204 even if none of the IDs existed. Unchanged.

**C4 — Single DELETE no author check**: ⚠️ **Partially Fixed**
- Same posture as R2 — no author check, but TODO is present (`messages.ts:128`). The author-vs-MANAGE_MESSAGES asymmetry with PATCH (`messages.ts:96`) remains. Acceptable *only if* #113 (or a new issue) explicitly tracks single-DELETE author check as a blocker.

### Suggestions

| ID | R2 Suggestion | R3 Status |
|---|---|---|
| S1 | Replace dropped `code: 10013` on `User already exists` with a meaningful code | ❌ Still bare 409 — `agents.ts:28`. Note: this PR's diff is the change that *removed* `10013` (it was wrong: 10013 = Unknown User). Removal was correct; replacement with `50035` or no code at all should be a conscious choice, not "we deleted it and moved on". |
| S2 | Collapse two length checks in bulk-delete | ❌ Still split — `messages.ts:151-156` |
| S3 | Comment on snowflake lex-sort assumption in v5 backfill | ❌ Not addressed (`schema.ts:333-339`). The backfill `ORDER BY m.id DESC` relies on snowflakes sorting lexicographically — true for fixed-width strings but worth a one-liner. |
| S4 | Debug-log unknown opcodes after dropping REQUEST_TYPING | ❌ Not addressed (`ws/index.ts:81` — `default: break;`). Clients that haven't updated will silently see their op-4 sends vanish. |
| S5 | Negative tests for ownership checks and bulk validation | ❌ Not addressed. Diff still only flips positive-path auth headers — no `user-A→user-B 403` tests, no `bulk-delete with 1 / 101 / non-array` 400 tests, no `@me-alias` test. The new `@me` aliasing in three endpoints is shipping completely uncovered. |
| S6 | Wire `/gateway/bot` shards / limits through config | ❌ Still hardcoded (`app.ts:51-55`) |
| S7 | Drop `guild_id` from `MESSAGE_DELETE_BULK` `d` payload | ❌ Still duplicated (`dispatcher.ts:81`). Client (`gateway-subscriptions.ts:48`) doesn't read `d.guild_id`, confirming it's dead weight. |

### Notes

| ID | R2 Note | R3 Status |
|---|---|---|
| N1 | Client bulk-delete loops per-id instead of batching | ❌ Unchanged (`gateway-subscriptions.ts:47-52`) |
| N2 | Typing-cue REST regression (~12 calls / burst, silent `.catch`) | ❌ Unchanged (`channel.ts:246-260`) |
| N3 | `Repos.db` exposure breaks repo encapsulation | ❌ Unchanged (`repos/index.ts:22`). Bulk-delete still reaches into `repos.db.transaction(...)`. A `MessagesRepo.deleteMany(channelId, ids)` returning surviving IDs would keep the txn inside the repo. |
| N4 | `GET /gateway/bot` unauthenticated stub | ❌ Unchanged (`app.ts:51-55`). Adding `auth` now is a 2-line change and avoids a silent breaking change later. |
| N5 | `CHANNEL_CREATE`/`DELETE` broadcast scope | ❌ Unchanged — left for follow-up. |

R2 Caveat on **C1** (CHANNEL_DELETE should carry full Channel object, not `{id, guild_id}`): ❌ Unchanged (`dispatcher.ts:93`, `gateway-dispatcher.ts:13`).

---

## New Issues (R3 fresh-eyes pass)

### N6 — `MESSAGE_DELETE_BULK` client allowlist fix was a latent dispatcher bug ✅ (fixed in this round)
`useWebSocketStore.ts:90` now includes `"MESSAGE_DELETE_BULK"` in the gateway allowlist. Without this, the new event from R2 would have been **silently dropped by the client filter** before reaching `gateway-subscriptions.ts`. The R2 reviewer (me) missed this because I read the subscription code and assumed dispatch worked. Good catch by the PR author. Calling it out so the lesson sticks: **adding a new gateway event requires updating both the dispatcher map AND the WS allowlist**. Worth a comment near each of those two structures, or even unifying them (the allowlist could be derived from `keys(GatewayEventMap)`).

### N7 — `@me` aliasing semantics: token-regen, PATCH, DELETE now self-only (agents.ts:35-42, 63-70, 91-98)
The new pattern is clean — resolve `@me` to `actorId`, then check `id === actorId`. After this change:
- `POST /users/:id/token`: was admin-only by virtue of `auth` middleware + raw id (i.e., admins could regen anyone's token). Now **only the user themselves**, even with an admin token, can regen. This is the Discord-correct behavior (`/users/@me/...` is the only legitimate path).
- `PATCH /users/:id` and `DELETE /users/:id`: same shift — admin tokens can no longer modify/delete other users.

This is a **silent capability regression** for admin tooling that may have relied on it (e.g., the existing test suite at `api.test.ts:706-737` had to be rewritten to use the target user's own token rather than `adminToken`). Should be called out in the PR description / changelog as a breaking change. If an admin escape hatch is intended later (e.g., `POST /users/:id/disable` for moderation), worth a TODO. **Severity: Note.**

### N8 — `@me` alias not tested (agents.ts:35-98)
The whole point of `@me` aliasing is that `GET/PATCH/DELETE /users/@me/...` works. There is zero test coverage in this diff exercising the literal string `"@me"`. A single test like `app.request("/users/@me", { method: "DELETE", headers: { Authorization: \`Bot ${user.token}\` } })` would pin this down. **Severity: Suggestion** (folds into S5).

### N9 — `recomputeLastMessageId` in bulk-delete can still write the same value (messages.ts:166)
Minor: `repos.channels.recomputeLastMessageId(channelId)` runs unconditionally when `deleted.length > 0`, even if the latest message wasn't among the deleted IDs. The single-DELETE path correctly gates on `ch.last_message_id === msgId`. Bulk could check `deleted.includes(ch.last_message_id)` to avoid the write. Not a correctness bug; just a stylistic asymmetry. **Severity: Nit.**

---

## Anti-Confirmation Bias Pass

- **`@me` aliasing — did I miss a bypass?** Walked through each of the three endpoints: `rawId → actorId if @me, else rawId`, then `if (id !== actorId) 403`. No bypass via case (`@ME` would not match — confirmed, JS `===` is case-sensitive). No bypass via URL-encoding (Hono decodes path params before this code runs). No bypass via empty string (`""` !== actorId → 403). Looks tight.
- **R2 verdict was option #1 OR option #2.** The PR author chose option #1 (TODO comment). I'm honoring that choice but flagging the missing follow-up-issue half. I did **not** silently downgrade C3/C4 to ✅ on the strength of a comment alone — the gaps remain, the comment just documents them.
- **Did the `db: Database.Database` exposure (N3) get tightened?** Re-read `repos/index.ts` — still exported, still reached for in `messages.ts:158`. No new callers added in this round, but no walk-back either.
- **Did anything new land that R2 didn't see?** Three new things: (1) MESSAGE_DELETE_BULK allowlist (good fix, latent bug), (2) `@me` aliasing on three endpoints (silent admin regression — worth a changelog note), (3) bulk-delete TODO. Reviewed all three above.

---

## Summary

R3 addressed exactly what was promised in the commit message: client allowlist for the new bulk event (a real latent bug), `@me` aliasing for self-only profile endpoints, and a TODO acknowledging the bulk-delete permission gap. Everything else from R2 — both the gating items and the long suggestion tail — is unchanged.

The bar I set at R2 was: **TODO + linked follow-up issue, OR a minimal author-only check**. Half of option #1 landed (TODO). The other half (the issue link) I cannot verify from the diff alone. If #113 already covers single-DELETE author check, bulk-delete permission, 14-day age limit, and dedup as explicit items, this is fine. If not, please update #113 or open a new tracking issue and reference it in the PR body — otherwise the TODOs are just comments that will outlive everyone's memory of why they were added.

The `@me` aliasing change is **good and Discord-correct**, but it removes admin override on three endpoints and ships with **zero tests** for the alias path itself. That's the thing I'd most want pinned down before merge: one test per endpoint that hits `/users/@me/...` and confirms `200 / 204`, plus one negative test that hits `/users/<other-id>` with a non-admin token and confirms `403`. That's ~30 lines of test code and locks in the contract permanently.

The R2 suggestion tail (S1–S7, N1–N5) is now two rounds old and untouched. Time to either action or formally drop them — carrying them forever isn't useful. My recommendation: file a single "PR #222 follow-ups" issue listing S1, S2, S3, S4, S6, S7, N1–N5, and close them out of review scope.

## Verdict

**Rating: ⚠️ Needs Changes**

Blocking-before-merge:
1. **Confirm or open the follow-up issue** covering: bulk-delete permission, 14-day age limit, dedup, single-DELETE author check. Link it in PR body. Without this, C3/C4 close as "comment-only" and the moderation gaps quietly ossify.
2. **Add at least one `@me` alias test** per endpoint (token-regen, PATCH, DELETE) — positive (self) + negative (other user → 403). N8 / S5. Cheap, locks in the new contract.
3. **Changelog / PR-body note** on the silent admin capability regression for `POST /users/:id/token`, `PATCH /users/:id`, `DELETE /users/:id`. N7.

Non-blocking but recommended this round (pick one or two, drop the rest formally):
- S7 — drop redundant `guild_id` from `MESSAGE_DELETE_BULK` `d` payload (1-line)
- N9 — gate bulk-delete's `recomputeLastMessageId` on `deleted.includes(ch.last_message_id)` (1-line, matches single-delete asymmetry)
- N4 — add `auth` middleware on `/gateway/bot` stub now to avoid a future silent breaking change (2-line)
