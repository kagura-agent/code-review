# Stella R3 Review — kagura-agent/cove PR #327

## Summary

This PR adds `@cove/claude-bridge`, a daemon that connects Cove gateway messages to local `claude` CLI runs and posts results back through Cove REST. The latest round fixed several Round 2 items: queued messages no longer immediately clear the in-flight response, README now matches the per-message `-p` implementation, non-zero exits get a channel-visible error in the no-output case, and the unused fields/imports were removed. However, two blocking problems remain: the configured guild scope is still not actually enforceable with the current payload, and the bridge exposes a local `claude --dangerously-skip-permissions` process to any accepted chat message without user/channel gating. I also found failure/length edge cases that can still silently lose responses.

**Rating: ⚠️ Needs Changes**

## Critical Issues

1. **`COVE_GUILD_ID` is still not reliably enforced because `MESSAGE_CREATE` payloads do not include `guild_id`**  
   `packages/claude-bridge/src/bridge.ts:99-100` now checks `(message as any).guild_id`, but the Cove shared `Message` type has no `guild_id`, and the server dispatcher currently broadcasts `MESSAGE_CREATE` with the raw `Message` object (`packages/server/src/ws/dispatcher.ts:70-72`). That means this condition only rejects messages if a future/foreign payload happens to include a mismatched guild id; current Cove message events will pass the filter because `guild_id` is absent. Since `COVE_GUILD_ID` is required config and documented as scoping message handling, this is still a real isolation bug if the bot session receives events from more than one guild.  
   **Fix:** include `guild_id` in `MESSAGE_CREATE` dispatches, or make the bridge build an allowed channel set for `COVE_GUILD_ID` and reject unknown channels. Also add a negative test proving messages outside the configured guild are ignored.

2. **Any guild member/channel that reaches the bridge can drive a local unrestricted Claude Code process**  
   `packages/claude-bridge/src/bridge.ts:95-107` forwards every non-bot, non-empty accepted message to Claude, and `packages/claude-bridge/src/claude-process.ts:76-81` runs `claude --dangerously-skip-permissions`. With the current design, a normal Cove chat message can ask the local Claude process to read/write files or run tools in `CLAUDE_WORKING_DIR`. That may be acceptable for a single-user private lab, but as a bridge daemon this is an unsafe default and becomes especially dangerous while guild scoping is ineffective.  
   **Fix:** require explicit operator-controlled gating before spawning Claude: at minimum channel allowlist and/or user allowlist env vars, or only respond to mentions/commands in configured channels. Consider not using `--dangerously-skip-permissions` by default; make the unsafe mode an explicit opt-in with documentation.

3. **Non-zero exits after partial output still leave users with a silent/incomplete response**  
   `packages/claude-bridge/src/bridge.ts:132-138` sends the sanitized non-zero-exit warning only when `!this.activeResponses.has(channelId)`. If Claude emits an `assistant` text event, then fails before a `result`, `activeResponses` remains present, so the bridge logs the exit, stops typing, and does not tell the channel that the run failed. The active response also remains stuck until a later user message clears it. This only fixes the “no output at all” failure case from Round 2, not the common “partial output then crash/auth/tool failure” case.  
   **Fix:** track per-run completion state (`result` received vs. not received) separately from “response message exists”. On non-zero exit without a completed result, edit the partial message or send a follow-up sanitized error, then clear response state.

4. **Long first/final responses can still fail POST and strand `activeResponses`**  
   `editMessageSafe()` truncates edits (`packages/claude-bridge/src/bridge.ts:240-245`), but first streamed text uses raw `rest.sendMessage(channelId, text)` (`bridge.ts:173`) and result-without-streaming uses raw `rest.sendMessage(channelId, resultText || ...)` (`bridge.ts:220`). Cove validates message content at max 4000 chars. If the first assistant event or direct final result exceeds the server limit, the POST fails; in the first-text path the catch only logs (`bridge.ts:186-188`) and leaves an `activeResponses` entry with no `messageId`, so a later `result` just sets `resultPending` and never reaches the user.  
   **Fix:** centralize `sendMessageSafe()` and use it for all sends as well as edits. Either split long Claude output across multiple messages or apply consistent truncation before every REST call, and clear/fallback when the initial send fails.

## Product Impact

- The operator-facing `COVE_GUILD_ID` setting remains misleading: it appears to scope the bridge, but current Cove `MESSAGE_CREATE` events do not provide the data needed for this implementation to enforce it.
- The bridge currently turns Cove chat access into local Claude Code control. Without explicit allowlists or command gating, this is a significant deployment foot-gun.
- Users can still see partial/no response for long outputs or Claude failures even though the bridge logs the failure locally.

## Suggestions

- Add tests around the bridge state machine: guild filtering with absent/mismatched `guild_id`, non-zero exit after partial text, initial `sendMessage` failure, long result handling, and queued messages. The queued-message corruption from Round 2 looks fixed, but it deserves regression coverage.
- Queued messages currently call `ClaudeProcessManager.drainPending()` → `sendMessage()` directly (`claude-process.ts:127-135`), bypassing `Bridge.handleUserMessage()`. That means the queued run does not restart typing after the previous run stops typing. Non-blocking, but users may not see activity for queued work.
- If the `bin` entry is meant to support direct execution as `cove-claude-bridge`, add a shebang to `src/index.ts` or ensure the generated bin wrapper invokes Node correctly.
- Validate `CLAUDE_WORKING_DIR` at startup so a typo fails fast before the first chat message.

## Positive Notes

- Verified locally in a temp worktree: after applying `/tmp/cove-327.diff` and installing dependencies, `pnpm -F @cove/claude-bridge exec tsc --noEmit` and `pnpm -F @cove/claude-bridge build` both pass.
- The README now accurately describes per-message process spawning, `-p`, `--output-format stream-json`, and no session persistence.
- The Round 2 active-response corruption fix is materially better: `handleUserMessage()` only clears old response state when no process is active.
- Non-zero exits with no active response now produce a sanitized channel-visible warning, which is a good improvement over log-only failure.
- `sanitizedEnv()` is a sensible default for reducing accidental secret exposure to child processes.
