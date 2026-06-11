# Nova Review — cove#327 (Claude Code bridge)

**Verdict:** ⚠️ Needs Changes

## Summary

A new `@cove/claude-bridge` package that connects a local `claude` CLI to a Cove server via the gateway WebSocket + REST API. The gateway/REST client and lifecycle scaffolding are solid (good cleanup, exponential backoff, RESUME, debounced edits). However, the core message pipeline has a confirmed race condition that drops responses, the session-persistence story claimed in the README is not implemented, and the stream-json event parsing appears to target the wrong shape — so the most user-visible feature (streaming Claude text into Cove) likely doesn't actually fire. Combined with `--dangerously-skip-permissions` and no user allowlist, the security posture also needs an explicit decision before merge.

## Critical Issues

### 1. Race: response is silently dropped if Claude finishes before the first `sendMessage` resolves
`bridge.ts` `handleClaudeText` / `handleClaudeResult`:
- First text chunk path sets `active.messageId = ""`, fires `rest.sendMessage(...)` (async), then relies on the `.then()` callback to record `msg.id`.
- If `handleClaudeResult` runs before that `.then()` resolves, it hits the `active && !active.messageId` branch, updates `active.content = resultText`, then **unconditionally calls `this.activeResponses.delete(channelId)`**.
- When the original `sendMessage` finally resolves, `this.activeResponses.get(channelId)` returns `undefined`, so no edit is scheduled. The user sees only the first partial chunk; the final answer is lost.

Fix options: keep `active` until both the initial POST and the final result have reconciled, or await the initial `sendMessage` before processing further stream events for that channel.

### 2. Stream-json parsing targets a shape Claude Code doesn't emit
`claude-process.ts` `handleStreamEvent`:
- `"assistant"` branch reads `event.text` (string). Claude Code's `--output-format stream-json` `assistant` events are `{ type: "assistant", message: { content: [{ type: "text", text: "..." }, ...] }, ... }`. There is no top-level `event.text` on assistant events — so `text` is never emitted and streaming updates never happen.
- The `"result"` branch reading `event.result` is correct, so users will see the final answer in one shot, but the "streaming with debounced edits" story in the README is broken in practice.

Verify against the actual stream-json schema (run `claude --print --verbose --output-format stream-json -p "hi"` and inspect) and parse `message.content[].text` for assistant deltas.

### 3. README ↔ code mismatch on session persistence and CLI flags
- README claims `--input-format stream-json`, `--session-id <deterministic-uuid>`, and "Each channel gets a deterministic session ID derived from the channel ID, so Claude can resume conversations across bridge restarts."
- Actual `spawnProcess` args: `--print --verbose --output-format stream-json --dangerously-skip-permissions -p prompt`. No `--input-format`, no `--session-id`, no `--resume`.
- `deterministicUUID(...)` is defined but never called. `channelSessions.set(channelId, sessionId)` is written on exit but never read. `sessionId` per process is a fresh `randomUUID()` each spawn.
- Net effect: every user message is an independent Claude invocation with no memory. The advertised "session persistence across restarts" does not exist.

Either implement `--resume <sessionId>` using the persisted session ID (and persist across restarts to disk, since `channelSessions` is an in-memory `Map`), or update the README to remove the claim and delete the dead `deterministicUUID` / `channelSessions` code.

### 4. `guildId` is required by config but never used to filter messages
`bridge.ts` accepts `guildId` and stores it, but `messageCreate` only checks `author.bot`. Any message in any channel/guild the bot can see will trigger Claude. Combined with `--dangerously-skip-permissions`, this is a meaningful blast radius. Add a `message.guild_id === this.guildId` (and ideally `channel_id` allowlist or explicit-mention requirement) check before invoking Claude.

## Product Impact / Security

### 5. `--dangerously-skip-permissions` + no user allowlist
Every user-sent message in any visible channel becomes an unconfined Claude invocation against `CLAUDE_WORKING_DIR` with the bridge process's full credentials (filesystem, network, env including secrets passed through `{ ...process.env }`). For a personal/self-hosted deployment this may be acceptable, but it should be an explicit decision:
- Document the trust model in the README (anyone who can post in the guild can execute arbitrary code on the host).
- Add a `COVE_ALLOWED_USER_IDS` (or guild-admin-only) gate before spawning.
- Consider passing a minimal env subset instead of `{ ...process.env }` to avoid leaking unrelated tokens to the Claude child.

### 6. Discord-style 2000-char truncation drops content
`editMessageSafe` truncates with `…(truncated)` instead of splitting into follow-up messages. The `overflowIds: string[]` field on `activeResponses` is reserved for this but never used. Claude responses routinely exceed 2k chars — users will silently lose answers. Either implement the overflow split that the data structure hints at, or remove `overflowIds` and document the limit prominently.

## Suggestions

- **No tests.** 1036 lines, zero. At minimum, unit-test `handleStreamEvent` event shapes (so issue #2 doesn't regress) and the `RestClient` 429/5xx retry behavior. The bridge orchestration is harder to test but a fake `GatewayClient` + fake `ClaudeProcessManager` would exercise the race in #1.
- `claude-process.ts` `console.log("[claude] Spawned process...")` runs *after* attaching listeners and `proc.exit` — fine, but the matching exit log lives in `bridge.ts` instead of next to the spawn log; consolidate.
- `pendingMessages` queue: on `error` (not `exit`), the queue is never drained — the channel will silently stop responding until restart. Drain pending on `error` too, or merge the error + exit paths.
- `handleClaudeText` assumes `event.text` is cumulative (it does `active.content = text`, not append). Once #2 is fixed to parse `message.content`, confirm whether the incoming chunks are cumulative or delta and handle accordingly. Assistant events in stream-json are typically discrete blocks, not cumulative — getting this wrong will produce only-the-last-chunk output.
- `botUserId` is set on `ready` but never read; `author.bot` is used instead. Either filter on `botUserId === message.author.id` (more precise — avoids ignoring legitimate user messages from accounts marked `bot`) or drop the field.
- `rest-client.ts`: `isIdempotent` includes `PUT` but not `POST`. `sendMessage` (POST) won't retry on 5xx, which is probably what you want for non-idempotent ops — confirm intentional and document. Also: `parseFloat(raw ?? "") || 1` silently defaults a malformed `Retry-After` to 1s; for HTTP-date format this is wrong. Consider parsing both seconds and HTTP-date.
- `gateway-client.ts` `invalidSessionTimer` is stored but a subsequent INVALID_SESSION won't clear the previous timer — small leak / duplicate IDENTIFY risk. Clear it at the top of the case.
- `TypedEmitter` uses `any` in `Parameters<T[K] & ((...args: any[]) => any)>`. Minor, but if `@cove/shared` already exports a typed emitter helper, prefer it for consistency with the rest of the monorepo.
- `bridge.ts` `start()` fetches the gateway URL from REST purely to log it, then ignores it and uses the derived `wsUrl`. Either use the discovered URL (preferred — that's why the endpoint exists) or remove the call.
- `MAX_MESSAGE_LENGTH = 2000` is hardcoded as "Discord limit" — Cove may have its own limit; pull from `@cove/shared` if available.
- Env handling: `process.env.CLAUDE_WORKING_DIR || process.cwd()` is fine, but there's no validation that the path exists / is a directory. A clearer error at startup beats a confusing `spawn ENOENT` later.

## Positive Notes

- **Gateway client is well-built**: heartbeat ack tracking, exponential backoff with cap, RESUME-with-timeout-then-IDENTIFY fallback, jittered INVALID_SESSION delay, `hasConnectedOnce` to distinguish first-connect from reconnect. This is the right shape for a Discord-style gateway.
- **Cleanup discipline is excellent**: `shutdown()` clears intervals, timers, processes; `cleanup()` removes WS listeners; `destroyAll()` SIGTERMs children. Few bridges of this size get teardown this right.
- **Debounced edits with 300ms batching** is the right call to avoid hammering the REST API during streaming.
- **REST client** has reasonable 429 + 5xx retry with backoff and idempotency gating — the bones are right, just needs the polish noted above.
- **Stderr is line-buffered and prefixed** with a short channel ID, which will make multi-channel debugging much easier than dumping raw streams.
- Separation of concerns across `gateway-client` / `rest-client` / `claude-process` / `bridge` is clean and reads like a 4th file you'd actually want to maintain.

---

**File:** `/home/kagura/.openclaw/workspace/code-review/reviews/cove-327-nova.md`
