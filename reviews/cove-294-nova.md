# PR #294 Review — feat: add webhook support for cross-channel messaging

**Reviewer:** 🌠 Nova

## Summary
This PR adds a clean, mostly Discord-compatible webhook implementation: schema migration v8, `WebhooksRepo`, CRUD + execute routes, plugin echo-filter update, shared types, client Integrations UI, and a focused test file (213 lines covering create / execute / token-hiding / delete / validation). The execute endpoint is correctly registered before the global auth middleware so token-in-URL works without a session. Architecture is sound and the implementation has internal consistency with the PR description. There are no blocking bugs, but a few security/UX items below should be addressed or consciously deferred before merge.

**Rating: ✅ Ready** (with suggestions worth picking up before broad use)

---

## Critical Issues
None blocking. The pieces I'd normally flag as critical (auth on execute, token leak in list/get, missing tests for negatives) are all already handled — there are explicit tests for "list does NOT include token", "get does NOT include token", "invalid token returns 404", and validation rejections.

---

## Product Impact

1. **Token is shown exactly once, and only in component-local state** — `packages/client/src/components/ChannelSettings.tsx:50,90-93`. The newly-created token lives in a `useState` Map; if the user closes/reopens the settings modal (or refreshes the page) before copying, the webhook URL becomes unrecoverable (`listByChannel`/`findById` strip the token by design). Discord solves this with an explicit "Reveal Token" + "Regenerate Token" action. For Cove, at minimum the UI should make this consequence obvious ("Copy now — you won't see this URL again") and ideally a `POST /webhooks/:id/token` regenerate endpoint should land soon. Right now a user can easily create a useless webhook.

2. **Echo-loop risk for bot-originated webhook calls** — `packages/plugin/src/channel.ts:333`. The new filter is `if (message.author.bot && !message.webhook_id) return;`. That correctly *un-mutes* webhook messages. But if the **same bot** that runs this plugin executes a webhook in a channel it also listens to, the bot will now receive and dispatch its own webhook message → infinite loop. The cross-channel design probably assumes the source bot ≠ the channel's bot, but nothing enforces this. Consider also filtering when `message.webhook_id` is known to belong to a webhook created by this bot (or stamping a metadata field like `application_id`).

3. **`user.bot` gate on all webhook management routes** — `packages/server/src/routes/webhooks.ts:18, 38, 50, 66, 81, 109`. Every management endpoint short-circuits with 403 when `!user.bot`. The new client UI in `ChannelSettings.tsx` calls these from a logged-in human session. This will work only because Cove currently flags interactive users as `bot=1` (the test does the same). If a non-bot user ever opens the Integrations tab they get a silent 403 and `setWebhooks` is called with `[]` via the catch path. Worth a comment explaining the intent, or replacing with a proper permission check once Cove has permissions.

---

## Suggestions

### Security / robustness

- **Validate `avatar` on create and PATCH** — `routes/webhooks.ts:25, 96`. `body.avatar` and `body.avatar_url` on the management side are passed straight through without type/length checks (execute path does validate `avatar_url`, but create/PATCH does not). A client sending `avatar: { evil: true }` would be persisted as `[object Object]` or worse. Add `validateString(body.avatar, "avatar", { maxLength: 2048 })` and the same on PATCH.

- **PATCH avatar nulling is brittle** — `routes/webhooks.ts:101-104`. Sending `{"avatar": null}` correctly clears, but sending `{"avatar": 123}` would silently coerce. Combine with above.

- **Rate-limit map cleanup runs on every request** — `routes/webhooks.ts:147-156`. The "iterate all buckets, filter timestamps, possibly sort and evict half" block runs **every execute**, regardless of map size. With even ~500 active webhooks this is wasted work per request. Either:
  - run cleanup probabilistically (e.g. `if (Math.random() < 0.01)`), or
  - only run the full sweep when `buckets.size > MAX_BUCKETS`, or
  - use a periodic `setInterval`.
  Also `Math.min(...a[1])` will throw "RangeError: Maximum call stack" on very long arrays (not realistic given MAX_REQUESTS=30, but worth knowing).

- **Token in URL → log scrubbing** — Webhook tokens are bearer credentials carried in the path. Make sure access logs / error logs don't write the full path. Not in this PR's diff, but worth confirming before this hits production traffic.

- **No CORS handling on the execute endpoint** — If anyone intends to call this from a browser on a different origin (the natural Discord use case is server-side, so probably not), preflight OPTIONS will not be answered by the POST-only handler. Document the intended caller (server-to-server) or add CORS for that route group.

### Code quality

- **`createFromWebhook` duplicates the message-shape construction** in `repos/messages.ts:142-173`. The same shape is reconstructed in `toMessage` when reading back. Consider building once via a shared helper — when adding embeds/attachments next, two places will need to be kept in sync.

- **`toMessage` references `row.sender_name`** (`repos/messages.ts` toMessage block) but `MessageRow` interface in the diff doesn't declare `sender_name`. Compiles only because `row.sender_name` is read from the spread `m.*` SQL projection at runtime. Add `sender_name: string | null;` to the `MessageRow` interface for honesty.

- **Test comment is stale**: `it("fresh DB gets user_version = 6", ...)` — comment says 6, assertion is 8 (`__tests__/migration.test.ts:14`). Same in other test names that still say "Version should be 3" with assertion 8.

- **`webhookExecuteRoutes` second arg `dispatcher?` is optional**, but if a webhook dispatches a message without notifying gateway clients, the message simply never appears to live clients until refresh. Consider making `dispatcher` required, or asserting in production.

- **Client `api.ts`** is missing `updateWebhook` and `getWebhook` helpers even though the server supports them. Not blocking, but the rest-client (`packages/plugin/src/rest-client.ts`) is also missing `delete/patch/getById/listByGuild`. Inconsistent coverage between client/plugin/server.

### Tests worth adding (non-blocking but cheap)

- Rate-limit hit (31st request → 429 with `Retry-After`).
- Cascade delete: deleting a channel deletes its webhooks (FK `ON DELETE CASCADE`).
- Deleting a webhook sets `messages.webhook_id` to NULL (`ON DELETE SET NULL`) — confirm message fetch still works and falls back to a sane author.
- Non-member of guild calling GET `/webhooks/:id` gets 404 (the code does this, but no test).
- Cross-guild isolation on `listByGuild`.

---

## Positive Notes

- **Auth boundary placement is exactly right.** Registering `webhookExecuteRoutes` before `app.use("/api/*", authMw)` in `app.ts` is the correct Hono pattern for a public token-bearing route, and the route does its own validation. Many implementations get this wrong.
- **Token hygiene in list/get is correct and tested.** `stripToken` + `toPublicWebhook` produce two distinct serializers, and there are explicit assertions that `token` is absent on both endpoints.
- **Per-execution `username` / `avatar_url` overrides** match Discord semantics, with length validation (`80` and `2048`) — that's the right defaults.
- **Schema** uses `ON DELETE CASCADE` for channel/guild references and `ON DELETE SET NULL` for `messages.webhook_id`. Correct choice — historical messages are preserved even if the webhook is revoked.
- **Plugin echo filter change** is a minimal, intent-revealing one-liner; the design (let webhook messages through, since their author identity ≠ the bot user) is elegant and solves the stated problem cleanly.
- **Tests cover both happy and error paths** for execute (success, bad token, missing content, username override, persistence after reload, validation lengths) — better-than-typical coverage for new routes.
- **Discord compatibility table** in the PR description is honest about what's deferred (#293 for `?wait` and `thread_id`).

---

**Verdict: ✅ Ready** — Merge after addressing the Product Impact items if you want a polished first cut, or merge now and follow up. The two things I'd actually push to land before users start creating webhooks: (1) UI warning that the token is shown once, and (2) `avatar` validation on create/PATCH.
