# PR #327 Review — Round 3 (Nova / Claude Opus 4.7)

## Summary
The bridge package introduces a new `@cove/claude-bridge` daemon (~1k LOC across `bridge.ts`, `claude-process.ts`, `gateway-client.ts`, `rest-client.ts`, `index.ts`). All six Round 2 issues are confirmed fixed in this revision. The remaining items are smaller edge-case and hygiene concerns; nothing that should block merging an MVP bridge intended for a personal/staging deployment.

Verdict: **✅ Ready (with suggestions)**

## Verification of Round 2 fixes
- `bridge.ts:153` — `guild_id` check now in `messageCreate` handler. ✅
- `README.md` — per-message spawn, no session persistence, correct CLI flags. ✅
- `bridge.ts:194-197` — `activeResponses.delete` gated on `!this.claude.hasProcess(channelId)`. ✅
- `bridge.ts:175` — non-zero exit sends `⚠️ Claude exited with an error (code N)`. ✅
- `bridge.ts:182,71-73` — `err.message` logged in error/edit paths. ✅
- No leftover `botUserId`, `sessionId` field on Bridge, or `randomUUID` import. ✅

## Critical Issues
None.

## Product Impact
- **Guild scoping accepts payloads with no `guild_id`.** `bridge.ts:153` only rejects when `guild_id` is present *and* mismatched. If the gateway ever sends a message without `guild_id` (DM, system event, future payload variant), the bot would respond and execute Claude with `--dangerously-skip-permissions`. Recommend inverting: require `guild_id` present and equal. This is a one-line hardening for a security-sensitive path.
- **`--dangerously-skip-permissions` + per-message spawn** means anyone with write access to a channel in the configured guild can trigger arbitrary code execution as the bridge user in `CLAUDE_WORKING_DIR`. This is documented behavior, but the README's "Limitations (MVP)" should also include an explicit **Security** section noting (a) channel posting == shell access on the host, and (b) operators must restrict channel ACLs accordingly.

## Suggestions
1. **`as any` casts on `message.guild_id`** (`bridge.ts:153`). The `Message` type from `@cove/shared` should either include optional `guild_id?: string` or the bridge should narrow once via a typed helper. `as any` here defeats the type system on the only auth-relevant field in the file.
2. **Stream event semantics assumption** (`claude-process.ts:128-143`). The `assistant` handler treats each event as a full text snapshot (`active.content = text` in `bridge.ts:227`). If `claude --output-format stream-json` ever emits incremental *deltas* instead of cumulative snapshots, the bridge will overwrite earlier text and display only the last chunk until the final `result` event lands. Worth either (a) a brief comment documenting the snapshot assumption, or (b) preferring `result` as the source of truth and treating `assistant` purely as a "still working" signal.
3. **Unbounded per-channel maps**. `activeResponses`, `editTimers`, `typingIntervals`, `processes`, `pendingMessages` (5 maps in `bridge.ts` + `claude-process.ts`) grow with every distinct channel and are only pruned on response completion or process exit. For an MVP this is fine; in long-running deployments it would help to also delete map entries on `result`/exit explicitly (the current code does this for most but not all).
4. **Orphan `setTimeout` in `drainPending`** (`claude-process.ts:152`). The 500ms respawn timer is not tracked, so `destroyAll()` during shutdown can leave a pending spawn that fires after `processes.clear()`. Track and clear these timers in `destroyAll`.
5. **`shutdown()` doesn't clear `pendingMessages`** (`bridge.ts:101-108`). Minor — process exits anyway, but if `Bridge` is ever instantiated in tests or restarted in-process, the queue would leak.
6. **`Retry-After` numeric-only parsing** (`rest-client.ts:43`). HTTP-date format is silently ignored (`parseFloat` → NaN → falls back to 1s). Acceptable since Cove server likely emits numeric, but worth a comment.
7. **PUT classified as idempotent for retry** (`rest-client.ts:30`). True per HTTP semantics, but no PUT call exists in this client — dead branch. Either remove or leave a comment.
8. **No tests for the new package.** Per review standards, "auth paths without tests = Critical" — here the only auth-relevant code is guild scoping and `author.bot` filtering. For a personal/MVP package I'm downgrading to a Suggestion, but a single integration test stubbing the gateway and asserting (a) cross-guild messages dropped, (b) bot author dropped, (c) empty content dropped, would lock in the fixes from Round 2.
9. **`console.error` for transient REST failures** (e.g. `bridge.ts:71`) — fine for MVP but consider whether a single retry-and-fail should surface back to the channel rather than silently log.
10. **`process.env[key]!` non-null assertion** (`claude-process.ts:42`) after a truthy check — the check rejects empty strings, which is probably fine but worth `?? ""` if empty values should also pass through (e.g. `TERM=""`). Not blocking.

## Positive Notes
- The Round 2 fix to `handleUserMessage` (gate `activeResponses.delete` on `!hasProcess`) is the right shape — it preserves in-flight messageId so subsequent `assistant` events keep editing the correct message until `result`.
- Race handling in `handleClaudeText` for "result arrives before sendMessage resolves" via `resultPending` is correctly thought through (`bridge.ts:217-224`, `bridge.ts:251-257`).
- `gateway-client.ts` correctly handles `INVALID_SESSION` with jittered re-IDENTIFY, RESUME timeout fallback, and tracks `currentWs` to avoid IDENTIFY-ing on a stale socket — solid for a "simplified" port.
- `RestClient` correctly distinguishes idempotent vs non-idempotent for 5xx retries, handles 429 separately, and uses `AbortSignal.timeout` instead of hand-rolled timeouts.
- Env sanitization (`ALLOWED_ENV_KEYS`) is conservative and aligns with the README claim.
- `editMessageSafe` truncation math (`MAX_MESSAGE_LENGTH - 20` + `"\n\n…(truncated)"`) is correct and bounded.

File: `~/.openclaw/workspace/code-review/reviews/cove-327-nova-r3.md`
