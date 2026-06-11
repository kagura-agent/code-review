# Stella Review — kagura-agent/cove PR #327

## Summary

This PR adds a new `@cove/claude-bridge` daemon that connects Cove Gateway events to local Claude Code CLI invocations and posts responses back through Cove REST. The overall shape is promising for a personal self-hosted bridge, but it is not ready as-is: the current implementation ignores the configured guild scope while running Claude with skipped permissions, does not actually implement the documented Claude session continuity, has a race that can drop final responses, and ignores the discovered Gateway URL. Verdict: ⚠️ Needs Changes.

## Critical Issues

1. **Guild scoping is required but never enforced, exposing the local Claude Code bridge outside the intended scope**  
   `BridgeConfig.guildId` is stored in `packages/claude-bridge/src/bridge.ts:24` / `:52`, and `COVE_GUILD_ID` is required in `src/index.ts:17-35`, but `messageCreate` handles every non-bot message it receives (`src/bridge.ts:94-103`) without checking the guild/channel belongs to that guild. Because Claude is launched with `--dangerously-skip-permissions` (`src/claude-process.ts:73-78`), any unintended channel/guild the bot can see becomes a path to execute a local agent with broad file/tool access. Please enforce the configured guild boundary before calling `handleUserMessage` (for example by using event `guild_id` if available, or resolving/caching channel → guild and rejecting non-matching channels). Given the danger flag, I would also strongly consider an explicit channel/user allowlist or mention/prefix gate.

2. **Documented per-channel Claude session persistence is not implemented**  
   The README says each channel gets a deterministic session ID and the CLI is spawned with `--session-id <deterministic-uuid>` (`README.md:62-81`), and `sendMessage` says it uses `--resume` (`src/claude-process.ts:48-51`). The actual spawn creates a fresh `randomUUID()` (`src/claude-process.ts:70`), never passes `--session-id` or `--resume` (`src/claude-process.ts:71-78`), and the `channelSessions` map plus `deterministicUUID()` helper are unused (`src/claude-process.ts:35`, `:174-192`). As a result, every message starts a new Claude session and channel conversation context is lost across turns/restarts. Please either wire the intended session/resume flags correctly or update the product behavior/docs and remove the dead persistence code.

3. **Fast final results can be lost before the initial send resolves**  
   In `handleClaudeText`, the first text chunk starts `rest.sendMessage(...)` and only fills `active.messageId` in the async callback (`src/bridge.ts:156-173`). If Claude emits `result` before that REST request resolves, `handleClaudeResult` hits the `active && !active.messageId` branch, updates `active.content`, then immediately deletes `activeResponses` (`src/bridge.ts:190-215`). When `sendMessage` later resolves, the callback finds no active response and cannot edit to the final result. This can leave users with only a partial first chunk (or stale content). Keep the active record until the initial send resolves, await/chain the final edit, or use a per-channel response state machine so finalization cannot race the first send.

4. **The bridge fetches the canonical Gateway URL but never uses it**  
   `start()` calls `this.rest.getGatewayUrl()` and logs the returned URL (`src/bridge.ts:68-70`), but the `GatewayClient` was already constructed from a derived `${baseUrl}/gateway` URL in the constructor (`src/bridge.ts:56-58`), and `gwUrl` is discarded. If Cove serves a different gateway URL (common behind proxies, path prefixes, or separate WS hosts), startup will still connect to the wrong endpoint. Please construct/connect the `GatewayClient` using the discovered URL when available, or remove the discovery path if derived URLs are the supported contract.

## Product Impact

- Users will expect Cove channels to feel like persistent Claude Code conversations, but current behavior is closer to stateless one-shot prompts. This is especially confusing because the README explicitly promises persistence/resume.
- The permission model is risky: a chat message can drive a local Claude Code process with skipped permissions. In a personal deployment that may be acceptable only if the bridge is tightly scoped to known channels/users.
- Long answers are likely to fail or be silently degraded. `editMessageSafe()` truncates edits (`src/bridge.ts:229-237`), but the initial `sendMessage(channelId, text)` (`src/bridge.ts:164`) and no-streaming final `sendMessage(channelId, resultText || ...)` (`src/bridge.ts:206-208`) send raw content. If the first/final payload exceeds Cove/Discord limits, the API can reject the response instead of delivering the documented truncation.

## Suggestions

- Add tests around the bridge state machine: first-chunk send race, queued messages while a process is active, long output truncation, and gateway URL selection. These are the paths most likely to regress.
- Parse Claude Code `stream-json` output against the real event shape. `handleStreamEvent` currently only reads `event.text` on `assistant` events (`src/claude-process.ts:128-136`), while Claude Code stream output commonly nests assistant message content in structured blocks and emits final text on `result`. If streaming is a feature, add a fixture captured from the real CLI.
- Consider truncating/splitting consistently in `RestClient.sendMessage` or a shared bridge helper, not only in edits. The unused `overflowIds` field suggests splitting was planned but not completed (`src/bridge.ts:36-40`).
- Clear `pendingMessages` in `destroyAll()` so queued prompts cannot outlive shutdown state (`src/claude-process.ts:153-160`).
- Avoid swallowing malformed Claude stdout silently (`src/claude-process.ts:90-97`); at least debug-log the first parse failure so CLI format changes are diagnosable.
- I attempted `pnpm -F @cove/claude-bridge check` after applying the diff locally. It failed because the new package had not been installed/linked in local `node_modules` (`Cannot find module '@cove/shared'`). That may be an artifact of the local checkout rather than the PR, but CI should run after a fresh `pnpm install` to confirm the package builds.

## Positive Notes

- The bridge keeps REST retry behavior conservative for non-idempotent methods, matching the existing plugin client pattern.
- Gateway reconnect/heartbeat handling follows the existing Cove plugin structure, which is a good reuse point.
- The code is small and readable for an MVP daemon; the main fixes are around boundaries, real Claude CLI semantics, and async state correctness rather than broad architecture.

**Rating:** ⚠️ Needs Changes
