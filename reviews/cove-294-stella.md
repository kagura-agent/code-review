# Stella Review — PR #294 Round 2

## R1 Issue Status

1. **FK violation in `createFromWebhook`** — ✅ Fixed. Webhook messages now insert `sender = null` and store the webhook identity in `messages.webhook_id`, avoiding the `users(id)` FK crash.
2. **No rate limiting on unauthenticated execute endpoint** — ⚠️ Partially fixed. A local fixed-window limiter was added to `POST /webhooks/:id/:token`, but it runs before token validation and is keyed only by `webhookId`, so invalid-token traffic can exhaust a real webhook's quota; random IDs also grow the in-memory bucket map without cleanup.
3. **`username` / `avatar_url` unvalidated on public endpoint** — ⚠️ Partially fixed. Length/type validation exists, but `avatar_url` is not validated as a URL and `username` can be an empty/whitespace override because it is optional and not trimmed/required when present.
4. **Token leaked in list/get API responses to all guild members** — ✅ Fixed. `listByChannel`, `listByGuild`, and authenticated `GET /webhooks/:id` return token-stripped webhook objects.
5. **Message identity lost on reload** — ⚠️ Partially fixed. Reloaded webhook messages now retain `bot: true`, username, `author.id`, and `webhook_id`, but avatar is still lost because only `sender_name` and `webhook_id` are persisted/read; additionally `ON DELETE SET NULL` on `messages.webhook_id` causes old webhook messages to lose webhook/bot identity after the webhook is deleted.
6. **No tests for security-critical code** — ⚠️ Partially fixed. Webhook tests were added for create/execute/list/get/delete and some validation, but they do not cover permission/authorization boundaries, rate-limit behavior, invalid-token quota exhaustion, avatar URL validation, avatar persistence, or identity after webhook deletion.
7. **No permission check on webhook creation beyond guild membership** — ❌ Not fixed. Creation still only checks `requireGuildMember`; patch/delete/list/get are also available to any guild member. Escalated because this was called out in R1 and remains unresolved.

## Summary

Round 2 addresses several core correctness issues from R1: the FK crash is fixed, tokens are no longer returned by list/get APIs, webhook messages mostly preserve identity on reload, and there is now a first pass at tests and client UI. However, the permission model is still too broad for a credential-creating feature, the unauthenticated rate limiter has abuseable edge cases, and webhook message identity is still incomplete around avatars and deletion. I would not merge yet; the remaining issues are concentrated in security/product correctness paths for the new public webhook capability.

## Critical Issues

### 1. Any guild member can create, modify, delete, and enumerate webhooks

**Where:** `packages/server/src/routes/webhooks.ts:16-102`

The webhook management endpoints only check guild membership. This was an R1 finding for creation and remains unresolved, so it should be treated as blocking. A webhook URL is effectively a send credential for the channel; any guild member who can create one can mint an unauthenticated sender into that channel. Any guild member can also patch/delete existing webhooks and list webhook metadata across a channel/guild.

At minimum, gate create/patch/delete/list/get behind an explicit owner/admin/manage-webhooks policy once available, or use the repository's closest existing administrative model. Add tests proving an ordinary guild member cannot create/delete/manage webhooks.

### 2. The unauthenticated execute rate limiter can be abused with invalid tokens and unbounded IDs

**Where:** `packages/server/src/routes/webhooks.ts:111-132`

The execute limiter consumes quota before `findByIdAndToken`. That means an attacker who knows or guesses a webhook ID can send invalid tokens and rate-limit the legitimate webhook without knowing the token. It is also keyed by arbitrary `webhookId` and never cleaned up, so random IDs can grow the `buckets` map indefinitely.

Recommended fix: validate the webhook ID/token before charging the per-webhook bucket, add an IP/global bucket for invalid requests, and add cleanup/TTL for unauthenticated buckets. Add tests for invalid-token requests not exhausting a valid webhook and for 429 behavior on valid executions.

### 3. Webhook identity is still not fully persistent

**Where:** `packages/server/src/repos/messages.ts:48-57`, `packages/server/src/repos/messages.ts:142-173`, `packages/server/src/db/migrations/v8-webhooks.ts:18`

`createFromWebhook` returns the execution avatar, but DB reloads always set `author.avatar: null`; neither the webhook avatar nor per-message `avatar_url` override is persisted. Also, `messages.webhook_id` uses `ON DELETE SET NULL`, so deleting a webhook turns historical messages into non-webhook messages on reload (`bot: false`, `webhook_id` gone, sender null). That reintroduces identity loss in a common lifecycle path.

Recommended fix: persist the display avatar used for the message (or join to webhook avatar where appropriate), and preserve webhook message identity independently of the webhook row deletion. Add tests for avatar persistence and for messages fetched after deleting their webhook.

## Suggestions

- The client UI renders existing webhook URLs as `/api/v10/webhooks/:id/undefined` after refetch because list/get intentionally omit `token`, but `ChannelSettings.webhookUrl()` always uses `wh.token` (`packages/client/src/components/ChannelSettings.tsx:116-118`). Either only show/copy the URL immediately after creation, add a secure token reveal/regenerate flow, or make the UI explicit that the URL cannot be recovered.
- `navigator.clipboard.writeText(...)` is a floating promise in `handleCopyUrl` (`ChannelSettings.tsx:121-124`). Await/catch it so failed clipboard writes do not show “Copied!” incorrectly and satisfy the floating-promises rule.
- Validate `avatar` on create/patch and `avatar_url` on execute as a real allowed URL scheme/format, not only max length.
- Consider trimming names/usernames before persisting/using them. Current validation accepts names with leading/trailing whitespace and optional username overrides that are all whitespace.
- The new tests are useful, but add negative authorization tests and rate-limit tests before relying on this as security coverage.
- I could not run the new webhook test file in the fresh clone without installing dependencies; `pnpm -F @cove/server test -- webhooks.test.ts` failed at import resolution for packages such as `hono` / `@cove/shared`, so this review is based on the diff/source inspection rather than a passing test run.

## Positive Notes

- The FK crash was fixed cleanly by avoiding fake user IDs in `messages.sender`.
- Token stripping for list/get responses is a good improvement and aligns with least exposure.
- The server test coverage is much better than R1 and covers create, execute, invalid token, missing content, list/get token omission, delete, and basic validation.
- Client UI support is a solid start and gives users a straightforward creation/copy/delete workflow.

## Rating

❌ Major Issues
