1. **Summary**: This PR implements Discord-compatible webhooks, including database migrations, CRUD routes, a public execution endpoint, and frontend channel settings UI. While the architecture and Discord compatibility are well-aligned, there are several critical flaws involving persistence, authorization, and data loss that block this PR from being merged.

2. **Critical Issues**:
   - **Broken UI / Bot-only Authorization (`routes/webhooks.ts`)**: Every CRUD endpoint checks `if (!user.bot) { return c.json(..., 403) }`. This explicitly prevents regular human users from managing webhooks, completely breaking the newly added React UI in `ChannelSettings.tsx`. (Also check if `c.get("botUser")` was a typo for `c.get("user")`).
   - **Avatar Persistence Failure (`repos/messages.ts`)**: Webhook avatars and per-execution `avatar_url` overrides are never saved to the database. The `createFromWebhook` function ignores `webhookAvatar`, and `toMessage()` hardcodes `avatar: null`. On page reload, all webhook avatars will disappear. A `sender_avatar` column needs to be added in the migration.
   - **Historical Data Loss on Deletion (`repos/messages.ts` & `v8-webhooks.ts`)**: `webhook_id` is set to `ON DELETE SET NULL`. If a webhook is deleted, `row.webhook_id` becomes null. `toMessage()` will then fall back to normal message mapping, but since `sender` is null, the message's author identity will permanently revert to `"Unknown User"` instead of preserving the original `sender_name`.
   - **Missing Input Validation (`routes/webhooks.ts`)**: The `body.avatar` field in the POST and PATCH webhook CRUD endpoints is entirely unvalidated, violating the review standard.
   - **Missing Negative Tests (`__tests__/webhooks.test.ts`)**: The tests only use `adminToken` (which explicitly sets `bot: 1`). There are zero tests for unauthorized users or regular non-bot users attempting to manage webhooks, which is a mandatory requirement for new auth paths.

3. **Product Impact**:
   - Webhook messages will instantly lose their avatars upon client refresh, rendering the `avatar_url` override feature incomplete.
   - Deleting a webhook will corrupt the visual history of all messages sent by it.
   - The UI currently ships in a broken state since the backend will reject human actions with a 403.

4. **Suggestions**:
   - **Rate Limiter Performance (`routes/webhooks.ts`)**: The rate limiter iterates over all `buckets` keys on every request to clean up stale entries. For a high-traffic instance, this O(N) cleanup could cause event-loop lag. Consider a separate `setInterval` cleanup or a TTL-based store like Redis if scaling up.
   - **Preflight/CORS Checks**: Verify that the execution endpoint (`POST /webhooks/:id/:token`) will correctly handle CORS preflight `OPTIONS` requests since it's mounted before the global auth middleware.

5. **Positive Notes**:
   - The React UI handles the one-time token display elegantly and securely.
   - The execution endpoint mirrors Discord's API well, supporting per-message overrides cleanly.
   - The echo-filter bypass (`!message.webhook_id`) cleanly solves the cross-channel messaging recursion problem.

Rate the PR: ❌ Major Issues