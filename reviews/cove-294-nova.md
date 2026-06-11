# PR #294 — Round 4 Re-review (Nova 🌠)

**PR:** feat: add webhook support for cross-channel messaging
**Repo:** kagura-agent/cove
**Round:** 4 (re-review after author's fixes)

---

## 1. Summary

Round 4 confirms that the author addressed the **majority** of the previous round's blockers: client-side auth path is unblocked, negative auth tests landed, avatar input is validated, and a deleted-webhook null-crash has been guarded. The remaining issue is that C3's fix only prevents the crash — it does not preserve the original message identity, so historical webhook messages collapse to a generic "Deleted Webhook" author string after a webhook is removed. That's the only real functional gap I'd block on; everything else is suggestion-grade.

**Verdict: ⚠️ Needs Changes** — one near-Critical (C3 partial fix → information loss), small but easy to finish in this PR.

---

## 2. Status of previous-round issues

| ID | Description | Round 3 severity | Round 4 status |
|----|-------------|------------------|----------------|
| C1 | Bot-only auth on CRUD blocks client UI | Critical | ✅ **Resolved** — client UI calls `api.fetchWebhooks/createWebhook/deleteWebhook` and the `non-member user gets 404` test uses `Bearer <token>` and is accepted by middleware before being rejected at member check, confirming non-bot tokens reach the routes (`packages/server/src/__tests__/webhooks.test.ts:218–235`). |
| C2 | Webhook avatar identity lost on reload | Deferred | ⏸️ Same status — `createFromWebhook` (`repos/messages.ts:157–161`) does not persist `webhookAvatar`; reload returns `avatar: null`. Username override **is** persisted via `sender_name`, which is good, but avatar override is not. Acceptable as deferred. |
| C3 | Deleting webhook corrupts historical message identity | Critical | ⚠️ **Partially resolved** — see Critical Issues below. |
| C4 | Missing negative auth tests | Critical | ✅ **Resolved** — `webhooks.test.ts` adds: unauthenticated → 401, non-member → 404 / code 10003, wrong webhook token → 404, cross-guild user → 404, plus content/username/avatar_url validation tests. |
| C5 | Missing avatar validation on create/PATCH | Critical | ✅ **Resolved** — `routes/webhooks.ts:21–24` (POST), `routes/webhooks.ts:91–94` (PATCH) both call `validateString(..., { maxLength: 2048 })`. |
| C6 | Rate-limit cleanup runs on every request | Deferred | ⏸️ Same status — `routes/webhooks.ts:160–168` still scans all buckets per request. Bounded by `MAX_BUCKETS = 10_000`, tolerable for now, but the deferred issue persists by design. |

Per the escalation rule: nothing newly broken, no escalations needed except C3 needs to stay Critical.

---

## 3. Critical Issues

### C3 (still Critical — partial fix only): historical webhook messages lose identity on webhook delete

**Where:** `packages/server/src/db/migrations/v8-webhooks.ts:18` (`messages.webhook_id ... REFERENCES webhooks(id) ON DELETE SET NULL`) combined with `packages/server/src/repos/messages.ts:24–43` (`toMessage`).

**What now happens:**
1. Webhook executes a message → row stored with `sender=NULL`, `sender_name=<displayName/override>`, `webhook_id=<id>`.
2. Admin deletes the webhook → `ON DELETE SET NULL` zeros out `webhook_id`. `sender` is still NULL. `sender_name` (the actual identity, possibly the per-execution `username` override) is **still in the row**.
3. `toMessage` runs the three-branch `if/else if/else`:
   - `webhook_id` is NULL → skip first branch.
   - `sender` is NULL → skip second branch.
   - Falls into the third branch and emits `{ id: "0", username: "Deleted Webhook", bot: true, ... }`.

The row still has the original display name in `sender_name`, but `toMessage` never reads it on this path, so the data is discarded at serialization time. Result: every historical webhook message in a channel changes its visible author the moment a webhook is deleted, which is exactly the corruption flagged in Round 3. This is a meaningful product regression vs Discord (which preserves the historical webhook name on deleted webhooks) and breaks audit/log readability.

**Minimal fix:** add a fallback branch that prefers `sender_name` whenever it exists, regardless of whether `webhook_id` survives:

```ts
} else if (row.sender_name) {
  author = {
    id: "0",
    username: row.sender_name,
    avatar: null,
    bot: true,
    discriminator: "0",
    global_name: null,
  };
} else { /* current "Deleted Webhook" fallback */ }
```

Plus: add a regression test that creates a webhook, executes it (with and without `username` override), deletes the webhook, and asserts the historical message author still reads `sender_name` rather than `"Deleted Webhook"`.

(Alternative: drop `ON DELETE SET NULL` and keep `webhook_id` so the first branch keeps firing — but the row+fallback approach is the smaller change and also covers any future row where `webhook_id` is genuinely missing.)

---

## 4. Product Impact

- **Identity preservation on delete (C3 above)** is the main user-visible risk. Channel transcripts will silently rewrite authorship history after webhook cleanup. For a project pitching webhooks as "Channel as Service" cross-channel messaging, this is the worst possible UX surprise — it makes audit trails untrustworthy.
- **Webhook URL construction in client** (`ChannelSettings.tsx:104`): hardcodes `/api/v10/webhooks/...`. The rest of the client uses `API_PREFIX` from `@cove/shared`. If `API_PREFIX` ever changes, the displayed/copied URL silently becomes wrong while the rest of the UI keeps working. Trivial fix: import and interpolate `API_PREFIX`.
- **Avatar override not persisted (C2, deferred):** consciously accepted per Round 3, but worth re-noting for users — the displayed avatar of a webhook message is `null` after reload even when `avatar_url` was passed at execution time. Consider documenting this in the SKILL.md or the PR description so plugin authors don't expect Discord parity here.
- **Webhook `name` shown in client URL list** when token is no longer in memory (e.g. after page reload) renders "Token hidden — URL was shown at creation" with a disabled Copy button. Functional, but a brand-new user creating a webhook and immediately reloading will think it's broken. A short helper text ("URLs are only shown once at creation; delete and recreate to get a new one") would close the loop.

---

## 5. Suggestions (non-blocking)

1. **PATCH route is untested.** `routes/webhooks.ts:73–106` has its own validation and member check, but no test exercises it. Add at least a "PATCH name + avatar" happy path and a "PATCH by non-member → 404" case.
2. **GET `/guilds/:id/webhooks` is untested.** `routes/webhooks.ts:39–48` — covered only by code, not by tests. One smoke test (member sees list, non-member 404) is enough.
3. **`createFromWebhook` could persist avatar.** The `messages.metadata` column is already accepted as a parameter (`null` today). Storing `{ webhook_avatar: displayAvatar }` there and reading it in `toMessage` resolves C2 with no schema migration. Cheap follow-up.
4. **Rate-limit map cleanup (C6 deferred):** the `for (const ... of buckets)` walk on every execute (`routes/webhooks.ts:160–164`) is O(N) per request. With `MAX_BUCKETS = 10_000` and 30 timestamps each, that's 300k array filter ops on every webhook hit under load. Either (a) only sweep when `buckets.size > MAX_BUCKETS / 2`, or (b) sweep on a `setInterval` outside the hot path. Not a blocker, but log a follow-up issue if you want to keep deferring.
5. **`stripToken` uses `Omit<T, "token">` over a destructure with `_`.** Functionally fine; ESLint may flag `_` as unused depending on config — consider `void token;` or a regex pragma if so.
6. **`webhookRoutes` PATCH:** `body.avatar !== null` skip path means PATCH `{ avatar: null }` clears the avatar without validation, but PATCH `{ avatar: "" }` would pass `validateString` (length check only) and store an empty string. If empty string is invalid (it should be — there's no semantic for "blank avatar URL"), tighten the validator to reject empty after `required:false`.
7. **`webhookExecuteRoutes` — content max 4000 vs Discord's 2000.** Intentional? Worth a comment. Plugins relying on Discord parity may overshoot.
8. **DELETE webhook returns 204 even if `repos.webhooks.delete` returns `false`.** The findById check above guarantees the row existed at read time; in single-process SQLite this is fine, but if you ever go multi-process, surface the 0-row case as 404. Tiny.
9. **`webhookExecuteRoutes` accepts `dispatcher?` as optional** (`routes/webhooks.ts:131`). The route only conditionally dispatches, but the rest of the codebase requires a dispatcher. If this is intentional for testability, fine; otherwise the optional-ness leaks the test seam.
10. **Skill file has Windows-style trailing newline issue** — `skills/cove-webhook/SKILL.md` ends without a final newline (`\\ No newline at end of file`). Minor.

---

## 6. Positive Notes

- **Token never leaks on list/get/patch/delete.** `stripToken` + `toPublicWebhook` are applied consistently and verified by tests (`webhooks.test.ts:147–169`). Good defense-in-depth — the public type is enforced at both route and repo layers.
- **Execute endpoint is registered before the global auth middleware** (`app.ts:39–46`), so the no-auth contract is structural rather than a per-route opt-out. Easy to audit, hard to misconfigure.
- **Negative-test coverage is genuinely good** for a Round-3 follow-up: 401 unauth, 404 non-member with the correct error code 10003, 404 cross-guild, 404 wrong token, 400 over-length username/avatar_url. This is exactly the suite Round 3 asked for.
- **Username override persists on reload** via `sender_name` (`webhooks.test.ts:117–135`) — that's the half of C2 that did get fixed, and the test that proves it is the right test.
- **Migration is additive only.** `v8-webhooks.ts` only `CREATE TABLE` + `ADD COLUMN`, no destructive changes; safe for existing deployments.
- **Client UI matches Discord's "show token only at creation" model** (`ChannelSettings.tsx:99–106`). Correct security choice and well-tested by manual flow.
- **`sender = NULL` schema usage** for webhook-authored messages is clean: it means non-webhook code paths that read by `sender` won't accidentally attribute messages to a fake user.

---

**File path:** `~/.openclaw/workspace/code-review/reviews/cove-294-nova.md`
