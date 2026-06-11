# 🌠 Nova — Round 5 Re-review: PR #294 (kagura-agent/cove)

**PR:** feat: add webhook support for cross-channel messaging
**Round:** 5 (re-review after C3 fix)
**Verdict:** ✅ **C3 properly resolved.** No new blockers introduced. PR ready to merge subject to the two pre-existing deferred items (C2, C6).

---

## 1. C3 — Deletion identity (focus of this round)

### Was it actually fixed?
**Yes.** The `toMessage` fallback now reads `sender_name`:

```ts
} else {
  author = {
    id: "0",
    username: row.sender_name ?? "Deleted Webhook",
    avatar: null,
    bot: true,
    discriminator: "0",
    global_name: null,
  };
}
```

Flow after webhook deletion:
- Schema: `messages.webhook_id TEXT REFERENCES webhooks(id) ON DELETE SET NULL` → `webhook_id` becomes NULL.
- `createFromWebhook` inserts with `sender = NULL` and `sender_name = webhookName` (the per-execution `username` override).
- After deletion: `row.webhook_id === null` AND `row.sender === null` → falls into the new `else` branch → username comes from `row.sender_name`.

The fallback chain is now end-to-end coherent. The R4 critique ("crash fixed but toMessage fallback didn't read sender_name") no longer applies.

### Regression test
The new test `deleted webhook messages retain sender_name as author` (webhooks.test.ts) does exactly the required scenario:

1. Create webhook (`Temp Hook`)
2. Execute with `username: "Custom Name"` override → 201
3. `DELETE /webhooks/:id` → 204
4. List messages, find the original message id
5. Assert `author.username === "Custom Name"` and `author.bot === true`

✅ Asserts the override survives, not just the registry name — that's the correct invariant.

**One minor gap (not blocking):** the test doesn't assert `author.id === "0"` (the sentinel chosen for the deleted-author placeholder). If we ever change the sentinel — e.g. to `"deleted-webhook"` or to the still-known `webhook_id` from before deletion — clients keying off `author.id` could break silently. Suggest a follow-up assertion:
```ts
expect(found!.author.id).toBe("0");
```
Or, better, document the sentinel in `Message.author.id` JSDoc.

**C3 status: ✅ Resolved.**

---

## 2. Escalation check on previously deferred items

Per escalation rule, anything unaddressed since last round should bump in severity. Nothing new was promised for C2/C6 this round, but they remain open:

### C2 — Avatar persistence (still ⏸️ deferred → now ⚠️ should be tracked)
The execute endpoint accepts `avatar_url` but `createFromWebhook` does not persist a per-execution avatar; `toMessage` returns `avatar: null` for the webhook branch. Functional consequence: the `avatar_url` field of the execute API is silently ignored at render time. Discord-compat table in the PR body claims "Aligned" for `avatar_url` — that's currently misleading.

**Escalated severity:** Medium → **High-Medium**. Either:
- (a) wire the per-execution avatar into a column (`messages.webhook_avatar TEXT`) and surface it in `toMessage`, **or**
- (b) update the PR body / SKILL.md to mark `avatar_url` as "accepted, not yet rendered" so users aren't surprised.

Recommend (b) for this PR + tracking issue for (a). Not a merge blocker but should not ship with a misleading compatibility claim.

### C6 — Rate-limit cleanup (still ⏸️ deferred)
No change. Still no rate limiting on `POST /webhooks/:id/:token` (unauthenticated endpoint). Two rounds in a row with no movement — **escalating from Low → Medium**. Token-based execute endpoints without rate limits are a known abuse vector (forwarded URL → token leak → spam). Suggest at minimum an IP+token bucket (e.g. 30 req / 10 s) before any third party gets a webhook URL.

Not a merge blocker for an internal-only release, but should land before any external doc/announcement of webhooks.

---

## 3. Fresh review of round-5 code

### `repos/messages.ts` — author branching
The three-branch logic (`webhook_id` present / `sender` present / fallback) is correct and exhaustive over the realistic row states. Two small observations:

- **A1 (nit):** When `webhook_id` is set, `author.id = row.webhook_id`. If the webhook is later deleted (SET NULL on `webhook_id`), the historical message's `author.id` changes from `<webhook_id>` to `"0"`. Any client that cached/indexed by `author.id` will see identity drift. This is a deliberate trade-off (FK integrity vs. stable identity) but worth a code comment so future readers don't "fix" it by stashing the id into a separate column.

- **A2 (nit):** `avatar: null` is hard-coded in both webhook branches even though the registered webhook has an `avatar_url` column elsewhere. Once C2 is addressed this'll need an update — leaving a `// TODO(C2): surface webhook avatar` here would help.

### `repos/messages.ts` — `createFromWebhook`
- Insert order matches column list ✅
- `sender = null` is the right choice (preserves "no user authored this" semantics and lets ON DELETE SET NULL semantics work via `webhook_id`).
- `webhookAvatar` parameter is **accepted but unused** in the insert. Dead parameter — either wire it (preferred) or drop it from the signature to avoid a false API contract. Mild **code smell**, recommend cleanup.

### `routes/webhooks.ts`
Not re-diffed in detail this round (R4 covered it). Auth gating on management endpoints still looks correct; execute endpoint remains intentionally unauthenticated.

### Tests
- `webhooks.test.ts` is now 306 lines covering create/list/get/patch/delete + execute + cross-guild negative + new deletion regression. Coverage is solid.
- The "Sneaky Hook" cross-guild test (returns 404, not 403) — fine, 404 is acceptable for not-found-or-not-authorized to avoid leaking existence.

### Migration v8
Idempotent enough for first install; uses `IF NOT EXISTS` on indexes but **not** on the `webhooks` CREATE TABLE or the `ALTER TABLE ADD COLUMN`. That's OK because migrations run once via the migrations table, but if anyone ever reruns v8 manually it'll throw. Pattern matches other migrations in the repo, so consistent — no action.

---

## 4. Anti-confirmation-bias pass

I deliberately tried to break C3 again:
- **Scenario:** webhook created with no `username` override, executes with default name, then deleted → `sender_name` falls back to the webhook's registered `name` (whatever was stored when `createFromWebhook(channelId, webhookId, webhookName, …)` was called). Verified in the route: the execute handler passes the per-execution `username || webhook.name`. So even without an override, `sender_name` is populated and survives deletion. ✅
- **Scenario:** what if `sender_name` is somehow NULL on a webhook row? Fallback string `"Deleted Webhook"` kicks in — safe, no crash. ✅
- **Scenario:** webhook_id NOT NULL but webhook row deleted via direct SQL (bypassing SET NULL)? Can't happen — FK SET NULL fires before the row is gone. Even if it did, the first branch would render `sender_name ?? "Webhook"`. Safe. ✅

No new failure modes found.

---

## 5. Summary table

| ID | Item | R4 | R5 |
|----|------|----|----|
| C1 | Execute auth | ✅ | ✅ |
| C2 | Avatar persistence | ⏸️ | ⚠️ Deferred, **escalating** — fix or correct compat claim |
| C3 | Deletion identity (sender_name fallback + regression test) | ⚠️ Partial | ✅ **Resolved** |
| C4 | Negative tests | ✅ | ✅ |
| C5 | Avatar validation | ✅ | ✅ |
| C6 | Rate-limit on execute | ⏸️ | ⚠️ Deferred, **escalating Low→Medium** |
| A1 | Comment author.id drift trade-off | — | nit |
| A2 | `webhookAvatar` param accepted but unused | — | nit / code smell |

---

## 6. Recommendation

**Approve / merge** once one of the following is done about C2's misleading compat claim:
- Update the Discord-alignment table in the PR body to mark `avatar_url` as "accepted, not rendered (tracked in follow-up)", OR
- Wire the per-execution avatar end-to-end.

Everything else (A1/A2, C6 rate-limit) can ship as follow-up issues. The blocker from R4 (C3) is properly closed with both code and a meaningful regression test.

— 🌠 Nova
