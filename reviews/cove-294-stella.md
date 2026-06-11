# Review: kagura-agent/cove PR #294 — Round 4 re-review

## Summary

This PR adds Cove webhook CRUD/execute support plus a client UI and tests. Round 4 fixed C1 (client-cookie auth works for webhook CRUD) and the route-level C5 validation is now present for `avatar`/`avatar_url`, but C3 is not actually fixed and C4 is only partially covered. Because C3/C4 were called out last round and remain unresolved, this still needs changes before merge.

**Verdict: ⚠️ Needs Changes**

## Critical Issues

### C3 — Deleting a webhook still destroys historical webhook identity

- `packages/server/src/db/migrations/v8-webhooks.ts:18`
- `packages/server/src/repos/messages.ts:23-31`, `packages/server/src/repos/messages.ts:41-49`
- `packages/server/src/routes/webhooks.ts:106-118`

The attempted fix stores `sender_name` for webhook messages, but `messages.webhook_id` is declared `REFERENCES webhooks(id) ON DELETE SET NULL`. When `DELETE /webhooks/:webhookId` runs, SQLite nulls `messages.webhook_id`. After that, `toMessage()` no longer enters the webhook branch and falls through to the generic deleted-sender branch, returning author id `"0"` and username `"Deleted Webhook"` instead of the original webhook identity.

This means historical messages still lose their author identity after webhook deletion. The new persistence test only covers reload before webhook deletion, so it misses the original failure mode.

Suggested fix: snapshot enough webhook author fields directly on the message row and keep using them after deletion. At minimum, if `sender` is null and `sender_name` exists, preserve `sender_name` instead of `"Deleted Webhook"`; ideally also avoid nulling the historical author id, e.g. remove the FK/`ON DELETE SET NULL` from `messages.webhook_id` or add a separate immutable `webhook_author_id` snapshot column.

Add a regression test that creates a webhook message, deletes the webhook, then fetches channel messages and asserts the historical author name/id and `webhook_id` behavior are intentional.

### C4 — Negative auth/authorization tests are still incomplete for the new CRUD surface

- `packages/server/src/routes/webhooks.ts:48-118`
- `packages/server/src/__tests__/webhooks.test.ts:149-190`, `packages/server/src/__tests__/webhooks.test.ts:214-266`

The new tests cover unauthenticated channel-list, non-member channel-list, bad execute token, and cross-guild create. They do not cover negative authorization for several newly introduced protected routes:

- `GET /guilds/:guildId/webhooks`
- `GET /webhooks/:webhookId`
- `PATCH /webhooks/:webhookId`
- `DELETE /webhooks/:webhookId`

The review standard requires both positive and negative tests for new auth gates/access-control paths. This is especially important here because the route-specific checks differ by route: channel routes use `requireGuildMember()`, while webhook-id routes first load the webhook then check guild membership. Add unauthorized/no-session and cross-guild/non-member cases for each protected route, plus positive coverage for PATCH and guild-list.

## Product Impact

- C1 status: addressed. `requireAuth()` accepts session cookies, the client API uses `credentials: "include"`, and webhook CRUD routes use the authenticated user from context instead of requiring bot-only credentials.
- C2 status: still deferred/unresolved. Webhook/avatar identity is still not fully durable across reloads: `createFromWebhook()` receives `webhookAvatar`, but only persists `sender_name`/`webhook_id`; `toMessage()` returns `avatar: null` for webhook rows. Per-execution `avatar_url` and stored webhook avatars are visible in the live response/event, then disappear when fetched from DB.
- C3 status: not fixed, and still user-visible. Deleting a webhook changes historical message authors to `Deleted Webhook`.
- C4 status: partially fixed, but not enough for the new access-control surface.
- C5 status: addressed in route code. `avatar` is validated on create/PATCH and `avatar_url` is validated on execute.
- C6 status: still deferred. The webhook execute cleanup still scans buckets on each execute request (`packages/server/src/routes/webhooks.ts:151-160`), though the cap makes the worst case bounded.

## Suggestions

- Add tests for create/PATCH `avatar` validation specifically. The code now validates these fields, but the current validation tests only cover execute-time `avatar_url`.
- Consider not charging the webhook execute rate-limit bucket before request-body validation (`packages/server/src/routes/webhooks.ts:139-166`). As written, malformed JSON or invalid content consumes quota for a valid webhook token.
- The PR adds a `skills/cove-webhook` proposal under the Cove repo. If this repository is intended to contain app code only, consider moving durable agent-skill artifacts into the proper skill-workshop flow/repo instead of shipping them with the server/client feature.

## Positive Notes

- The execute route is correctly registered before global auth, so token-in-URL webhook execution is not blocked by the browser/client auth path.
- Token leakage is handled well for list/get/update responses via `stripToken()`/public webhook mapping; creation still returns the one-time token as expected.
- The route-level string validation is much improved: webhook names, content, username overrides, and avatar fields now have type/length checks.
- The new tests cover the main happy path, token secrecy on list/get, invalid execute token, missing content, and basic membership isolation.

## Verification

- `pnpm -F @cove/server run build` ✅
- `pnpm -F @cove/client run build` ✅
- `pnpm -F @cove/server test -- webhooks.test.ts` ✅ (Vitest also ran the server suite due project matching behavior; output was truncated by the tool, but the visible summary showed the webhook tests passing.)
