# Review: PR #387 Round 2 — feat: cross-channel Reply-To metadata (#386)

## Summary

The Round 1 fixes are partially addressed: `reply_to.id` now has route-level string/length validation, and the requested server tests for happy-path round-trip, persistence, length overflow, and non-string IDs were added. I also ran the server test suite (`pnpm -F @cove/server test -- webhooks.test.ts`), and it passed: 16 files / 316 tests. However, the validation still persists the entire caller-provided `reply_to` object after checking only `id`, which leaves a malformed/unbounded metadata path in an externally writable webhook endpoint. Rating: ⚠️ Needs Changes.

## Critical Issues

### 1. `reply_to` validation checks `id` but still stores arbitrary extra payload

`packages/server/src/routes/webhooks.ts:194-219` validates that `body.reply_to.id` is a string of at most 64 characters, but then passes `body.reply_to` through unchanged into `MessagesRepo.createFromWebhook`. `packages/server/src/repos/messages.ts:212-244` serializes and returns that whole object.

That means a webhook caller can send a valid `id` plus arbitrary extra fields, including large nested data, and the server will persist and expose it as message metadata. This bypasses the intended compact Reply-To contract and effectively creates an unbounded metadata write path separate from the existing `content` max length.

Suggested fix: after validation, construct a sanitized value and pass only `{ id: body.reply_to.id }` to the repo, or reject `reply_to` objects with keys other than `id`. Add a test that `reply_to: { id: "x", extra: "..." }` is either rejected or round-trips as exactly `{ id: "x" }`.

## Product Impact

The user-facing Reply-To behavior should work for normal webhook sends, and the persistence path is now tested. The remaining issue is mostly reliability/abuse resistance: cross-channel routing metadata should be a tiny trusted routing hint, not an arbitrary object that can be stored and later surfaced to agents/clients.

## Suggestions

1. Add a focused plugin dispatch test for `packages/plugin/src/dispatch.ts:347-349` to verify that `message.reply_to.id` becomes `extraContext.ReplyToChannelId`. This is the part that actually makes the metadata useful to agents, and it is still untested.
2. Consider using `validateString(body.reply_to?.id, "reply_to.id", { required: true, maxLength: 64 })` after confirming `reply_to` is a non-array object. That would align the new validation with existing project helpers and error wording.
3. The error message says “at most 64 characters” but the implementation also rejects an empty string. That is fine behavior, but the message could be clearer if clients rely on it.

## Positive Notes

- The four requested server tests were added and cover the main webhook API contract.
- The happy-path implementation remains compact and backward-compatible.
- Storing Reply-To separately from Discord-native `message_reference` keeps the cross-channel routing semantics clear.

## Rating

⚠️ Needs Changes
