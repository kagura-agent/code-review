# 🌠 Nova — Round 2 Review: cove#294 (Webhooks)

**Rating:** ⚠️ Needs Changes

Big improvements over R1 — the critical FK crash and message-identity regressions are gone, a real test file exists, and tokens are stripped from list/get. But two R1 items aren’t actually fixed, the new rate limiter is the wrong shape (memory leak + DoS amplifier + tests think it’s disabled when it isn’t), and the client UI surfaces a broken webhook URL after any reload. None of these are blocking-by-themselves catastrophic, but together they should not ship.

---

## R1 Issue Status

| # | R1 Issue | Status | Notes |
|---|----------|--------|-------|
| 1 | FK violation in `createFromWebhook` (sender=webhookId) | ✅ Fixed | New insert passes `sender=null`, `webhook_id=webhookId`. Verified in `messages.ts:147`. |
| 2 | No rate limit on unauthenticated execute | ⚠️ Partially fixed | A limiter exists, but it’s per-webhookId in-memory, leaks entries forever, and is populated *before* the webhook is validated → trivial unauthenticated DoS by spraying random IDs. See C1 below. |
| 3 | `username` / `avatar_url` unvalidated | ⚠️ Partially fixed | `maxLength` checked, but `avatar_url` is not validated as a URL — `javascript:` / data: / ftp: URIs accepted and round-tripped into clients. |
| 4 | Token leaked in list/get responses | ✅ Fixed | `listByChannel` and `listByGuild` use `toPublicWebhook`, `GET /webhooks/:id` and `PATCH` call `stripToken`. Token only returned on POST create — Discord-compatible. |
| 5 | Message identity lost on reload | ⚠️ Partially fixed | `toMessage` now restores `bot:true`, `author.id=webhook_id`, and the original webhook name. **But `avatar` is hardcoded `null`** — per-execute `avatar_url` overrides vanish, and the webhook’s own avatar is never looked up. Also, when a webhook is deleted (FK `SET NULL`), `webhook_id` becomes null and the branch is skipped → all historical messages from that webhook lose their identity entirely. No test for either. |
| 6 | No tests for security-critical code | ✅ Fixed | `webhooks.test.ts` covers create/exec/list/get/delete/validation + identity-on-reload. Good baseline. |
| 7 | No permission check beyond guild membership | ❌ Not fixed — **escalate** | All five management routes (`POST/GET/PATCH/DELETE channels/:id/webhooks`, `GET guilds/:id/webhooks`, `GET/PATCH/DELETE /webhooks/:id`) gate only on `members.exists(...)`. *Any* guild member can create webhooks, see their tokens (at creation), modify them, and delete anyone else’s. This was Nova-unique in R1; it’s still here in R2. |

---

## Critical Issues (blocking)

### C1. Rate limiter is a DoS vector and a memory leak
`packages/server/src/routes/webhooks.ts` execute route:

```ts
const timestamps = buckets.get(webhookId) ?? [];
...
recent.push(now);
buckets.set(webhookId, recent);          // ← populated BEFORE auth

const webhook = repos.webhooks.findByIdAndToken(webhookId, webhookToken);
if (!webhook) return c.json(..., 404);
```

Two problems:

1. **Unbounded growth / unauthenticated DoS.** The bucket is keyed on the raw `:webhookId` path parameter and inserted *before* token validation. An anonymous attacker can `POST /api/v10/webhooks/<random-snowflake>/x` in a loop and grow `buckets` without bound. There’s no eviction (`buckets` is a module-scoped `Map`). After ~10⁶ requests the process is OOM.
2. **Wrong key.** Rate-limiting per webhook ID means a single attacker with a leaked URL is throttled to 30/min, but a guild full of guests sharing 100 webhook URLs can hammer the server 3000/min. There’s also no per-IP bound. Per Discord, the practical key is `(webhook_id, source_ip)` or at least a global IP bucket.

Fix: validate the webhook (and parse body) first, only record timestamps after that; add a periodic prune of empty/old buckets; consider a per-IP fallback bucket for unknown IDs.

### C2. `process.env.RATE_LIMIT_ENABLED = "false"` doesn’t do anything
`webhooks.test.ts:beforeEach` sets this env var, but `webhookExecuteRoutes` ignores it. So:
- The "rate limit disabled" intent in the tests is silently false.
- Tests pass today only because they make ≤30 calls per `beforeEach`, but the limiter shares a *module-scoped* `buckets` Map across the suite. Add a test or two and CI starts going red intermittently with 429s. Either honour the env var, or reset the limiter via a `__resetForTests` hook, or move the limiter into a per-app construct.

### C3. Permission model — anyone in the guild can manage / read tokens of any webhook
R1 #7 unchanged. Concretely:
- Guest user `eve` joins a guild → `POST /channels/X/webhooks` succeeds and `eve` receives a fresh token (full URL → write access to channel X).
- `eve` can `DELETE /webhooks/<anyone’s id>`.
- `eve` can `PATCH /webhooks/<anyone’s id>` to rename them to `"#general — official"` for impersonation, since the displayed identity is whatever name the webhook has.

Add a `MANAGE_WEBHOOKS` capability (or, at minimum, restrict management to the guild owner or the webhook’s creator). At minimum store `creator_id` on `webhooks` and gate PATCH/DELETE on it; gate POST on a role check. This is what R1 called for.

### C4. Client always shows a broken URL after reload
`ChannelSettings.tsx` renders `webhookUrl(wh)` for every webhook in the list, and `fetchWebhooks` returns `Webhook[]` *without* `token` (correctly, per the server change). So on every reload:

```
https://cove.example.com/api/v10/webhooks/<id>/undefined
```

is rendered in the DOM and pushed to clipboard on “Copy URL”. The token-only-shown-at-creation behaviour is fine, but the UI must reflect it — e.g. only render the URL when `wh.token` is present, otherwise show "Token hidden — recreate to get a new URL" and disable the Copy button. As written, this is a user-facing regression vs. doing nothing.

### C5. `avatar_url` accepts arbitrary scheme
`validateString(body.avatar_url, ..., { maxLength: 2048 })` only bounds length. A webhook caller can push `avatar_url: "javascript:alert(1)"` or `data:text/html,...`, the value reaches `Message.author.avatar`, and any client that renders it as `<img src={author.avatar}>` (current client doesn’t, but the message is also re-emitted over gateway to bots / future clients) inherits the issue. Validate it as `http(s)://` only, or reject and store nothing on reload anyway (since `toMessage` always returns `avatar:null` — see Suggestion S2, this is also a real-vs-claimed mismatch).

---

## Suggestions (non-blocking)

- **S1. `messages.webhook_id` deletion semantics.** `ON DELETE SET NULL` means deleting a webhook nukes the historical identity of every message it sent (they’ll re-render as a sender-less message). Either keep `webhook_id` (`ON DELETE NO ACTION`) and disallow hard-delete with messages still present, or snapshot `(webhook_name, webhook_avatar)` onto the message row at insert time. The current code already stores `sender_name` — good — but `toMessage`’s webhook branch only fires while `webhook_id` is still non-null.
- **S2. Per-execute avatar override is not persisted.** `executeWebhook` accepts `avatar_url` and uses it in the *returned* `Message`, but it’s never written to the DB. On reload, `avatar` is `null`. Either drop the parameter, or add `messages.author_avatar TEXT` and round-trip it. (Same problem applies to `username` override — only persisted via `sender_name`, which is what gets shown — that part is OK.)
- **S3. Webhook tokens are stored plaintext.** Discord stores a hash. If the DB is ever exfiltrated, every webhook becomes a write-anywhere primitive against your channels. Consider `token_hash` with bcrypt/argon2; the lookup path is `findByIdAndToken`, which already has the id, so hashing is straightforward.
- **S4. `TestDispatcher extends GatewayDispatcher` with `as any` cast.** Acceptable but suggests the real type is wrong. Consider making `GatewayDispatcher` constructor accept a minimal interface.
- **S5. `rest-client.ts` `executeWebhook` ignores the response shape.** Returns `Message` but the server actually returns `Message` with `webhook_id` set — already typed correctly via shared types, good. Consider an explicit `wait=true` query (Discord parity) for callers that want fire-and-forget later.
- **S6. UI input states.** `webhookName` is not reset when the modal/section closes. Stale name persists across channels in the same session. Minor.
- **S7. `recent[0]` access in rate-limiter** is technically safe because `length >= MAX_REQUESTS` guards it, but `recent[0]!` or `recent.at(0)` with explicit guard reads better and would have been caught by `noUncheckedIndexedAccess` if enabled.
- **S8. Tests don’t cover the permission boundary** (non-member trying to manage a webhook). Even without fixing C3, add the test so the gap is visible in CI.
- **S9. Tests don’t cover rate-limit behavior** — important given C1/C2.

---

## Positive Notes

- The R1 critical `messages.sender` FK crash is genuinely gone, and the new `createFromWebhook` path is clean.
- Token-strip pattern (`toPublicWebhook` + `stripToken`) is the right shape — server-side enforcement, not just client trust.
- Migration v8 is well-formed: indices on `channel_id` and `guild_id`, FK cascades wired correctly, additive `ALTER TABLE` only.
- Identity-on-reload test (`webhook message retains identity when fetched from DB`) is exactly the kind of regression test R1 asked for.
- Username override coverage (`Custom Bot`), validation length tests, and 404-on-bad-token test demonstrate real R1 follow-through.
- Client UI integration is tidy and uses existing primitives (`Modal`, `Input`, `Button`) consistently with the rest of `ChannelSettings`.
- Discord-compatible URL shape (`/api/v10/webhooks/:id/:token`) makes the contract immediately legible to people coming from Discord webhooks.

---

**Recommendation:** address **C1, C3, C4** before merge; C2 + C5 should land in the same PR since they’re a few lines each. Suggestions can be follow-ups.
