# Review: kagura-agent/cove PR #294 — feat: add webhook support for cross-channel messaging

## Summary

This PR adds the right high-level abstraction for cross-channel messaging, but the current implementation has several merge-blocking issues in the webhook execution path. Most importantly, webhook sends appear to fail at runtime because messages still require `sender` to reference `users(id)` while `createFromWebhook()` inserts the webhook id there. The public no-auth execute endpoint is also mounted before the existing auth/rate-limit middleware, so it has no rate limiting, and several user-controlled fields are unvalidated. Given that this endpoint is intentionally public and token-protected, these need to be fixed and covered by tests before merge.

**Rate: ❌ Major Issues**

## Critical Issues

1. **Webhook execution likely fails due to `messages.sender` foreign key violation**
   - `packages/server/src/repos/messages.ts:138-140`
   - `packages/server/src/db/schema.ts:51`
   - `createFromWebhook()` inserts `sender = webhookId`, but `messages.sender` is declared as `TEXT REFERENCES users(id) ON DELETE SET NULL`. Webhook ids are stored in the new `webhooks` table, not `users`, so with `foreign_keys = ON` this insert should throw instead of creating a message.
   - This blocks the main feature: `POST /api/webhooks/:id/:token` will 500 for normal webhooks unless FK enforcement is disabled elsewhere.
   - Fix options: make webhook-created messages use `sender = NULL` and `webhook_id = webhookId`, or introduce a separate author model/schema that does not overload `sender` as both user id and webhook id. Then update `toMessage()` to derive webhook author fields from `webhooks` / stored webhook metadata.

2. **The public execute endpoint bypasses all existing rate limiting**
   - `packages/server/src/app.ts:39-52`
   - `webhookExecuteRoutes()` is mounted before both global auth and `rateLimitMiddleware()`. Since Hono route handlers that return a response do not call later middleware, successful/failed webhook executions do not pass through the app’s rate limiter.
   - This is high risk because the endpoint is intentionally unauthenticated and token-in-URL is the only secret. A leaked token can be abused to spam channels indefinitely; brute-force/credential-stuffing attempts also have no application-level throttle.
   - Add a dedicated unauthenticated webhook rate limiter keyed by webhook id/token hash and/or IP before the execute route, or mount the route after a rate-limit middleware that can handle anonymous callers. Add tests for 429 behavior.

3. **`username` and `avatar_url` overrides are unvalidated on the no-auth endpoint**
   - `packages/server/src/routes/webhooks.ts:113-128`
   - `content` is validated, but `username` and `avatar_url` are accepted as arbitrary JSON values and then bound into SQLite / returned over the API. Non-string values can trigger server errors; very large strings can bloat DB/API responses; invalid URLs can propagate to clients.
   - For a public endpoint this is a security and robustness issue. Validate `username` as a string with Discord-compatible length (typically 1–80 chars) and validate `avatar_url` as string/null with a sane max length and URL scheme/format. Reject unknown invalid types with 400, not 500.

4. **Webhook messages are not round-tripped correctly from storage**
   - `packages/server/src/repos/messages.ts:17-45`, `packages/server/src/repos/messages.ts:134-165`
   - The immediate response from `createFromWebhook()` has `author.bot = true` and `avatar = webhookAvatar`, but later `list()`/`getById()` reconstruct messages through `MSG_SELECT` joining only `users`. Because webhook ids are not users, `sender_bot` is `null`, so stored webhook messages come back with `author.bot = false`; the avatar is also lost.
   - This will create inconsistent client behavior after reload/history fetch and can break webhook/agent echo-filter assumptions. Store enough webhook author metadata or join `webhooks` when `webhook_id` is present, and ensure list/get responses match create/dispatch responses.

5. **No tests cover the new security-critical webhook behavior**
   - PR adds public unauthenticated execution, token lookup, CRUD access control, migration, and message persistence behavior, but no tests are added.
   - Required coverage before merge: successful execute, invalid token/id, content length validation, username/avatar validation, rate limiting, cross-guild CRUD denial, webhook message listing/getting, and migration from v7 including FK behavior.

## Product Impact

- Cross-channel messaging may not work at all because webhook execution can fail on the message insert FK constraint.
- Even if insertion is adjusted locally, users may see webhook messages change identity after reload/history fetch (`bot: true` becomes `bot: false`, avatar disappears).
- A leaked webhook URL currently has no app-level abuse throttle, which can cause spam, DB growth, websocket fanout, and degraded channel UX.
- Invalid webhook override payloads can turn user errors into 500s, making integrations brittle and harder to debug.

## Suggestions

- Consider not returning webhook `token` from all authenticated list/get responses unless Discord compatibility explicitly requires it for Cove’s clients. If returned, document that these responses expose send capability and should be protected like credentials.
- Add an index on `webhooks(guild_id)` because `listByGuild()` queries by guild id and orders by `created_at`.
- Validate create/patch `avatar` with the same rules as execute `avatar_url`; currently create accepts arbitrary avatar values too.
- Consider wrapping execute message creation + `last_message_id` update in a transaction so channel state cannot diverge if a later write fails.
- Decide whether Cove wants Discord’s `?wait` semantics now or a documented divergence. Always returning the message is fine, but clients may rely on Discord-compatible behavior.

## Positive Notes

- The route split between authenticated CRUD and public execute is clear and easy to audit.
- Token generation with `crypto.randomUUID()` provides meaningful entropy for unguessable URLs.
- CRUD routes consistently hide cross-guild/non-member access behind `Unknown Webhook` / `Unknown Guild` style responses, which avoids obvious resource enumeration through authenticated endpoints.
- Content validation exists on execute and aligns with the existing message length limit.
