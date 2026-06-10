# Code Review: PR #294 (Round 2)

## R1 Issue Status
1. **FK violation**: ✅ Fixed (null inserted instead of webhookId).
2. **No rate limiting**: ✅ Fixed (in-memory rate limiting added).
3. **`username`/`avatar_url` unvalidated**: ✅ Fixed (length constraints added).
4. **Token leaked in list/get**: ✅ Fixed (token stripped from public responses).
5. **Message identity lost on reload**: ⚠️ Partially fixed (bot flag and username restored, but avatar is still hardcoded to `null` because it is not saved in the messages table).
6. **No tests**: ✅ Fixed (comprehensive test suite added).
7. **No permission check on webhook creation**: ❌ Not fixed (ESCALATED). `requireGuildMember` only verifies guild membership, allowing any regular user to create, edit, or delete webhooks.

## Summary
The second round introduces a solid test suite, fixes the database constraint crash, and properly redacts tokens from read endpoints. However, the permission model is still completely missing, and a new critical client bug was introduced when trying to construct webhook URLs using the now-redacted tokens.

## Critical Issues (Blocking)
1. **Client URL Generation Broken**: The UI's `webhookUrl(wh)` function attempts to use `wh.token`, but the `GET /channels/:channelId/webhooks` endpoint explicitly (and correctly) strips the token. This results in the UI copying broken URLs ending in `/undefined`. The UI needs to handle the fact that tokens are only available immediately upon creation.
2. **Missing Permissions (Escalated from R1)**: Endpoint handlers (`POST`, `PATCH`, `DELETE`) still only use `requireGuildMember`. Any user in the server can create, list, modify, and delete webhooks for any channel. This requires a proper authorization check (e.g., a `MANAGE_WEBHOOKS` permission or admin role requirement).

## Suggestions
1. **Avatar Persistence**: To fully fix R1 issue #5, consider adding a `sender_avatar` column to the `messages` table or storing it in the `metadata` JSON blob. Currently, custom webhook avatars are lost when clients fetch message history.
2. **Rate Limiter Memory Leak**: The `buckets` Map in `webhookExecuteRoutes` never removes keys once they are added. Over time, this will leak memory for every unique webhook ID. Consider adding a periodic cleanup interval to delete keys that have no recent timestamps.

## Positive Notes
- The new test suite in `webhooks.test.ts` is thorough and accurately catches the token omission and validation requirements.
- The client-side integration in `ChannelSettings.tsx` provides a great user experience with good state management for loading and deleting webhooks.

**Rate:** ❌ Major Issues
