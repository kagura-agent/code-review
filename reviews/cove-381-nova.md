# 🌠 Nova — Review of PR #381

**PR:** feat(server): webhook execute supports `?wait` and `?thread_id` (#293)
**Repo:** kagura-agent/cove
**Scope:** 3 files, +37/-11
**Verdict:** ⚠️ **Needs Changes** (mostly small but two non-trivial concerns)

---

## 1. Summary

This PR aligns `POST /webhooks/:id/:token` with Discord's documented query parameters:

- `?wait=true` switches the response from `204 No Content` (new default) to `200` with the created message body. Previously the route always returned `201` + body.
- `?thread_id=<id>` retargets the message into a thread, with validation that the thread exists, has type `11`, has `parent_id === webhook.channel_id`, and is not archived. Thread message count is incremented when used.
- 4 existing tests are updated to opt into `?wait=true` so they keep receiving a body, and the assertion changes from `201` to `200`.

The behaviour matches Discord's webhook contract more closely, which is the explicit goal.

---

## 2. Critical Issues

### 🔴 2.1 Silent breaking change for existing webhook consumers
The default response code/shape changes for **every** caller that does not pass `?wait=true`:

- Before: `201 Created` with full message body
- After: `204 No Content` with empty body

Any existing client (in‑house bridges, CI scripts, Discord‑bot adapters, integration tests outside this repo, etc.) that was relying on the returned message id or content will now silently get `null`/empty and likely crash on `await res.json()`. The internal test updates demonstrate exactly this — every previously passing call had to add `?wait=true`.

This is the Discord default, so it is defensible, but it deserves:
- A **`BREAKING CHANGE:`** footer in the commit / changelog entry, not just a `feat:` prefix.
- A line in the PR description explicitly calling out the default flip from `201+body` → `204+empty`.

If 100% Discord parity is not yet a goal, an alternative is to keep `201+body` as default and only switch to `204` when `wait=false` is explicitly passed. That would be additive instead of breaking.

### 🟠 2.2 Thread type check is too narrow
```ts
if (!thread || thread.type !== 11 || thread.parent_id !== webhook.channel_id) {
  return c.json({ message: 'Unknown Channel', code: 10003 }, 404);
}
```
Discord defines three thread channel types:
- `10` — `ANNOUNCEMENT_THREAD`
- `11` — `PUBLIC_THREAD`
- `12` — `PRIVATE_THREAD`

Discord's `POST /webhooks/.../?thread_id=` accepts all three. Hard‑coding `=== 11` means a perfectly valid private or announcement thread is reported as `Unknown Channel`, which is both wrong and confusing (it exists; it's just the wrong type per this check).

Suggested fix:
```ts
const THREAD_TYPES = new Set([10, 11, 12]);
if (!thread || !THREAD_TYPES.has(thread.type) || thread.parent_id !== webhook.channel_id) { ... }
```
…or extract a `isThread(channel)` helper if one already exists in the channels module — please grep first; cove may already have it for the threads routes.

### 🟠 2.3 Missing `locked` check
Discord rejects webhook posts to **locked** threads (even when not archived) with `403`. The current code only checks `thread_metadata?.archived`. If the cove threads model has a `locked` flag (it does in the Discord schema), it should be checked here too. Otherwise behaviour diverges from Discord and from the in‑repo expectation that locked threads are read‑only.

---

## 3. Product Impact

- **Discord‑bridge correctness:** Big win. Bridges previously got `201` and had to special‑case; now `?wait=true` opt‑in matches what Discord SDKs already do.
- **Thread routing:** Unlocks webhook → thread posting for the first time. Useful for CI bots, log forwarders, scoped notification channels.
- **Backwards compat:** As noted in 2.1, existing internal consumers must be updated. Worth scanning the rest of the monorepo (web client, docs/examples, any bot SDK) for `webhooks/${id}/${token}` callers that don't pass `?wait=true` and rely on the response body.
- **Validation UX:** Returning `Unknown Channel` for a wrong thread type is technically Discord‑accurate but the narrow type check (2.2) will produce false negatives. End users will see "unknown channel" for a thread that visibly exists, which is hard to debug.

---

## 4. Suggestions

### 4.1 Add tests for the new behaviour
The PR description lists 5 test plan cases, but the diff only updates **existing** tests to use `?wait=true`. No new tests are added for:
- `?wait` absent or `wait=false` → `204` + empty body
- `?thread_id=<valid>` → message lands in thread, thread `message_count` incremented, thread `last_message_id` updated, parent channel `last_message_id` **not** updated
- `?thread_id=<nonexistent>` → 404 `10003`
- `?thread_id=<wrong parent>` → 404 `10003`
- `?thread_id=<archived>` → 403 `50083`
- `?thread_id=<non‑thread channel>` → 404 `10003`
- mention_count increments target the **thread**, not the parent channel

These are the regressions most likely to bite later. Strongly recommend landing them in this PR.

### 4.2 Validation ordering vs. rate limit
Thread validation runs **before** the rate‑limit bucket update, so a flood of requests with invalid `thread_id` values returns `404` without consuming rate‑limit quota. This is a (very minor) probe vector — a caller could enumerate channel IDs without being throttled. Trivial fix: move the rate‑limit bookkeeping above the thread validation, or count failed validations toward the bucket. Not a blocker; flagging for awareness.

### 4.3 `wait` parsing is strict
`c.req.query('wait') === 'true'` accepts only the literal lowercase `true`. Discord behaves the same way, so this is fine — but a one‑line comment ("Discord accepts only the literal string 'true'") would save the next reader a trip to Discord docs.

### 4.4 Style consistency
The new lines use single quotes (`'wait'`, `'Unknown Channel'`, `'true'`) while the surrounding file uses double quotes. Two‑second nit; let the formatter handle it.

### 4.5 Consider extracting the thread‑resolution helper
The check `getById → type ∈ thread types → parent_id matches → not archived → not locked` is the same one the threads routes and the message create route already need (or will need) when handling thread targeting. Extracting `resolveThreadForChannel(repos, threadId, parentChannelId)` returning `Result<Channel, ErrorBody>` would avoid drift between callers.

### 4.6 `repos.threads.incrementMessageCount(targetChannelId)` — confirm semantics
Worth double‑checking that this also bumps `total_message_sent` (Discord exposes both `message_count` and `total_message_sent`) and emits any gateway event the threads list UI listens to. If not, the thread sidebar may not refresh ordering after a webhook post.

---

## 5. Positive Notes

- ✅ Clean, minimal diff that does exactly what the title says.
- ✅ Correctly substitutes `targetChannelId` in **all** three downstream uses: `createFromWebhook`, `updateLastMessageId`, and the per‑mention `incrementMentionCount`. Easy place to forget one — you didn't.
- ✅ Error codes (`10003`, `10015`, `50083`) match Discord, which makes client SDKs that map error codes work out of the box.
- ✅ Existing tests were updated in lockstep instead of being left to fail.
- ✅ Thread post correctly increments the thread's `message_count`, separate from the regular message create path — good attention to thread bookkeeping.
- ✅ `displayName` / `displayAvatar` overrides still flow through correctly post‑refactor.

---

## TL;DR

Solid Discord‑alignment patch. Two real issues to fix before merge: **document the default response breaking change** (2.1) and **broaden the thread type check beyond `=== 11`** (2.2). Add the locked‑thread check (2.3) and please add tests for the new `thread_id` paths (4.1) — the absence of new tests is the biggest gap in an otherwise tidy PR.

— 🌠 Nova
