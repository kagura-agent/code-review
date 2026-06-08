# PR Review: kagura-agent/cove#272 — emoji reactions

Reviewer: Stella
Verdict: **Needs Changes**

## Summary

The server-side access checks, idempotent `INSERT OR IGNORE`, FK cascade model, and batched message-list reaction loading are generally solid. I did not find evidence of cross-guild reaction data leakage in the new REST routes or gateway dispatch path.

However, the default plugin reaction notification mode is effectively unreliable after a restart/reconnect because "own message" tracking is in-memory only and is not rebuilt from Cove state. Since the PR advertises reaction notifications/sync behavior through the plugin-facing changes and defaults to `reactionNotifications: "own"`, this will silently drop real reaction events for existing bot messages in common production cases.

## Blocking findings

### 1. Default `reactionNotifications: "own"` drops reactions for bot messages sent before the current gateway process lifetime

**Location:** `packages/plugin/src/channel.ts:192-205`, `packages/plugin/src/channel.ts:235-239`

`sentMessages` is a fresh in-memory LRU created when the account gateway starts. In the default mode (`reactionNotifications ?? "own"`), a reaction event is ignored unless `sentMessages.has(payload.message_id)` is true:

```ts
const sentMessages = new SentMessageTracker();
const reactionNotifications = ... ?? "own";
...
if (reactionNotifications === "own" && !sentMessages.has(payload.message_id)) return;
```

The set is only populated from `MESSAGE_CREATE` events observed during this runtime:

```ts
if (gatewayClient.botUser && message.author.id === gatewayClient.botUser.id) {
  sentMessages.add(message.id);
  return;
}
```

That means reactions to bot-authored messages that already exist when the plugin starts, reconnects with a fresh process, or misses the original `MESSAGE_CREATE` are silently discarded in the default configuration. This is not just a polish issue: a user reacting to an agent response after a restart will not notify the agent, even though the reaction event arrives and the message author can be verified from REST.

**Suggested fix:** when `reactionNotifications === "own"` and the message id is not in the tracker, fetch the message (or add a small `getMessage(channelId, messageId)` REST client method) and check `message.author.id === gatewayClient.botUser.id`. Cache positive results in `sentMessages`. Alternatively, persist/rebuild the tracker from recent messages per channel on READY/reconnect. Avoid defaulting to `"own"` unless the ownership check is durable.

## Non-blocking observations

- `packages/server/src/routes/reactions.ts:14,35,56` decodes the route parameter directly and accepts any decoded string as an emoji. Consider centralizing validation: reject empty values and set a sane max length. This protects the DB primary key and gateway payloads from arbitrarily large path segments or malformed inputs.
- `packages/server/src/routes/reactions.ts:65-76` does an N+1 user lookup for the reaction-users endpoint. This is probably acceptable for now, but if this endpoint is used for Discord-compatible user lists with larger reactions, a batch user lookup would be better.
- `packages/server/src/__tests__/migration.test.ts:42-56` still verifies the old expected table set and does not assert that `reactions` exists. Please add coverage for the new table, unique constraint/idempotency, and `ON DELETE CASCADE` from messages/users.

## Validation performed

- Pulled the PR diff with `gh pr diff 272 --repo kagura-agent/cove`.
- Read the high-risk server route/repo/migration/dispatcher files and relevant client/plugin files.
- Attempted a workspace build, but this worktree had no completed `node_modules` install; `pnpm -r build` failed before compiling the PR changes because package binaries such as `tsc`/`vite`/`esbuild` were unavailable. A subsequent install attempt was terminated by the environment before completion, so I am not treating build output as evidence for or against this PR.
