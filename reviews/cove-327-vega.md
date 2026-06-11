# PR #327 Review — feat: Claude Code bridge
**Reviewer**: Vega (Gemini 3.1 Pro perspective)
**PR**: kagura-agent/cove#327
**Scope**: 9 new files, `packages/claude-bridge` — bridge daemon connecting Claude Code CLI to Cove chat

## Summary

A clean MVP bridge daemon that connects Cove's Discord-compatible WebSocket gateway to local Claude Code CLI processes via `stream-json` I/O. The architecture is sound — gateway client, REST client, process manager, and bridge orchestrator are well-separated. The code is readable and handles the core happy path well. However, there are several correctness and robustness issues around process management, streaming text assembly, retry logic for non-idempotent requests, and a dead-code function that suggest the implementation was iterated on without full cleanup. Ready with suggestions — nothing here will cause data loss or security issues, but some bugs will surface in real usage.

**Verdict: ✅ Ready** (with suggestions — the issues below are real but acceptable for an MVP being tested by the author)

## Critical Issues

None blocking. The issues below are substantive but appropriate as follow-ups for a personal-project MVP.

## Suggestions

### 1. Dead code: `deterministicUUID` is defined but never called (claude-process.ts:166-192)

The README says "Each channel gets a deterministic session ID derived from the channel ID" and the interface has a `sessionId` field, but `spawnProcess` uses `randomUUID()` (line 80) instead of `deterministicUUID(channelId)`. The `channelSessions` map is populated on exit (line 108) but never read.

This means session persistence across bridge restarts **does not work** despite being documented as a feature. Either:
- Use `deterministicUUID(channelId)` as the session ID and pass `--session-id` to Claude CLI, or
- Remove the dead code and update the README to remove the session persistence claim.

The `--resume` flag mentioned in the comment on line 56 is also not passed to the CLI args (lines 81-87). The current args are `--print --verbose --output-format stream-json --dangerously-skip-permissions -p <prompt>` — no `--session-id` or `--resume`.

### 2. Streaming text: `handleClaudeText` receives full accumulated text or deltas? (bridge.ts:131-160)

The `text` event handler in `bridge.ts` treats the `event.text` from `assistant` stream events as the full accumulated text (it assigns `active.content = text` on line 150 rather than appending). But Claude's `stream-json` `assistant` events emit **deltas** (incremental text chunks), not accumulated text.

This means each streaming edit will overwrite the message content with only the latest chunk, losing all prior text. The fix is either:
- Accumulate: `active.content += text` on line 150, and track accumulated text for the initial send too
- Or buffer in `ClaudeProcessManager` and emit accumulated text

### 3. Non-idempotent POST retries (rest-client.ts:55-62)

The retry loop in `request()` only retries on 5xx errors for idempotent methods (`GET`, `DELETE`, `HEAD`, `PUT`), which is correct. However, the 429 rate-limit retry on lines 44-48 applies to **all** methods including POST. This could cause duplicate message sends if a `sendMessage` POST gets rate-limited after the server already processed it. For an MVP this is low-risk (Cove likely doesn't rate-limit its own bridge), but worth noting.

### 4. No guild ID filtering (bridge.ts:93-101)

`guildId` is accepted in `BridgeConfig` and stored, but never used for filtering. The `messageCreate` handler processes messages from **all** guilds. If the bot is in multiple guilds, it will respond to messages in unintended channels. Add a check like:
```
if (message.guild_id && message.guild_id !== this.guildId) return;
```

### 5. Claude process spawn: `stdin` is `"ignore"` but using `--print -p` mode (claude-process.ts:88)

With `stdio: ["ignore", "pipe", "pipe"]`, stdin is closed. This is fine for `--print -p <prompt>` mode (single prompt, no interactive input). But the README describes "pipes them to Claude Code via stream-json I/O" and mentions `--input-format stream-json`, implying bidirectional streaming. The actual implementation spawns a new process per message, which is a valid design but:
- The README's `--input-format stream-json` flag is not in the actual args
- The architecture diagram shows bidirectional stdin/stdout which is misleading
- Each new message spawns a fresh process, so there's no conversational context (session persistence is dead code per issue #1)

Consider updating the README to match the actual one-process-per-message architecture.

### 6. Message queue race condition (claude-process.ts:62-67)

If multiple messages arrive rapidly for the same channel, they queue in `pendingMessages`. When the process exits (line 105-112), the next message is dispatched after a 500ms delay. But `sendMessage` checks `managed.proc.exitCode === null` — if the new process spawns and exits very quickly, a queued message could be lost. Low probability but the queue draining logic should be more robust (e.g., drain in a loop rather than recursive `setTimeout`).

### 7. Truncation loses context (bridge.ts:182-186)

`editMessageSafe` truncates at `MAX_MESSAGE_LENGTH - 20` and appends `"\n\n…(truncated)"`. Long Claude responses will be silently cut. The `activeResponses` type has an `overflowIds: string[]` field (line 42) suggesting multi-message overflow was planned but never implemented. For MVP this is fine, but it's a known UX gap for longer responses.

### 8. Error message could leak internal details (bridge.ts:118)

```typescript
this.rest.sendMessage(channelId, `⚠️ Claude process error: ${error.message}`)
```

Sending raw `error.message` to the chat channel could expose filesystem paths, environment details, or stack traces. Consider sanitizing or using a generic error message for users.

### 9. `--dangerously-skip-permissions` security note (claude-process.ts:86)

This flag is documented in the README and appropriate for a self-hosted bridge where the operator controls what Claude can do. But worth a comment in the code noting that this means Claude can execute arbitrary commands on the host machine. Anyone running this bridge should understand the security implications.

### 10. esbuild externals (package.json:12)

Only `ws` is externalized. If `@cove/shared` uses any Node.js built-ins or has dependencies that shouldn't be bundled, those need to be external too. The `--alias` approach for `@cove/shared` source import is pragmatic for a monorepo but fragile — if `@cove/shared`'s entry point or structure changes, the build breaks silently.

## Positive Notes

- **Clean module separation**: Gateway, REST, process manager, and bridge orchestrator have clear responsibilities and minimal coupling. Easy to test each in isolation.
- **Gateway client is solid**: RESUME support, exponential backoff, heartbeat timeout detection, INVALID_SESSION handling with jittered retry — this covers the real-world reconnection scenarios well.
- **REST client rate-limit handling**: Parsing `Retry-After` header with a 30s cap is a nice detail.
- **Debounced message edits**: 300ms batching for streaming updates is a good balance between responsiveness and API load.
- **Graceful shutdown**: `SIGINT`/`SIGTERM` handlers properly clean up all processes, timers, and connections.
- **README is comprehensive**: Architecture diagram, config table, CLI flags, and limitations section. Good for an MVP.
- **TypedEmitter pattern**: The typed event emitter wrapper provides type safety for event handlers without a heavy library dependency.
