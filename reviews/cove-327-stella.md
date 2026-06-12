# Review: kagura-agent/cove PR #327 — Round 5 (Stella)

## Verdict: ❌ Major Issues

The three specific Round 4 implementation asks were mostly applied mechanically: the `guild_id` check is now default-deny, drain timers are tracked/cleared, and the esbuild banner produces a shebang. However, the new strict `guild_id` check appears incompatible with Cove's current gateway payload shape: `MESSAGE_CREATE` events do not include `guild_id`, so the bridge will now ignore every normal guild message.

I verified with `pnpm --filter @cove/claude-bridge run check` and `pnpm --filter @cove/claude-bridge run build`; both pass, and the built `dist/index.js` starts with `#!/usr/bin/env node`.

## Round 4 follow-up

1. **guild_id fails open** — **security issue fixed, but product is now broken**
   - PR changed the bridge to `if ((message as any).guild_id !== this.guildId) return;` (`packages/claude-bridge/src/bridge.ts:100-101`).
   - That is default-deny, but Cove's shared `Message` type has no `guild_id`, `toMessage()` does not populate one, and `GatewayDispatcher.messageCreate()` broadcasts the raw `message` without adding the resolved guild id (`packages/server/src/ws/dispatcher.ts:76-79`).
   - Result: for normal `MESSAGE_CREATE` dispatches, `message.guild_id` is `undefined`, so the bridge returns before handling the message.

2. **drainPending timeout survives destroyAll()** — **fixed**
   - `ClaudeProcessManager` now tracks `drainTimers`, has a `destroyed` guard, clears timers in `destroyAll()`, and checks `!this.destroyed` before dispatching the queued message (`packages/claude-bridge/src/claude-process.ts:47-48`, `130-140`, `180-184`).

3. **Missing shebang** — **fixed**
   - `package.json` build script adds `--banner:js='#!/usr/bin/env node'` (`packages/claude-bridge/package.json:11`).
   - Verified built output: first line is `#!/usr/bin/env node`.

## Blocking finding

### [High] Bridge ignores all messages because gateway `MESSAGE_CREATE` payloads do not include `guild_id`

The Round 4 default-deny fix depends on a field that Cove does not currently send on message create events.

Evidence:
- Bridge filter: `if ((message as any).guild_id !== this.guildId) return;` in `packages/claude-bridge/src/bridge.ts:100-101`.
- Shared `Message` interface has `id`, `channel_id`, `content`, `author`, etc., but no `guild_id` (`packages/shared/src/types.ts`).
- Server message conversion returns no `guild_id` (`packages/server/src/repos/messages.ts`).
- Dispatcher resolves the guild for routing but broadcasts the original message unchanged: `this.broadcastToGuildWithChannelFilter(guildId, message.channel_id, "MESSAGE_CREATE", message);` (`packages/server/src/ws/dispatcher.ts:76-79`).

Impact: with current server behavior, every incoming guild message has `guild_id === undefined`, so this bridge never calls `handleUserMessage()` and the Claude bridge is non-functional.

Recommended fix options:
1. Add `guild_id` to guild `MESSAGE_CREATE` gateway payloads server-side, matching Discord semantics, and update the shared `Message` type/tests accordingly; or
2. Have the bridge maintain allowed channel IDs from READY/guild channel data or a REST channel lookup, then default-deny by channel membership rather than by a missing message field.

Given this is a daemon whose core behavior is responding to messages, this should block merge.

## Non-blocking notes

- README still documents `--dangerously-skip-permissions` but does not explain the security implications or recommend a dedicated sandbox/workspace. This is important for an MVP bridge that executes local Claude Code from chat input.
- Username is still injected into the prompt without newline/control-character sanitization (`[${username}]: ${content}`). If Cove usernames can contain newlines/brackets, sanitize or escape before prompt construction.
- `sanitizedEnv()` remains very restrictive and may break real Claude Code setups that need `TMPDIR`, proxy env, or provider-specific variables. This may be acceptable for security, but should be documented or made configurable.
- No tests were added. At minimum, add a focused test for guild filtering/message dispatch shape so this exact regression is caught.
