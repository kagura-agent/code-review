# 🌠 Nova — Review of cove#387

**PR:** feat: cross-channel Reply-To metadata for webhook messages (#386)
**Scope:** 5 files, +68/-12
**Verdict:** **Request changes** — feature is small and clean, but ships with **zero test coverage** for the new behavior and **zero validation** on a user-supplied field that flows into stored metadata, plugin extraContext, and downstream agent routing.

---

## 🟥 Blockers

### B1. No test coverage for any new behavior (violates the brief)
The PR description claims "381 tests passed ✅", but **no new tests were added**. `git diff` shows the test suite untouched. The reviewer brief explicitly says: *Any behavior change must have test coverage.* At minimum, this PR needs:

- **Round-trip test** in `packages/server/src/__tests__/webhooks.test.ts`:
  - POST `/webhooks/:id/:token?wait=true` with `reply_to: { id: "...." }` → response `Message.reply_to.id === "...."`.
  - GET the message back via the messages API → `reply_to` survives.
- **Metadata persistence test** for `MessagesRepo.createFromWebhook(..., replyTo)`: row written, `toMessage` reconstructs `reply_to`.
- **No reply_to → no field**: POST without `reply_to` → response object has no `reply_to` key, and DB metadata column stays `NULL` (regression guard for the previous `null` literal).
- **Malformed metadata tolerated**: pre-seed a row with garbage metadata, confirm `toMessage` doesn't throw (the new `try/catch` exists — prove it).
- **Plugin dispatch**: confirm `ReplyToChannelId` is injected into `extraContext` iff `message.reply_to?.id` is present. Same fixture style as existing dispatch tests, if any.

Without these, future refactors will silently break the cross-channel routing contract.

### B2. `reply_to.id` is unvalidated — trusted into storage, extraContext, and agent routing
`packages/server/src/routes/webhooks.ts:188` types the body as `reply_to?: { id: string }` but never validates it. The value is:

1. JSON-stringified into the `metadata` column (no length cap),
2. Passed through `toMessage` and exposed on the public `Message` API,
3. Injected into the plugin's `extraContext.ReplyToChannelId`, which agents will use to **send replies to that ID**.

That means any holder of a webhook URL (which is sufficient by itself — no auth on execute) can:

- Send `reply_to: { id: "<arbitrary large string>" }` and bloat the metadata column.
- Send `reply_to: { id: 12345 }` (wrong type) and break consumers expecting a string.
- Send `reply_to: { id: "<id of a private channel they shouldn't reach>" }` and trick a downstream agent into routing replies into a channel the original sender has no membership in.
- Send `reply_to: { id: "...", evil: "<huge blob>" }` — the entire object is stringified and round-tripped because the route forwards `body.reply_to` as-is.

**Fix:**

```ts
let replyTo: { id: string } | undefined;
if (body.reply_to !== undefined) {
  if (typeof body.reply_to !== "object" || body.reply_to === null) {
    return validationError(c, "reply_to must be an object");
  }
  const idErr = validateString(body.reply_to.id, "reply_to.id", { required: true, maxLength: 64 });
  if (idErr) return validationError(c, idErr);
  replyTo = { id: body.reply_to.id }; // strip unknown fields
}
// ...pass `replyTo` (not `body.reply_to`) into createFromWebhook
```

Then in `MessagesRepo.createFromWebhook` mirror the narrowing:

```ts
const metadata = replyTo ? JSON.stringify({ reply_to: { id: replyTo.id } }) : null;
// ...
if (replyTo) msg.reply_to = { id: replyTo.id };
```

This is small but it's the difference between "feature" and "trust boundary."

---

## 🟧 Should-fix

### S1. Existence/access check on `reply_to.id` for cross-channel safety
Even with B2 fixed, the server still happily stores any string. For the email-model use case described in the PR, the realistic guarantee callers want is: *the return address points to a channel/thread that exists and is reachable*. Two pragmatic options:

- **Soft:** `repos.channels.getById(body.reply_to.id)` and 400 if not found. Cheap and catches typos.
- **Strict:** verify the resolved channel is in the same guild as `webhook.channel_id`. Prevents using a webhook in guild A to seed replies into guild B.

If the team intentionally wants the field opaque (i.e., not necessarily a Cove channel), say so in the type doc on `Message.reply_to` so reviewers stop asking. Right now `packages/shared/src/types.ts:114` says only *"Reference to a channel for reply context"* — which **does** suggest a Cove channel.

### S2. `metadata` JSON column has no schema/owner
This PR is the first writer of structured JSON into `messages.metadata` for webhook rows (search shows it was always `NULL` before). The current pattern hard-codes the whole document:

```ts
const metadata = replyTo ? JSON.stringify({ reply_to: replyTo }) : null;
```

The next field added by anyone else will either (a) clobber `reply_to` or (b) need to know about all prior fields. Two cheap mitigations:

- Centralize a `serializeMessageMetadata({ replyTo, ... })` / `parseMessageMetadata(row.metadata)` helper next to the row type.
- Add a brief comment on the schema column documenting "JSON, fields: `reply_to?: {id}`" so the convention is discoverable.

Not blocking but very cheap insurance.

### S3. Positional-arg sprawl on `createFromWebhook`
`createFromWebhook(channelId, webhookId, webhookName, webhookAvatar, content, replyTo)` is at 6 positional args. Every future webhook feature (e.g. avatar override audit, embeds, attachments) will keep extending the tail. Prefer:

```ts
createFromWebhook(channelId: string, webhook: { id; name; avatar }, content: string, opts: { replyTo? } = {}) { ... }
```

Not in scope to refactor today, but worth a follow-up issue before the next webhook field lands.

### S4. CLI usage string is misleading
`skills/cove-webhook/scripts/cove-webhook-send.mjs`:

```
Usage: cove-webhook-send.mjs --to <channel> [--to-id <id>] --from <channel> --message <text> [--reply-to <channel-id>]
```

The actual check is `(!values.to && !values["to-id"])` — `--to` is **not** required when `--to-id` is given. Should be `(--to <channel> | --to-id <id>)`. Trivial copy fix.

### S5. CLI: `--avatar_url` dropped, `--from` becomes weak when using `--to-id`
- `executeWebhook` builds `body = { content, username }` — no `avatar_url`. Pre-existing, but worth a note since this script is the canonical reference for agent-to-agent flows.
- The success line `✅ Sent to #${values.to || targetId}` prints a raw snowflake when `--to-id` is used. Cosmetic; consider resolving the channel name from the API result (it's available) for cleaner logs in cron output.

---

## 🟨 Nits / Notes

- **N1.** `dispatch.ts` now emits up to two different "reply" concepts side-by-side in `extraContext`: `ReplyToId`/`ReplyToBody`/`ReplyToSender` (message-level) and `ReplyToChannelId` (cross-channel return address). Agents reading this need to know which is which. Worth a one-line comment near the spread, or rename to `ReturnChannelId` / `ReplyToChannelId` consistently in agent docs to avoid the conflation with `ReplyToId`.
- **N2.** `toMessage`'s metadata `try/catch` silently swallows malformed JSON. Fine, but consider a single-line `log?.warn` so corrupted rows surface in logs instead of being invisible forever.
- **N3.** `resolveTargetRoute` makes an extra `GET /channels/:id` per send. For high-frequency cron paths this adds latency; consider caching in the same `cache` object alongside webhooks (keyed by `targetId`). Non-blocking.
- **N4.** PR description claims `--to <name>` is backward compatible — confirmed by code path; good. But the new `--to-id` path skips the guild-scoped name resolution entirely, which also means it skips any guild-mismatch guardrail `resolveChannelId` may have. Worth a follow-up to ensure `--to-id` can't accidentally target a channel in another guild.
- **N5.** Type doc: `Message.reply_to?: { id: string }` — consider tightening to `{ id: string; guild_id?: string }` if S1 lands, or at least documenting that `id` is a Cove channel/thread snowflake. Right now consumers (plugin, future clients) have to guess.

---

## ✅ What's good

- The wire format (`reply_to: { id }`) mirrors Discord's nested-object conventions, leaves room for `{ id, guild_id, ... }` later, and avoids polluting the top-level `Message` shape.
- Thread auto-detection in the CLI (`resolveTargetRoute`) is the right place for that logic — server stays oblivious, script handles routing.
- `metadata` column reuse beats adding a new column for a single optional field.
- Plugin-side change is one conditional spread — minimum surface area, easy to revert.
- Backward compatibility on the CLI (`--to <name>` still works) is preserved cleanly.

---

## 📋 Minimum bar to merge

1. **B1** — add the round-trip + plugin-injection tests (≤ 60 lines of test code, model after `"execute with ?thread_id routes message to thread"`).
2. **B2** — validate + narrow `reply_to.id` on the server.
3. **S4** — fix the CLI usage string (literally 1 line).

S1, S2, S3, S5 and the nits can land as follow-ups, but I'd flag at least S1 in an issue before this merges so the security posture decision is recorded.
