# Review: kagura-agent/cove PR #294 — Round 5 (Stella)

## Summary

PR #294 adds Discord-compatible webhook support across server, shared types, client settings UI, plugin REST client, and helper skill/script. Round 5 specifically fixes the remaining C3 deletion-identity gap: `toMessage` now reads `sender_name` on the deleted-webhook fallback path, and the new regression test exercises create → execute with username override → delete webhook → fetch historical message. I re-reviewed the current diff fresh and found no new blocking correctness/security issues. Verdict: ✅ Ready.

## Critical Issues

None.

### Previous Round Follow-up

- C1 (auth): ✅ Resolved.
- C2 (avatar persistence): ⏸️ Deferred as previously agreed.
- C3 (deletion identity): ✅ Resolved.
  - `packages/server/src/repos/messages.ts:41-49` now handles rows with no `webhook_id` and no `sender` by using `row.sender_name ?? "Deleted Webhook"`, so messages whose `webhook_id` was nulled by `ON DELETE SET NULL` no longer lose the stored display name.
  - `packages/server/src/__tests__/webhooks.test.ts:268-305` creates a webhook, executes it with `username: "Custom Name"`, deletes the webhook, fetches channel messages, and asserts the historical message author username remains `"Custom Name"` and `bot === true`.
- C4 (negative tests): ✅ Resolved.
- C5 (avatar validation): ✅ Resolved.
- C6 (rate-limit cleanup): ⏸️ Deferred as previously agreed.

## Product Impact

Webhook deletion now preserves the historical display name for deleted webhook messages, which is the important user-facing behavior for readable history. One non-blocking caveat: after deletion, `messages.webhook_id` is intentionally nulled by the FK, so historical messages no longer expose `webhook_id` in API responses. That matches the current schema choice and was not the open C3 gap, but if downstream clients later need to distinguish deleted webhooks from deleted users, the schema would need a persistent sender-kind/snapshot field.

## Suggestions

- Consider a future follow-up for deleted non-webhook senders: `packages/server/src/repos/messages.ts:41-49` treats any row with both `sender` and `webhook_id` null as a bot/deleted-webhook-style author. Because normal user messages also use `sender_name` as a snapshot, a deleted human/user message would currently come back with `bot: true`. This is not new-blocking for the webhook PR, but a future `sender_kind` or `sender_bot` snapshot would make historical identity more precise.

## Positive Notes

- The C3 fix is targeted and covered by a regression test on the actual API path rather than only the repo layer.
- The test suite passes locally: `pnpm -F @cove/server test -- webhooks.test.ts` completed with 10 test files / 195 tests passing.
- The execute endpoint continues to validate content, username, and avatar URL lengths before message creation, and token-bearing webhook execution remains isolated from the authenticated route group.

## Verdict

✅ Ready
