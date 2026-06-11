# Stella R2 Review — kagura-agent/cove PR #327

## Summary

This PR adds a new `@cove/claude-bridge` daemon that connects Cove Gateway events to local Claude Code CLI invocations and posts responses through Cove REST. Round 1 fixed several important implementation issues, but I still see blocking problems around guild scoping, queued-message response tracking, and failure/length handling. The bridge is not ready to merge as-is because it can respond outside the configured guild and can corrupt/lose responses under normal chat usage.

**Rating: ⚠️ Needs Changes**

## Critical Issues

1. **`COVE_GUILD_ID` is still not enforced, despite being required config**  
   `packages/claude-bridge/src/bridge.ts:32`, `:54`, `:98-107` store the configured guild id but never use it when handling `MESSAGE_CREATE`. Since Cove `Message` does not currently include `guild_id`, this bridge will respond in every channel/guild delivered to the bot session, not just `COVE_GUILD_ID`. That violates the documented scoping contract and is a real isolation problem if the bot is a member of more than one guild.  
   **Fix:** either include/consume `guild_id` in gateway message events, or have the bridge fetch `GET /guilds/:guildId/channels` and maintain an allowed `channel_id` set before processing messages. Add both positive and negative tests: configured guild channel is handled; other guild channel is ignored.

2. **Queued user messages can detach/corrupt the active response for the previous Claude run**  
   `packages/claude-bridge/src/bridge.ts:144-153` deletes `activeResponses[channelId]` for every incoming user message before `ClaudeProcessManager.sendMessage()` decides whether the message will run immediately or be queued. If Claude is still answering message A and user sends message B, B is queued in `claude-process.ts:63-69`, but the bridge has already forgotten A's response message. Any later text/result from A can create a second message, leave the original partial message unfinalized, or post the final result separately.  
   **Fix:** do not clear the active response until the current process has completed, or key response state by a per-request/run id emitted by `ClaudeProcessManager`. If the new message is queued, keep A's active response intact and only initialize B's response tracking when B's process actually starts.

3. **Claude process failures can silently drop a user's request**  
   `packages/claude-bridge/src/claude-process.ts:115-119` emits `exit` for all exits, but `packages/claude-bridge/src/bridge.ts:132-135` only logs and stops typing. A non-zero Claude exit after writing diagnostics to stderr produces no channel-visible error and drains the next pending message, so the user just sees nothing. This is common for auth/config/permission/working-directory failures.  
   **Fix:** track whether a `result` was emitted; on non-zero exit or zero-exit-without-result, emit an error/failure result to the bridge so the channel receives a sanitized failure message. Keep stderr details in logs only.

4. **Long responses are not consistently truncated/split before REST sends**  
   `editMessageSafe()` truncates edits (`bridge.ts:236-244`), but initial sends and direct result sends use raw content (`bridge.ts:167`, `:214`). Cove validates message content at max 4000 chars (`packages/server/src/routes/messages.ts:48-52`), while README claims 2000-char truncation. A long first assistant event or result-without-streaming will fail the POST and leave no user-visible answer.  
   **Fix:** centralize message content preparation for both send and edit. Prefer splitting into multiple messages if preserving full Claude output matters; otherwise apply the same truncation path before every `sendMessage` call and update README to match the actual server limit/behavior.

## Product Impact

- **Configured guild scoping is currently misleading.** Operators will believe `COVE_GUILD_ID` limits the bridge, but the runtime ignores it.
- **Rapid chat interactions are unsafe.** Sending a follow-up while Claude is still responding can produce duplicate/partial/misattributed bot output.
- **README still contains stale behavior claims.** `packages/claude-bridge/README.md:16`, `:60`, `:63`, and `:70-75` say the bridge pipes `stream-json` via stdin/stdout, uses one process per channel, and passes deterministic `--session-id`. Current code uses one process per message, `-p <prompt>`, a random session id only for logging, and no session persistence. If that scope reduction is intentional, the README should say so clearly; if persistence is required, the code needs to implement it.

## Suggestions

- Add targeted tests for the bridge state machine: guild filtering, two messages in one channel while the first process is active, non-zero Claude exit, and long output handling.
- `packages/claude-bridge/src/claude-process.ts:80-85` passes user content via `-p` argv. That avoids shell injection, but it exposes message text in process listings while Claude runs. Consider stdin / stream-json input for better local privacy and to match the bridge architecture docs.
- `packages/claude-bridge/src/index.ts` / package bin: if `cove-claude-bridge` is meant to run as an installed binary, `src/index.ts` should start with a Node shebang so the generated `dist/index.js` is executable by npm/pnpm bin shims.
- Validate `CLAUDE_WORKING_DIR` at startup and fail fast with a clear error if it does not exist or is not a directory.
- `botUserId` in `bridge.ts:51` is set but unused. Ignoring all `author.bot` messages may be acceptable for MVP, but if the intended behavior is only self-loop prevention, use the READY user id and remove the unused state.

## Positive Notes

- The response race from Round 1 is materially improved with `resultPending`; final results arriving before `sendMessage()` resolves are now handled.
- Environment forwarding is much safer than before: `sanitizedEnv()` limits what reaches the Claude child process.
- Gateway URL discovery now uses the REST endpoint with a fallback, which is the right operational shape.
- Pending messages are drained on both process `exit` and spawn `error`, so one failed run no longer permanently blocks the channel queue.
