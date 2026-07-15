# Code Review: cove#460 — Cross-channel Messaging API

**Reviewer:** 💫 Vega  
**PR:** kagura-agent/cove#460  
**Date:** 2026-07-15  

## Summary

This PR implements a cross-channel messaging API (`POST /channels/:channelId/incoming`) backed by internal webhooks (type=2). It includes a DB migration (v24), webhook protection, automatic internal webhook provisioning on channel creation, lazy auto-creation, and a full test suite. The design is well-thought-out: the spec clearly documents trade-offs, and the implementation closely follows it.

## Verdict: ✅ Approve (with Suggestions)

No blocking issues found. The implementation is correct, secure, well-tested, and production-ready. The suggestions below are quality-of-life improvements, not blockers.

---

## Detailed Findings

### 🟢 Correctness

| # | File | Finding | Severity |
|---|------|---------|----------|
| 1 | `routes/incoming.ts` | `embeds` field declared in `IncomingMessageRequest` type but never consumed by the route handler. `createFromWebhook()` doesn't accept embeds either. Not a bug (field is silently ignored), but violates the spec's stated support for embeds. | **Suggestion** |
| 2 | `routes/incoming.ts` | `avatar_url` validation passes strings up to 2048 chars but no URL format validation. Same as existing webhook execute, so consistent. | **Note** |

### 🟢 Security

| # | File | Finding | Severity |
|---|------|---------|----------|
| 3 | `routes/webhooks.ts` | Internal webhook protection check (type=2 → 403) is placed **before** the permission check. This is correct — it prevents information leakage about webhook type to unauthorized users. Good. | **Positive** |
| 4 | `routes/incoming.ts` | Route is behind global `requireAuth` middleware (all `/api/*` routes). Permission check via `requireChannelPermission` + `SEND_MESSAGES` is correct. | **Positive** |
| 5 | `repos/webhooks.ts` | `findInternalByChannel` returns the full webhook including `token`. The token is only used internally and never exposed in the API response. Safe. | **Note** |

### 🟡 Performance

| # | File | Finding | Severity |
|---|------|---------|----------|
| 6 | `routes/incoming.ts` | Rate limit cleanup iterates ALL buckets on every request (`for (const [key, ts] of buckets)`). Under high load with many unique webhooks, this O(n) scan per request could be expensive. The existing `webhookExecuteRoutes` has the same pattern, so this is pre-existing technical debt. | **Suggestion** |
| 7 | `db/migrations/v24-webhook-type.ts` | Migration queries all channels without internal webhooks and inserts one at a time. For large DBs, this could be slow but is a one-shot migration — acceptable. | **Note** |

### 🟢 Readability

| # | File | Finding | Severity |
|---|------|---------|----------|
| 8 | `routes/incoming.ts` | Code closely mirrors `webhookExecuteRoutes` in structure (rate limiting, validation, thread routing). Consider extracting shared logic into a helper in the future to avoid drift. Not blocking for this PR. | **Suggestion** |

### 🟢 Testing

| # | File | Finding | Severity |
|---|------|---------|----------|
| 9 | `incoming.test.ts` | Covers: success path, permission denial, auto-create, list-API hiding, delete/patch protection, thread routing. Good coverage for all acceptance criteria. | **Positive** |
| 10 | `incoming.test.ts` | No rate limit test (rate limit is disabled in tests via `RATE_LIMIT_ENABLED=false`). The rate limit logic is identical to the tested `webhookExecuteRoutes`, so this is acceptable. | **Note** |
| 11 | `incoming.test.ts` | No test for missing/empty `content` (validation path). Minor — the validation function is already well-tested elsewhere. | **Suggestion** |

### 🟢 Input Validation

| # | File | Finding | Severity |
|---|------|---------|----------|
| 12 | `routes/incoming.ts` | `content` is validated as required with 4000 char max. `username` max 80, `avatar_url` max 2048. Matches existing webhook execute validation. | **Positive** |
| 13 | `routes/incoming.ts` | `thread_id` is validated by DB lookup (channel exists, correct type, correct parent). Archived/locked threads are rejected. | **Positive** |

### 🟢 API Design

| # | File | Finding | Severity |
|---|------|---------|----------|
| 14 | `routes/incoming.ts` | Returns 200 (not 201 like channel creation). Consistent with Discord's webhook execute `?wait=true` response. Good. | **Positive** |
| 15 | `shared/types.ts` | `Webhook.type` is `optional` (`type?: number`). This is correct for backward compatibility — existing consumers won't break. The internal type is never exposed in list APIs anyway. | **Positive** |

### 🟡 Config/Schema Consistency

| # | File | Finding | Severity |
|---|------|---------|----------|
| 16 | `db/migrations/v24-webhook-type.ts` | Uses `DEFAULT 1` in the ALTER TABLE, correctly backfilling existing user-created webhooks. Idempotent (checks column existence before ALTER, checks existing internal webhooks before INSERT). | **Positive** |
| 17 | `db/migrations/v24-webhook-type.ts` | Webhook name in migration is `"Internal"` (capitalized) but spec says `"internal"` (lowercase). The `createInternal()` repo method also uses `"Internal"`. Consistent within code, minor spec deviation. | **Suggestion** |
| 18 | `migration.test.ts` | All version assertions updated from 23 → 24. Correct. | **Positive** |

### 🟢 Product Impact

| # | File | Finding | Severity |
|---|------|---------|----------|
| 19 | `routes/channels.ts` | Internal webhook auto-created on channel creation. This means all new channels immediately support cross-channel messaging without migration re-runs. Good forward-thinking. | **Positive** |
| 20 | Overall | The `webhookExecuteRoutes` endpoint still works independently with user-created webhooks. No regression to existing functionality. | **Positive** |

---

## Suggestions (Non-blocking)

1. **Embeds support gap** (#1): Either remove `embeds` from `IncomingMessageRequest` (honest API surface) or add a TODO comment noting it's reserved for future implementation. Currently it's a no-op that could confuse API consumers.

2. **Rate limit cleanup** (#6): Consider a periodic cleanup (e.g., every N requests) instead of per-request full iteration. Low priority since the existing webhook execute has the same pattern.

3. **Shared logic extraction** (#8): The thread validation, rate limiting, and message dispatch logic is nearly identical between `webhookExecuteRoutes` and `incomingRoutes`. A shared helper would reduce drift risk. Fine as follow-up.

4. **Validation edge case test** (#11): Consider adding a quick test for `POST /channels/:id/incoming` with empty body or missing content to verify the 400 response.

5. **Webhook name casing** (#17): Trivial — align migration's `"Internal"` with spec's `"internal"`, or update spec. Doesn't matter functionally since users never see it.

---

## Architecture Assessment

The design choice of internal webhooks as an implementation detail is solid:
- Reuses all existing webhook execute infrastructure (message creation, mentions, threads)
- No new permission types needed
- Clean separation — users see "send to channel", platform handles routing
- Lazy auto-creation provides self-healing for edge cases

The PR is well-scoped, well-tested, and production-ready.
