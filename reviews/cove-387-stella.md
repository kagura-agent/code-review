# Review: PR #387 — feat: cross-channel Reply-To metadata (#386)

## 1. Summary

This PR adds a lightweight cross-channel Reply-To metadata path for webhook-created messages:

- shared `Message` type gains `reply_to`
- webhook execution accepts and stores `reply_to`
- message hydration exposes it back to API/gateway consumers
- plugin dispatch injects `ReplyToChannelId` into agent context
- webhook helper script can send by raw channel/thread id and include a return address

The overall design is small and fits the email-style routing goal. I like that the server stores the routing hint as metadata rather than overloading Discord-style message references.

## 2. Critical Issues

### ⚠️ Missing test coverage for behavior changes

This PR changes externally visible behavior in several places, but the diff does not add or update tests.

Coverage should be added before merge for at least:

- webhook execute accepts `reply_to` and returns it when `?wait=true`
- persisted webhook messages retain `reply_to` when fetched from DB/API
- webhook execution into a thread still preserves `reply_to`
- plugin dispatch maps `message.reply_to.id` to `extraContext.ReplyToChannelId`
- invalid/malformed `reply_to` payloads are either rejected or safely ignored, depending on intended contract

Given the review standard says any behavior change must have test coverage, this is a merge blocker.

### ⚠️ `reply_to` payload is not validated

`content`, `username`, and `avatar_url` are validated, but `reply_to` is accepted and persisted without shape/type validation. Since this value is later exposed on messages and injected into agent context, the route should validate that `reply_to`, if present, is an object with a non-empty string `id` and no unexpected unsafe shape.

Recommended behavior: return `400` for malformed values such as `reply_to: null`, `reply_to: {}`, `reply_to: { id: 123 }`, or an oversized id.

## 3. Product Impact

The feature is useful and directly supports automatic return routing between channels/threads. If merged as-is, happy-path routing may work, but regressions could slip through because the core contract is untested.

The unvalidated payload also creates a reliability risk: malformed Reply-To metadata can be stored permanently and then appear in agent context, which could break downstream automatic reply routing or cause confusing agent instructions.

## 4. Suggestions

1. Add server tests in the existing webhook test suite for `reply_to` round-trip and persistence.
2. Add validation for `reply_to.id` alongside the existing webhook body validation.
3. Add a focused plugin dispatch unit/integration test that confirms `ReplyToChannelId` appears only when `message.reply_to.id` is present.
4. Consider documenting whether `reply_to.id` may be a channel id, thread id, or both. The script supports thread-aware routing, so the accepted semantics should be explicit.
5. If `metadata` may eventually store more fields, consider a small typed parser/helper instead of inline `JSON.parse` in `toMessage()`.

## 5. Positive Notes

- The implementation is compact and keeps the new metadata separate from Discord-native reply references.
- Thread routing in the helper script is a good practical addition for cross-channel workflows.
- Backward compatibility for `--to <name>` is preserved.
- The plugin context name `ReplyToChannelId` is clear and easy for agents/tools to consume.

## Rating

⚠️ Needs Changes
