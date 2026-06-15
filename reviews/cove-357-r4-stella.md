# Cove PR #357 — Round 4 Re-review (Stella)

## R3 Issues Status

1. **Guild active-threads endpoint leaks threads** — ✅ Fixed
   - `GET /guilds/:guildId/threads/active` now verifies guild membership and filters bot-visible threads by each thread's `parent_id` permissions (`packages/server/src/routes/threads.ts:121-139`).

2. **PATCH archive/lock has no permission gate** — ✅ Fixed
   - `PATCH /channels/:id` now gates thread `archived`/`locked` updates to the thread owner after normal channel access checks (`packages/server/src/routes/channels.ts:80-124`).

3. **Archived/locked threads accept message writes** — ✅ Fixed for normal message POSTs
   - `POST /channels/:id/messages` now rejects writes into archived or locked thread channels before creating the message (`packages/server/src/routes/messages.ts:64-83`).
   - Caveat captured below: webhook execution can still write to a thread channel.

4. **Bulk delete/clear-all don't update thread message_count** — ✅ Fixed
   - Bulk delete decrements thread `message_count` by the number actually deleted (`packages/server/src/routes/messages.ts:260-273`; repo helper at `packages/server/src/repos/threads.ts:121-125`).
   - Clear-all resets thread `message_count` to zero (`packages/server/src/routes/messages.ts:292-298`; repo helper at `packages/server/src/repos/threads.ts:128-132`).

## New Issues

### ⚠️ Webhook execution can still write into archived/locked thread channels

`webhookExecuteRoutes` creates a message directly in `webhook.channel_id` without loading the target channel or checking thread `archived` / `locked` metadata (`packages/server/src/routes/webhooks.ts:187-204`). Since webhook creation accepts any accessible channel id, including thread channels (`packages/server/src/routes/webhooks.ts:16-38`), a webhook created for a thread can continue posting after the thread is archived or locked.

Impact:
- Bypasses the R4 archive/lock write guard for webhook-token writes.
- Also leaves thread `message_count` stale for webhook-created thread messages, because webhook execution does not call `repos.threads.incrementMessageCount`.

Suggested fix: in webhook execution, fetch the webhook target channel; if it is a thread, reject when archived/locked and increment thread counters on successful webhook messages. Alternatively, forbid webhook creation/execution against thread channels if thread webhooks are out of scope.

## Summary + Verdict

⚠️ **Needs Changes**

The four R3 must-fix items are addressed for the primary thread REST paths, and the targeted thread tests plus full workspace build pass:

- `pnpm -F @cove/server exec vitest run src/__tests__/threads.test.ts --reporter=dot` ✅ 29 passed
- `pnpm -r build` ✅ passed

I found one remaining functional/security gap around webhook writes into archived/locked thread channels. It is narrow, but it bypasses the same thread-write invariant R4 is trying to enforce, so I would fix it before merge.
