# Review: kagura-agent/cove PR #294 — feat: add webhook support for cross-channel messaging

## Summary

This PR adds the core webhook model, CRUD/execute routes, migration, client settings UI, plugin echo-filter adjustment, and server tests. The overall direction is solid and the execute path is close, but I do **not** think it is ready as-is: the new client UI is currently blocked by the server's bot-only CRUD checks, new access-control paths lack required negative tests, and webhook message identity is not fully preserved after reload/delete.

**Rating: ⚠️ Needs Changes**

## Critical Issues

1. **Client webhook UI cannot work for normal logged-in users**  
   `packages/server/src/routes/webhooks.ts:16-20`, `36-40`, `49-53`, `63-67`, `80-84`, `111-115`; `packages/client/src/lib/api.ts:86-95`; `packages/client/src/components/ChannelSettings.tsx:85-124`, `284-348`  
   The client UI calls the webhook CRUD endpoints using the browser session cookie (`credentials: "include"` in `api.ts`), but every CRUD endpoint immediately rejects `!user.bot` with 403. OAuth/session users are human users (`bot: false`), so the Integrations panel will fail to list/create/delete webhooks for the users who can actually open it. If Cove does not yet have a permissions model, these endpoints should likely be member-gated (or owner/admin-gated if such roles exist), not bot-only; alternatively, the UI should not expose this flow to human sessions.

2. **New access-control paths are missing required negative tests**  
   `packages/server/src/__tests__/webhooks.test.ts:64-190`; `packages/server/src/routes/webhooks.ts:16-127`  
   The new webhook CRUD routes introduce authorization and guild-membership checks, but the tests only cover successful bot-member access plus execute-token failure. There are no tests for unauthenticated requests returning 401, non-bot users returning 403, non-members receiving 404, cross-guild webhook access, or PATCH authorization. Per the review standard, new auth/permission gates need both positive and negative tests before merge.

3. **Webhook avatar identity is lost after persistence/reload**  
   `packages/server/src/repos/messages.ts:48-56`, `142-173`; `packages/server/src/routes/webhooks.ts:185-195`  
   `createFromWebhook` returns/broadcasts the supplied `webhookAvatar`, including `avatar_url` overrides, but the DB only stores `sender_name` and `webhook_id`. When the message is later read through `toMessage`, webhook messages always get `avatar: null`. That means `avatar_url`/webhook avatar support works only for the immediate response/gateway event and silently disappears on history reload. If avatar identity is part of the Discord-compatible contract, store a sender/avatar snapshot in message metadata or a dedicated column and restore it in `toMessage`.

4. **Deleting a webhook mutates historical message identity into an invalid/non-webhook author**  
   `packages/server/src/db/migrations/v8-webhooks.ts:18`; `packages/server/src/repos/messages.ts:21-59`  
   The migration adds `messages.webhook_id ... ON DELETE SET NULL`. Because webhook messages are inserted with `sender = null` (`messages.ts:146-148`), deleting a webhook clears `webhook_id`; later reads fall back to the normal author path with `author.id = row.sender` (null at runtime) and `bot: false`. This changes old webhook messages after deletion and can produce an invalid `Message.author.id`. Consider preserving a webhook/message identity snapshot and avoiding `ON DELETE SET NULL` for the value clients need to render history, or explicitly handle `sender === null` rows even after webhook deletion.

## Product Impact

- The PR advertises a user-facing Channel Settings → Integrations webhook flow, but current server checks make that flow unusable for normal Cove UI users.
- Webhook messages may look correct when first sent but degrade after page reload or webhook deletion, which is especially risky for cross-channel messaging where identity clarity is the whole point.
- Existing plugin echo filtering (`packages/plugin/src/channel.ts:333`) now lets webhook bot-authored messages through, which matches the goal. The correctness of that flow depends on `webhook_id` being preserved consistently in message history/events.

## Suggestions

1. **Validate `avatar` on create/update.**  
   `packages/server/src/routes/webhooks.ts:26-32`, `94-105` accepts `avatar` without a type or length check. A non-string/object value can cause DB binding errors or bad data. Add `validateString(body.avatar, "avatar", { maxLength: ... })` for create and patch, similar to `avatar_url` on execute.

2. **Trim stored webhook names consistently.**  
   `packages/server/src/routes/webhooks.ts:29-32`, `97-104` validates `name.trim()` indirectly but stores the original string. Other routes (for example channel create) trim before storing. Store `body.name.trim()` for create/update to avoid names with accidental leading/trailing whitespace.

3. **Use the configured API base when showing webhook URLs.**  
   `packages/client/src/components/ChannelSettings.tsx:120-124` always builds URLs from `window.location.origin`. In deployments where `VITE_COVE_API_URL` points to a separate API host, the copied webhook URL will be wrong. Consider exposing a helper based on the same API base used by `api.ts`, or return an execute URL from the server.

4. **Consider hashing webhook tokens at rest.**  
   `packages/server/src/repos/webhooks.ts:28-34`, `48-51` stores tokens in plaintext even though list/get already hide them. Since execute only needs token verification, storing a hash would reduce blast radius if the DB leaks. This is not required for Discord parity, but it is worth considering because webhook URLs are bearer credentials.

5. **Test PATCH and rate-limit behavior.**  
   The new tests do not cover PATCH success/validation/token hiding or the execute endpoint's 429 path. These would be useful regression tests for the API surface added here.

## Positive Notes

- The route split between authenticated CRUD and unauthenticated token-based execute is clear, and registering execute before global auth in `app.ts` makes the public boundary explicit.
- Token leakage is avoided on list/get/update responses via `stripToken`/public repo mapping, while create returns the token once for UI copy flow.
- Execute input validation covers content, username length, avatar URL length, invalid JSON, and invalid token cases.
- The plugin echo-filter change is small and targeted: bot messages are still ignored unless they are webhook messages.
- The tests cover the core happy execute path, invalid token, missing content, token hiding on list/get, delete behavior, and persisted webhook author name/id.

## Verification

- Pulled PR metadata and diff with `gh pr view 294 --repo kagura-agent/cove --json title,body,state,additions,deletions,files` and `gh pr diff 294 --repo kagura-agent/cove`.
- Attempted the advertised typecheck in a temporary checkout, but the workspace lacked installed dependencies/TypeScript (`pnpm -r exec tsc --noEmit` failed with `Command "tsc" not found` in `packages/shared`). No full test/typecheck result is available from this environment.
