# Code Review for PR #316 (Round 3)

## 1. Summary
This is Round 3. While significant progress was made (the `READY` payload is now filtered, channel lifecycle events are filtered, and many REST routes are properly gated with negative tests), the core C2 issue is still not fully resolved. Several critical channel-scoped REST routes were missed again, meaning a bot without `VIEW_CHANNEL` can still read, edit, and delete the channel itself. Additionally, some newly added security gates lack the mandatory negative tests.

## 2. Critical Issues

### ⚠️ ESCALATED: C2 - REST routes missing `VIEW_CHANNEL` gate
You added `requireBotChannelPermission` to messages, reactions, and webhooks, but completely missed the individual channel management endpoints. A bot without `VIEW_CHANNEL` can still fetch, edit, or delete the channel!
- **Missing Check**: `GET /channels/:id`
- **Missing Check**: `PATCH /channels/:id`
- **Missing Check**: `DELETE /channels/:id`
*Fix: Add `requireBotChannelPermission` to these three routes in `packages/server/src/routes/channels.ts`.*

### ❌ Missing Negative Tests for Security Gates
The review standard strictly requires: *"Security/auth paths without tests = Critical. Any new permission check, auth gate, or access control MUST have both positive and negative test cases."* You added tests for messages/reactions, but missed tests for several other newly gated paths:
- **Webhooks**: `POST /channels/:id/webhooks` and `GET /channels/:id/webhooks` now have the auth gate in `webhooks.ts`, but no tests verify that a denied bot gets a 403.
- **REST Channel List**: `GET /guilds/:guildId/channels` filters channels for bots, but there is no test proving a denied bot sees a filtered list.
- **READY Payload**: You correctly implemented filtering for `READY` in `session.ts`, but there is no test verifying that the `channels` array in the `READY` payload actually omits denied channels.
- **Channel Endpoints**: Once you add the missing gates to `GET/PATCH/DELETE /channels/:id`, you MUST add negative tests for them.

## 3. Product Impact
Currently, a bot denied from a private channel can still delete the entire channel via `DELETE /channels/:id`. This is a massive product security risk.

## 4. Suggestions
- The implementation of `broadcastToGuildWithChannelFilter` correctly handles checking if `permissionsRepo` exists, which is good defensive programming.
- Consider adding a helper test utility to assert a 403 response for a given authenticated request, which might make it faster to cover all these negative test cases.

## 5. Positive Notes
- **C4 Fixed**: Channel lifecycle events (`CHANNEL_CREATE`, `CHANNEL_UPDATE`, `CHANNEL_DELETE`) are now properly filtered via `broadcastToGuildWithChannelFilter`.
- **READY Payload Fixed**: `session.ts` correctly filters the channel list in the `READY` dispatch for bot sessions.
- Great job adding the bulk of the missing tests in `permissions.test.ts`. The structure of the negative test suite is clean and explicit.

**Verdict:** ❌ Major Issues