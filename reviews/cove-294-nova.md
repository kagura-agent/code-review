# 🌠 Nova — Code Review for PR #294 (kagura-agent/cove)

**PR:** feat: add webhook support for cross-channel messaging
**Files reviewed:** 8 (+303 / -3)
**Verdict:** ⚠️ **Needs Changes** — solid scaffolding and Discord-compatible shape, but the unauthenticated execute path + token-handout endpoints combine into a real auth-bypass risk that should be fixed before merge.

---

## 1. Summary

The PR implements a Discord-compatible webhooks subsystem: a new `webhooks` table (migration v8), a `WebhooksRepo`, CRUD routes mounted under the authenticated `/api` prefix, and an unauthenticated execute endpoint (`POST /webhooks/:id/:token`) registered *before* the global auth middleware so the URL token is the only credential. The data model, route shapes, and `webhook_id`-on-`Message` echo-suppression strategy are sound and align well with Discord behavior. The blocking issues are concentrated around the security boundary: (a) the read endpoints leak every webhook's `token` to any guild member, which collapses the URL-token security model; (b) the execute endpoint does no rate limiting and does not validate `username`/`avatar_url` overrides; (c) the create endpoint allows any guild member to mint webhook tokens. Test coverage for new code paths appears absent.

---

## 2. Critical Issues (blocking)

### 🔴 C1. Token exfiltration via list/get endpoints — breaks the entire auth model
`GET /channels/:id/webhooks`, `GET /guilds/:id/webhooks`, and `GET /webhooks/:id` all return the raw `token` field (the repo's `toWebhook` always includes it). The only gate is "is the caller a member of the guild." Combined with the fact that `POST /webhooks/:id/:token` requires only the token, **any guild member can enumerate every webhook in the guild and impersonate any of them at will** — including webhooks created by other members for cross-channel bridging. That defeats the entire premise of the URL-token security model.

Discord deliberately scopes token visibility to users with `MANAGE_WEBHOOKS` and even has a separate `GET /webhooks/{id}/{token}` endpoint that returns the webhook *without* the token to keep tokens out of normal API responses.

**Fix options (any):**
- Strip `token` from the response of list endpoints and `GET /webhooks/:id` unless the caller has an elevated permission (or is the creator).
- Return the token only at create time (and on a separate `regenerate-token` action). Make `toWebhook` omit the token by default and add `toWebhookWithToken` for the create response.

### 🔴 C2. No rate limiting / abuse controls on the execute endpoint
`POST /webhooks/:id/:token` is mounted before `requireAuth` (correctly, per Discord semantics) but has no per-webhook/per-IP rate limit, no concurrency limit, no daily quota, and no body size cap beyond `content` length (and `parseJsonBody` itself — unknown limit). An attacker who obtains (or guesses, see C1) a token can:
- Flood a channel with up to 4000-char messages at line rate.
- Spam every subscribed gateway client via `dispatcher.messageCreate`.
- Bloat the SQLite DB and `messages` table indefinitely.

**Fix:** add at minimum a coarse rate limit (e.g. token-bucket per webhook id, e.g. 30 req / minute matching Discord's 30/min per webhook), and reject `Content-Length` over a sane cap (e.g. 16KB) before JSON parsing.

### 🔴 C3. `username` and `avatar_url` overrides are not validated
```ts
const displayName = body.username ?? webhook.name;
const displayAvatar = body.avatar_url ?? webhook.avatar;
```
- `body.username` is stored directly into `messages.sender_name` with no length cap, no type check, no charset/control-char stripping. The route validates `content` (good) but skips both override fields. A caller can pass a 1 MB string or `null`/object (would crash `INSERT` binding or store garbage).
- `body.avatar_url` is unchecked — no URL parsing, no scheme allowlist (https/data). A malicious caller can store `javascript:` or huge payloads; downstream clients that render it may be impacted.

**Fix:** apply `validateString(body.username, "username", { maxLength: 80 })` (mirroring Discord) when present; same for `avatar_url` with a URL check + length cap. Also reject when `body.username === null` or non-string types.

### 🔴 C4. Webhook creation has no permission check beyond guild membership
`POST /channels/:channelId/webhooks` only calls `requireGuildMember`. Any user who has joined the guild can mint webhooks (which, post-C1 fix or not, become high-value credentials). Discord requires `MANAGE_WEBHOOKS`. If Cove has no permission system yet, at minimum gate webhook creation behind the same flag/role used elsewhere for privileged actions (or document this as a known-deferred gap and track it in #283/#288 so it doesn't ship to multi-tenant guilds).

### 🔴 C5. No tests for any new code path
The diff adds 303 lines of route + repo + migration code touching security-sensitive surface and contains zero accompanying tests. The auth-bypass path (`webhookExecuteRoutes` mounted before global auth) is exactly the class of regression that silently re-breaks in future refactors. At minimum:
- One test that the execute endpoint succeeds with valid id+token, rejects on bad token (404), and is reachable without an auth header.
- One test that a non-member of `guild_id` gets 404 on `GET/PATCH/DELETE /webhooks/:id` (cross-guild isolation).
- One migration test (idempotency / running v7→v8 on a populated DB).

---

## 3. Product Impact

- **Echo-suppression strategy works**: `messages.webhook_id` is set on webhook-created messages and `author.id === webhookId` (not the bot's user id), so plugin echo filters keying off `botUser.id` will not trigger. ✅ This achieves the #288 goal.
- **`bot: true` on webhook author**: matches Discord. Plugins that filter `bot: true` will *also* skip webhook messages — be aware this can block cross-channel bridging if any consumer naively skips bot messages. Worth a docs note (echo-suppression should key on `webhook_id == null && author.id == botUser.id`, not just `bot`).
- **Token leakage (C1) is a user-visible footgun**: in a shared guild, every member sees every cross-channel bridge token. If those bridges connect to private channels in other guilds (the whole point of "Channel as Service"), this is a confidentiality breach.
- **Last-message-id is updated** via `repos.channels.updateLastMessageId`, so unread counts behave correctly. Good.
- **`?wait=true` semantics**: PR always returns the message and 201. Discord without `?wait` returns 204. Some Discord-compatible clients may be surprised, but body says #293 follow-up — acceptable.

---

## 4. Suggestions (non-blocking)

- **S1. Dead parameter:** `webhookRoutes(repos, dispatcher?)` and `webhookExecuteRoutes(repos, dispatcher?)` — the first never uses `dispatcher`. Drop the parameter or, if you anticipate a `WEBHOOKS_UPDATE` gateway event, wire it up now (Discord emits `WEBHOOKS_UPDATE` on create/patch/delete). Either is fine; the current half-state is confusing.
- **S2. Token format:** `crypto.randomUUID()` gives ~122 bits of entropy — *cryptographically* fine, but readers familiar with Discord's ~68-char opaque tokens may mis-identify a UUID-shaped credential as a non-secret id. Consider `crypto.randomBytes(32).toString("base64url")` to make "this is a secret" visually obvious and to avoid log scrubbers that special-case UUIDs as non-sensitive.
- **S3. Token UNIQUE collision handling:** astronomically unlikely with UUIDv4, but the `INSERT` will throw on collision instead of retrying. A `try/retry-once` wrapper is cheap insurance.
- **S4. Migration idempotency:** `ALTER TABLE messages ADD COLUMN webhook_id ...` has no `IF NOT EXISTS` (SQLite doesn't support it). Fine as long as the migration runner tracks `user_version` correctly and never re-runs v8 — which it appears to — but a defensive `PRAGMA table_info(messages)` check would make the migration safe to re-run during dev.
- **S5. Avatar length on create/update:** `body.avatar` is not validated (length, type, scheme). Same exposure as C3 but on the authenticated path, hence "suggestion" rather than blocker.
- **S6. `parseJsonBody` and oversize bodies:** confirm `parseJsonBody` enforces a max body size; if not, add one at the framework layer for the public execute route. Defense in depth for C2.
- **S7. Webhook response shape:** missing `type` (Discord uses `1` = Incoming), `application_id` (null), `user` (creator). If you're advertising "Discord-compatible," adding `type: 1` now avoids breaking clients later.
- **S8. `findByToken` is defined but unused.** Drop it or use it (and add an index if it's intended for hot path; currently it scans because only `id` is PK and `token` has `UNIQUE`, which SQLite auto-indexes — so it's actually fine, just unused).
- **S9. `createFromWebhook` signature is positional and 5-arg.** Easy to swap `webhookName` and `content` by accident at call sites. Consider an options object: `createFromWebhook({ channelId, webhook, content })`.
- **S10. `displayAvatar = body.avatar_url ?? webhook.avatar`** silently coerces `null` to "use webhook avatar." If a caller explicitly passes `avatar_url: null` to *clear* the avatar per-execution, they'll be surprised. Either document or use `in body` check.
- **S11. Error codes:** good use of `code: 10004` / `10015` matching Discord. Consider extracting these as constants instead of inline magic numbers (they're repeated 4× for `10015`).
- **S12. `userId = c.get("botUser").id`** appears in every handler — small helper would DRY this.

---

## 5. Positive Notes

- **Mount order is correct**: `webhookExecuteRoutes` is registered *before* `requireAuth` middleware, with a clear comment. Easy to get wrong; you got it right.
- **`webhook_id` column with `ON DELETE SET NULL`** is the right call — preserves historical messages when the webhook is deleted.
- **FK constraints** on `channel_id` / `guild_id` with `ON DELETE CASCADE` keep the table tidy when channels/guilds disappear.
- **Index on `webhooks(channel_id)`** matches the obvious list query. Good.
- **`toWebhook` / `toMessage` mappers** keep DB rows away from the API surface — consistent with the rest of the codebase pattern.
- **`createFromWebhook` returns a fully-formed `Message`** without a follow-up SELECT — avoids an N+1 on the hot path.
- **`bot: true` on webhook author + `webhook_id` set on message** is exactly the right shape for the echo-filter solution described in #288. Clean design.
- **PR description is excellent** — clear "how it solves X" + Discord alignment table. Easy to review.

---

## Risk Matrix

| Area | Risk | Status |
|---|---|---|
| Auth bypass via token leak (C1) | High | 🔴 Blocker |
| Abuse / DoS on execute (C2) | High | 🔴 Blocker |
| Stored-data integrity from unchecked overrides (C3) | High | 🔴 Blocker |
| Privilege model on create (C4) | Medium-High | 🔴 Blocker (or document) |
| Regression coverage (C5) | High | 🔴 Blocker |
| Migration safety | Low | ✅ |
| Echo-suppression correctness | Low | ✅ |

**Recommendation:** address C1–C3 and add the minimum test set (C5) before merge. C4 is a policy decision; if Cove has no permission model yet, file a follow-up and gate behind a feature flag for multi-tenant guilds. The architecture is right; the security boundary just needs to be tightened.

— 🌠 Nova
