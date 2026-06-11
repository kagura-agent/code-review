# Consolidated Review: PR #294 — Webhook Support for Cross-Channel Messaging

**Reviewers:** 🌟 Stella (GPT-5.5) ⚠️ | 🌠 Nova (Claude Opus 4.7) ✅ | 💫 Vega (Gemini 3.1 Pro) ❌

---

## Consensus Findings (2+ reviewers agree)

### C1: Bot-only auth on CRUD routes blocks the client UI (Stella, Nova, Vega)
All webhook management routes check `if (!user.bot) return 403`. The new Integrations UI in `ChannelSettings.tsx` calls these endpoints from a human browser session. Unless Cove flags interactive users as `bot=1`, the entire webhook management UI is non-functional for normal users. Either replace with a proper permission check, or document why this is currently intentional.
**Files:** `routes/webhooks.ts:16-20, 36-40, 49-53, 63-67, 80-84, 111-115`

### C2: Webhook avatar identity lost on reload (Stella, Vega)
`createFromWebhook` accepts and broadcasts `webhookAvatar`, but the DB only stores `sender_name` and `webhook_id`. When messages are read back via `toMessage`, webhook messages always get `avatar: null`. The `avatar_url` per-execution override only works for the initial WS broadcast, not for history. Either store avatar in a column/metadata or drop the feature claim.
**Files:** `repos/messages.ts:48-56, 142-173`

### C3: Deleting a webhook corrupts historical message identity (Stella, Vega)
Migration uses `ON DELETE SET NULL` for `messages.webhook_id`. Since webhook messages are inserted with `sender = null`, deleting a webhook produces messages with both `sender` and `webhook_id` as null — `toMessage` falls back to an invalid author with `id: null, bot: false`. Historical messages lose their identity permanently.
**Files:** `v8-webhooks.ts:18`, `repos/messages.ts:21-59`

### C4: Missing negative auth tests (Stella, Vega)
Tests only use an admin bot token. No tests for: unauthenticated → 401, non-bot user → 403, non-member → 404, cross-guild isolation. Per review standard, new auth gates require both positive and negative test cases.
**Files:** `__tests__/webhooks.test.ts`

### C5: Missing `avatar` validation on create/PATCH (Stella, Nova, Vega)
`body.avatar` on create and PATCH endpoints is passed through without type or length checks. Execute validates `avatar_url` (max 2048) but the management routes don't validate `avatar` at all. A non-string value would be silently persisted.
**Files:** `routes/webhooks.ts:25-32, 94-105`

### C6: Rate-limit cleanup runs on every request (Nova, Vega)
The full bucket iteration + stale-entry filter + eviction runs on every execute call, regardless of map size. For high traffic this is O(N) per request. Consider periodic cleanup or probabilistic sweep.
**Files:** `routes/webhooks.ts:147-156`

---

## Unique Findings

### 🌟 Stella only
- **Webhook URL uses `window.location.origin`** — breaks when API is on a separate host via `VITE_COVE_API_URL`. Consider deriving from the configured API base.
- **Trim webhook names** — names are validated but stored with potential leading/trailing whitespace.
- **Consider hashing tokens at rest** — tokens are stored in plaintext; hashing would reduce blast radius on DB leak.

### 🌠 Nova only
- **Echo-loop risk** — if the same bot executes a webhook in a channel it also listens to, the `!message.webhook_id` filter will dispatch the message back to the bot → potential infinite loop. Nothing currently prevents this.
- **Token shown once, no recovery** — UI should warn "Copy now, you won't see this again" and ideally offer a token regeneration endpoint.
- **`MessageRow` interface missing `sender_name`** — compiles only because of runtime SQL spread; should be declared for type safety.
- **`dispatcher?` is optional in `webhookExecuteRoutes`** — if omitted, webhook messages silently never appear to live clients.
- **Missing client/plugin API parity** — `api.ts` lacks `updateWebhook`/`getWebhook`; `rest-client.ts` lacks `delete`/`patch`/`getById`.

### 💫 Vega only
- **CORS on execute endpoint** — if called from browser cross-origin, OPTIONS preflight will fail since only POST is handled.

---

## Overall Verdict: ⚠️ Needs Changes

Two of three reviewers flagged blocking issues (C1-C4). The architecture and Discord alignment are strong, and the echo-filter change is elegant. However, the bot-only auth + webhook deletion identity corruption + missing negative tests should be addressed before merge. The avatar persistence gap (C2) can be deferred as a known limitation if documented, but C1, C3, and C4 should land in this PR.

**Recommended priority:**
1. **C1** — Fix auth or document intent (blocks UI usability)
2. **C3** — Handle null sender + null webhook_id in `toMessage` gracefully
3. **C4** — Add negative auth tests
4. **C5** — Add `avatar` validation
5. C2, C6 — Can be follow-up issues
