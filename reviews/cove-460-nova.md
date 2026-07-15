# 🌠 Nova — Code Review: kagura-agent/cove#460

**PR:** feat(server): implement cross-channel messaging API (#451)
**Author:** kagura-agent
**Files reviewed:** 11 (548 additions, 17 deletions)
**Reviewed:** 2026-07-15

---

## Verdict: ✅ Approve (with Suggestions)

This is a well-structured feature PR. The implementation is clean, consistent with existing patterns (webhook execute route), properly tested, and the migration is safe (transactional, idempotent). No blocking issues found.

---

## Summary

The PR implements a first-class `POST /channels/:channelId/incoming` API that lets bots send messages to any channel they have SEND_MESSAGES permission on, abstracting away webhook management. Internally it uses auto-provisioned type=2 webhooks that are invisible and immutable from the user-facing API.

---

## Findings

### 🔴 Critical

*None.*

### 🟡 Medium

#### 1. Internal webhooks accessible via `GET /webhooks/:webhookId` (Security — Low risk)

**File:** `packages/server/src/routes/webhooks.ts` (unchanged, but relevant)

The `GET /webhooks/:webhookId` endpoint doesn't filter out type=2 webhooks. If a user somehow obtains an internal webhook's ID (e.g., from the `webhook_id` field on messages), they can retrieve its details via this endpoint (minus the token).

**Impact:** Low. The token is stripped, they can't modify/delete it (403), and the IDs aren't enumerable. But per the spec: "Internal webhooks are invisible to all external consumers."

**Suggestion:** Consider returning 404 for type=2 webhooks in `GET /webhooks/:webhookId`, or at minimum don't return the `type` field in the response so clients don't learn about internal webhook existence.

```typescript
// In GET /webhooks/:webhookId handler
if (webhook.type === WebhookType.INTERNAL) {
  return c.json({ message: "Unknown Webhook", code: 10015 }, 404);
}
```

---

#### 2. Internal webhook token exposed via `findInternalByChannel` (Defense-in-depth)

**File:** `packages/server/src/repos/webhooks.ts`

`findInternalByChannel` uses `toWebhook` which includes the `token` field in the returned object. The token is then available in the `incoming.ts` route handler. While the token is never sent to the client (the response is a message object, not a webhook object), the internal webhook's UUID token could theoretically be used against `POST /webhooks/:id/:token` (the execute endpoint) to bypass SEND_MESSAGES permission checks.

**Impact:** Low. The token never leaves the server boundary. But since the webhook execute endpoint doesn't check `type`, this is a defense-in-depth gap.

**Suggestion:** Either:
- Add `if (webhook.type === WebhookType.INTERNAL) return 403` to `webhookExecuteRoutes`, or
- Accept the risk since tokens are UUIDs that never leave the server.

---

### 🟢 Low / Suggestions

#### 3. `embeds` field accepted but silently ignored

**File:** `packages/shared/src/types.ts`, `packages/server/src/routes/incoming.ts`

`IncomingMessageRequest` declares `embeds?: unknown[]` but the route handler never passes embeds to `createFromWebhook`. The spec says "Supports all fields that webhook execute supports: content, username, avatar_url, embeds, thread_id" but embeds are not forwarded.

This is consistent with the existing webhook execute endpoint (which also doesn't pass embeds), so it's not a regression. But the type creates a false expectation.

**Suggestion:** Either:
- Remove `embeds` from `IncomingMessageRequest` until actually implemented, or
- Add a note in the spec that embeds support is deferred.

---

#### 4. Rate limit bucket cleanup runs on every request

**File:** `packages/server/src/routes/incoming.ts` (lines 63–71)

On every request (when rate limiting is enabled), the code iterates all buckets to prune expired entries:

```typescript
for (const [key, ts] of buckets) {
  const active = ts.filter((t) => t > windowStart);
  if (active.length === 0) buckets.delete(key);
  else buckets.set(key, active);
}
```

This is O(n) where n = number of active webhook buckets. With MAX_BUCKETS=10,000, this is a full map scan per request.

**Impact:** Negligible for current scale. This pattern is already used in `webhookExecuteRoutes`, so it's consistent.

**Suggestion:** For future optimization, consider periodic cleanup (e.g., every 100 requests or via `setInterval`) instead of per-request. Not a blocker.

---

#### 5. Spec references "v9" but implementation is v24

**File:** `docs/specs/451-cross-channel-messaging.md` (line under §3.1)

> "### 3.1 DB Migration (v9)"

The actual migration is v24. This is a minor spec-reality mismatch.

**Suggestion:** Update the spec to reference v24, or remove the version number since it'll always drift.

---

#### 6. `content` is required — spec implies optional

**File:** `packages/server/src/routes/incoming.ts`

The route requires `content` (`required: true`), but the spec says:
> "Supports all fields that webhook execute supports: content, username, avatar_url, embeds, thread_id"

And the `IncomingMessageRequest` type has `content: string` (required). This is actually good (messages without content are useless without embeds/attachments), but differs slightly from Discord's webhook execute which allows content-less messages with embeds.

**Impact:** None currently (embeds aren't supported). Correct for current scope.

---

#### 7. No validation on `thread_id` format

**File:** `packages/server/src/routes/incoming.ts`

`body.thread_id` is passed directly to `repos.channels.getById()` without string validation. If it's not a string (e.g., a number in JSON), the DB query may behave unexpectedly.

**Suggestion:** Add `validateString(body.thread_id, "thread_id")` check.

```typescript
if (body.thread_id !== undefined) {
  const threadErr = validateString(body.thread_id, "thread_id", { maxLength: 64 });
  if (threadErr) return validationError(c, threadErr);
}
```

---

#### 8. Migration test assertions hardcode version 24

**File:** `packages/server/src/__tests__/migration.test.ts`

All migration test assertions now check for version 24. This is correct but means every future migration will require updating 8+ assertions. This is existing tech debt, not introduced by this PR.

---

## Architecture & Design

**Strengths:**
- Clean separation: internal mechanism (webhook) hidden behind simple API
- Lazy auto-creation is a smart recovery mechanism for edge cases
- Reuses existing `createFromWebhook` — no message creation duplication
- Migration is idempotent (skips channels that already have type=2 webhook)
- Transaction-wrapped migration with proper foreign key cascades
- Tests cover all critical paths: permission, auto-create, thread routing, webhook protection

**Design consistency:**
- Rate limiting implementation mirrors `webhookExecuteRoutes` ✅
- Thread validation logic mirrors `webhookExecuteRoutes` ✅  
- Error codes follow Discord conventions (50013, 10003, 50083) ✅
- Webhook protection placed before permission check (fail fast) ✅

---

## Test Coverage Assessment

| Scenario | Covered |
|----------|---------|
| Happy path (send message) | ✅ |
| Permission denied (403) | ✅ |
| Auto-create internal webhook | ✅ |
| Internal webhook hidden from list | ✅ |
| Internal webhook delete protection | ✅ |
| Internal webhook patch protection | ✅ |
| Thread routing | ✅ |
| Rate limiting | ❌ (disabled in tests — acceptable) |
| Invalid JSON / missing content | ❌ (minor gap) |
| Channel not found | ❌ (minor gap) |

Overall test coverage is solid for a feature PR.

---

## Final Notes

This is a clean, well-scoped implementation that follows existing patterns closely. The code is readable, the migration is safe, and the test coverage hits the critical paths. The suggestions above are improvements, not blockers. Ship it.
