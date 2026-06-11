# Stella R4 Review — kagura-agent/cove PR #327

## Summary

This round does address the main R3 lifecycle/truncation fixes: `destroyAll()` clears `pendingMessages`, `Bridge.shutdown()` clears `activeResponses`, and the extracted `truncate()` helper is now applied to initial sends, final-result sends, and edits. I also verified `pnpm -F @cove/claude-bridge check` and `pnpm -F @cove/claude-bridge build` pass locally. However, two advertised behaviors are still broken in the current diff: the required guild scoping does not actually work with Cove's current `MESSAGE_CREATE` payload, and the package `bin` entry points at a generated JS file with no Node shebang. Verdict: ⚠️ Needs Changes, unless the intended MVP deployment is explicitly "single-guild bot + always run with `node dist/index.js`".

## Critical Issues

### 1. `COVE_GUILD_ID` scoping is ineffective with current `MESSAGE_CREATE` payload

- `packages/claude-bridge/src/bridge.ts:100-101`
- `packages/shared/src/types.ts:55-72`
- `packages/server/src/ws/dispatcher.ts:76-80`

The bridge requires `COVE_GUILD_ID` and claims to scope message handling to that guild, but the actual filter is:

- only reject if `(message as any).guild_id` exists and differs
- otherwise accept the message

Cove's shared `Message` type does not include `guild_id`, and the server currently dispatches `MESSAGE_CREATE` with the raw `message` object from the repo. `GatewayDispatcher.messageCreate()` resolves the guild internally for routing, but does not attach it to the dispatched payload. So in the current server/client contract, this bridge will accept every `MESSAGE_CREATE` it receives in every guild/channel visible to the bot.

For a normal chat bot this might be noisy; for this bridge it is a real product/safety bug because every accepted message can spawn local Claude Code with `--dangerously-skip-permissions` and post a response back. If the bot user is ever a member of more than the intended guild, `COVE_GUILD_ID` will not protect the local machine or other channels.

Recommended fixes, either is fine:

1. Add `guild_id` to `MESSAGE_CREATE` dispatch payloads and the shared gateway message type, then make the bridge check strict: if missing or mismatched, ignore.
2. Or have `GatewayClient` parse READY guild/channel data, keep a `channelId -> guildId` map, and filter `MESSAGE_CREATE` by `message.channel_id`.

Avoid leaving this as `(message as any).guild_id`; it bypasses TypeScript exactly where the boundary matters.

### 2. The documented `cove-claude-bridge` bin will not run as a CLI because the built file has no shebang

- `packages/claude-bridge/package.json:6-8`
- `packages/claude-bridge/src/index.ts:1`
- built output verified: `packages/claude-bridge/dist/index.js` starts with an esbuild comment, not `#!/usr/bin/env node`

The package declares:

- `bin.cove-claude-bridge = ./dist/index.js`

and the README documents running `cove-claude-bridge`, but the generated `dist/index.js` has no shebang. On Unix package managers generally symlink bin targets; without a shebang the shell tries to interpret the JS as shell script instead of running Node.

Fix by adding a shebang to the emitted bundle, for example with esbuild `--banner:js='#!/usr/bin/env node'` (and ensure executable mode is preserved), or remove the `bin`/README CLI path and document only `node dist/index.js`. Since the PR includes a `bin` entry, I would fix the shebang before merge.

## Product Impact

- The bridge now has better shutdown cleanup and message truncation than R3; long responses should no longer hit Cove's message length validation on direct result paths.
- If merged as-is, users may believe `COVE_GUILD_ID` isolates the bridge while it does not. That is the biggest user-facing risk.
- The CLI install path is likely frustrating: build succeeds, package metadata looks correct, but the advertised executable fails at runtime.

## Suggestions

1. Add minimal tests for the bridge MVP paths. I would prioritize:
   - `RestClient` does not retry non-idempotent POST/PATCH on 5xx.
   - `Bridge.truncate()` is applied to initial stream sends, final result sends, and edits.
   - `ClaudeProcessManager.destroyAll()` clears queued messages.
   - gateway invalid-session/reconnect timers do not send on stale sockets.
2. `ClaudeProcessManager.drainPending()` still schedules an uncancelled timeout (`claude-process.ts:128-134`). Clearing `pendingMessages` in `destroyAll()` fixes the common kill-active-process path, but a timeout that was already scheduled before shutdown still closes over `nextMsg` and can call `sendMessage()` later. In the current CLI `SIGTERM` handler immediately calls `process.exit(0)`, so this is less urgent, but the manager itself is still not fully shutdown-safe. Track and clear drain timers or add a `destroyed` flag.
3. Queued messages stop showing typing between the first result and the queued process. `startTyping()` runs when the user originally sends the queued message, but `handleClaudeResult()` stops typing before `drainPending()` starts the next Claude process. Non-blocking, but visible in channels with back-to-back prompts.
4. Replace the `(message as any).guild_id` cast with a typed boundary once the payload shape is fixed. This is currently hiding the most important mismatch in the PR.
5. Consider documenting the security model more explicitly: this bridge runs local Claude Code with skipped permissions for any message it accepts. Even for a personal MVP, the README should tell users to use a dedicated bot with access only to intended channels.

## Positive Notes

- R3's truncation concern is materially fixed: `sendMessage()` and `editMessage()` paths now consistently pass through `truncate()`.
- R3's active response cleanup was fixed in `Bridge.shutdown()`.
- `RestClient` correctly avoids retrying POST/PATCH on generic 5xx, preventing duplicate message sends from server errors.
- The gateway client has reasonable timer cleanup around reconnect, resume, invalid-session, and destroy.
- TypeScript check and esbuild build both pass locally for `@cove/claude-bridge`.

## Verdict

⚠️ Needs Changes
