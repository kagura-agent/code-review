# 🌠 Nova — Round 2 Re-review · PR #381

**Repo:** kagura-agent/cove
**PR:** feat(server): webhook execute supports ?wait and ?thread_id (#293)
**Branch:** feat/webhook-wait-thread-293 → main
**Scope:** +181 / −11 across 3 files
**Verdict:** ⚠️ **Needs Changes (minor)** — fixes look solid, but the "breaking change documented" claim is **not actually true** in CHANGELOG.md, and a couple of small consistency issues are worth a polish pass before merge.

---

## 1. R1 fix verification

### ✅ 6 new tests — fixed
`packages/server/src/__tests__/webhooks.test.ts` now adds:
1. `execute without ?wait returns 204 with no body` — asserts status + empty text.
2. `execute with ?wait=true returns 200 with message` — asserts status + body shape.
3. `execute with ?thread_id routes message to thread` — creates real thread, asserts `msg.channel_id === thread.id`.
4. `execute with invalid thread_id returns 404` — asserts code 10003.
5. `execute with archived thread returns 403` — toggles archived via PATCH, asserts code 50083 + message.
6. `execute with locked thread returns 403` — toggles locked via PATCH, asserts code 50083 + message.

Plus 4 pre-existing tests correctly updated to `?wait=true` and `status 200`. ✅

### ✅ Locked thread check — fixed
Lines 158–160 of `routes/webhooks.ts`:
```ts
if (thread.thread_metadata?.locked) {
  return c.json({ message: 'This thread is locked', code: 50083 }, 403);
}
```
Mirrors the archived check, mirrors `routes/messages.ts:104–112`. Test #6 covers it. ✅

### ✅ Thread types 10/11/12 — fixed
Line 153:
```ts
if (!thread || ![10, 11, 12].includes(thread.type) || thread.parent_id !== webhook.channel_id) {
```
Now accepts announcement (10), public (11), private (12) threads — matches Discord semantics. ✅

### ⚠️ Breaking change documented — **NOT fixed**
PR description claims "Discord-compatible: default is 204 No Content (breaking change from always-201)" and the code comment says the same, **but `CHANGELOG.md` has no entry for #381 / #293**. The file still ends at the `bot` field change for #264/#265. R1 explicitly asked for a CHANGELOG entry under `## [Unreleased] → ### Breaking Changes`; that hasn't landed.

Required entry should call out:
- Endpoint: `POST /api/webhooks/{id}/{token}`
- Old: always returned 201 with message body
- New: returns 204 No Content by default; pass `?wait=true` to get 200 + body
- Migration: existing callers that read `res.json()` must either append `?wait=true` or stop reading the body

---

## 2. Fresh review — findings beyond R1

### 🟡 Minor 1 — `incrementMessageCount` SQL only matches type = 11
`repos/threads.ts:118–122`:
```ts
incrementMessageCount(threadId: string): void {
  this.db.prepare(
    "UPDATE channels SET message_count = ..., total_message_sent = ... WHERE id = ? AND type = 11"
  ).run(threadId);
}
```
The webhook route now permits posting to type 10 / 12 threads, but the counter is silently a no-op for those types. Today cove only creates type-11 threads (see `repos/threads.ts:178`), so this is latent rather than active — but the type guard at the route level (`[10, 11, 12]`) and the type guard at the repo level (`= 11`) are now out of sync. Two reasonable options:
  - **(a)** Restrict the route to type 11 for now until 10/12 are actually supported.
  - **(b)** Relax the repo SQL to `type IN (10, 11, 12)` to match the route.

Suggest (a) for this PR — minimal surface area, easy to expand later when announcement / private threads ship.

### 🟡 Minor 2 — thread validation runs **before** rate-limit check
Route ordering (lines 144–175):
1. Webhook lookup (404)
2. **Thread lookup (404/403)** ← here
3. Rate-limit window check (429)

Result: an attacker who has the webhook token can probe arbitrary `thread_id` values and learn "exists but wrong parent" vs "doesn't exist at all" without consuming a rate-limit token, and without ever hitting the 30/min cap. The leak surface is small (token is already a secret), but Discord's own ordering rate-limits first. Cheap fix: hoist the rate-limit block above the thread validation. Non-blocking.

### 🟡 Minor 3 — `?wait` only accepts exact string `"true"`
```ts
const wait = c.req.query('wait') === 'true';
```
Discord accepts `wait=true|false`; `wait=1`, `wait=True`, `wait` (no value) all silently fall through to the 204 branch. This matches Discord's "strict string compare" behaviour, so it's fine — just flagging for awareness. No change required.

### 🟢 Nice — `thread_id=""` handled
Empty string is falsy, so `if (threadId)` skips validation and posts to the parent channel. Behavior is sensible and matches the "thread_id absent" path.

### 🟢 Nice — `parent_id` cross-channel check
`thread.parent_id !== webhook.channel_id` correctly prevents using one webhook to post into a thread under a different channel (or different guild). Good defence-in-depth.

### 🟢 Nice — counter increment only on thread path
The `if (threadId)` guard around `incrementMessageCount` correctly avoids double-counting or no-op-ing on parent-channel posts. Symmetric with `routes/messages.ts:223–225`.

---

## 3. Test quality

- Tests use real `app.request` against the full Hono pipeline — good integration coverage.
- Both happy paths (200 with wait, 204 without) and failure paths (404 invalid, 403 archived, 403 locked) covered.
- Code-and-message assertions on 50083 catch the two branches separately. ✅
- **Gap:** no test for `thread.parent_id !== webhook.channel_id` (the cross-channel guard) — a thread in a *different* channel returning 404 would lock in that behavior. Recommend adding one before merge.
- **Gap:** no test for rate-limit interaction with thread posting (does the bucket key remain `webhookId` rather than `webhookId:threadId`?) — current behaviour seems intentional but isn't pinned.

---

## 4. Summary

| Concern                              | Status         |
|--------------------------------------|----------------|
| 6 new tests (R1)                     | ✅ Fixed       |
| Locked thread check (R1)             | ✅ Fixed       |
| Thread type 10/11/12 (R1)            | ✅ Fixed (route) |
| Breaking change documented (R1)      | ❌ Not in CHANGELOG.md |
| Type guard sync (route vs repo)      | 🟡 Out of sync |
| Rate-limit order                     | 🟡 Probe leak  |
| Cross-channel test coverage          | 🟡 Missing     |

**Verdict:** ⚠️ **Needs Changes** — please (1) add the CHANGELOG entry and (2) decide between the two type-guard options. Items 2–4 are polish; happy to see them in a follow-up. Implementation is otherwise clean and Discord-aligned. 🚀

— Nova
