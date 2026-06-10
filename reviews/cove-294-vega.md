### Summary
The PR successfully introduces the foundation for Discord-compatible webhooks, properly mapping the execute endpoints and aligning with the goal of cross-channel messaging without echoing. However, there are significant data-layer bugs related to database constraints and missing data persistence that will cause the execution endpoint to crash, as well as logic flaws that fail to retain webhook identities.

### Critical Issues
1. **Foreign Key Violation on Execution**: In `MessagesRepo.createFromWebhook`, the `webhookId` is inserted into the `messages.sender` column. However, `sender` has a foreign key constraint referencing `users(id)`. Since the webhook is not in the `users` table, this will throw an `SQLITE_CONSTRAINT_FOREIGNKEY` error and crash the endpoint. You must insert `null` for `sender` and rely on `sender_name` and `webhook_id`.
2. **Webhook Avatar Data Loss**: The execute endpoint accepts an `avatar_url` override and passes it to `createFromWebhook`. However, this avatar is never saved to the database. When historical messages are fetched via `MessagesRepo.list`, `toMessage()` hardcodes `avatar: null`. The webhook's avatar will vanish upon client refresh.
3. **Missing Rate Limiting / Security**: The `POST /webhooks/:webhookId/:webhookToken` execute endpoint is completely unauthenticated (which is correct by design) but lacks rate limiting. Anyone with a webhook URL can spam the channel indefinitely.

### Product Impact
- **Broken Execute Endpoint**: Webhook execution will fail completely due to the database crash until the foreign key issue is fixed.
- **Incorrect Bot Flag in History**: When retrieving historical messages created by a webhook, `toMessage()` sets `bot: row.sender_bot === 1`. Because the webhook has no user record, `u.bot` will be `null` in the `LEFT JOIN`, making webhook messages incorrectly appear as `bot: false` to clients.
- **Unvalidated Avatars**: Both the webhook creation and execution endpoints do not validate the length or format of the `avatar` payload. This allows users to pass massive strings (e.g., large base64 images) directly into the database, causing storage bloat.

### Suggestions
- **Fix the `bot` flag for history**: In `toMessage()`, explicitly set `bot: true` if `row.webhook_id` is present, bypassing the `row.sender_bot` check.
- **Database Schema for Message Avatars**: Add a `sender_avatar` column to the `messages` table to permanently store the webhook's avatar at the time of execution.
- **Validate Avatar Input**: Add URL format and length validation for `body.avatar` in both webhook creation and execution to prevent abuse.
- **Permission Checking**: Currently, any guild member can create a webhook for any channel. Ensure there is a note to add "Manage Webhooks" permission checks once granular permissions are supported.

### Positive Notes
- The API interface maps perfectly to Discord's webhook structure, which is excellent for existing plugin compatibility.
- Token generation correctly uses `crypto.randomUUID()`, providing strong entropy to prevent brute-forcing.
- Relational integrity is well maintained with proper `ON DELETE CASCADE` cascades in the migration.

Rate: ❌ Major Issues
