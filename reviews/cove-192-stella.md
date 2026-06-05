# Stella Review — kagura-agent/cove PR #192 — Round 4

## R3 Issue Status

1. **🔴 ESCALATED: Auto-ack dedup doesn't survive remount / channel switch** — ⚠️ Partially Fixed
   - The specific `lastAckedIdRef` reset problem is fixed: `lastAckedIds` is now a module-level `Map`, so it survives `MessageList` unmount/remount and channel switch away/back within the same browser session (`packages/client/src/components/MessageList.tsx:19-20`, `packages/client/src/components/MessageList.tsx:74-81`).
   - Remaining gap: it still does not use persisted/READY read state. After a page reload or new tab, the map is empty, `READY` may already say the channel is read, but `MessageList` still sends another ack for the same last message (`packages/client/src/components/MessageList.tsx:74-81`, `packages/client/src/stores/useReadStateStore.ts:16-29`).
   - Because this was already escalated in R3, I would not call the dedup behavior fully fixed until the load path checks `readStates[channelId] === lastMsg.id` or updates the dedup cache from READY/MESSAGE_ACK state.

2. **🟡 Stale `MESSAGE_ACK` dispatch when DB skips update** — ✅ Fixed
   - `ReadStatesRepo.set()` now returns a boolean, and the ack route dispatches `MESSAGE_ACK` only when `set()` reports an actual write (`packages/server/src/repos/readStates.ts:13-23`, `packages/server/src/routes/messages.ts:143-144`).
   - For the older-message stale-ack case from R3, the DB guard skips the update and the route no longer emits a misleading `MESSAGE_ACK`.
   - Caveat: equal-timestamp cases are still not skipped; that is covered under the monotonic tie issue below.

3. **🟡 No `MESSAGE_ACK` dispatch on implicit self-ack** — ✅ Fixed
   - Message creation now persists the sender's read cursor, then sends `MESSAGE_ACK` to that user when the cursor advances (`packages/server/src/routes/messages.ts:61-70`).
   - This should clear the sender's other connected sessions after self-send.

4. **🟡 Monotonic ack timestamp ties / same-ms messages** — ❌ Not Fixed (escalated)
   - The monotonic guard still compares only `timestamp` and still allows `>=` (`packages/server/src/repos/readStates.ts:17-22`). Two messages created in the same millisecond can still be acked newer-then-older, and the older same-ms ack will overwrite the cursor.
   - READY's latest-message query also orders only by `m.timestamp DESC` (`packages/server/src/repos/readStates.ts:29-36`), so same-ms latest-message selection is nondeterministic.
   - Per the re-review escalation rule, this remains escalated rather than downgraded.

5. **🟢 `CONTRIBUTING.md` bash fence** — ✅ Fixed
   - The prose is now outside the `bash` fenced block, and the fenced block contains only shell/Node commands (`CONTRIBUTING.md:164-175`).

6. **🟢 `ReadStateRow` type alias cleanup** — ✅ Fixed
   - The current `readStates.ts` no longer has the `ReadStateRow` alias; inline row types are used instead (`packages/server/src/repos/readStates.ts:6-10`, `packages/server/src/repos/readStates.ts:26-36`).

## New Issues

### 🟡 Ack dedup cache is updated before ack success, so transient failures suppress retries

- **Files:** `packages/client/src/components/MessageList.tsx:77-80`
- **Problem:** The load-time auto-ack path writes `lastAckedIds.set(channelId, lastMsg.id)` and clears unread before `api.ackMessage()` succeeds, then swallows failures. If the ack request fails transiently, the current browser session records the message as already acked and will not retry that same message on channel revisit.
- **Impact:** The UI can show the channel as read while server read state is unchanged; the same message is not retried until page reload or a newer message arrives.
- **Suggested fix:** Move the dedup/cache update after ack success, or better, dedupe from confirmed `readStates` / `MESSAGE_ACK` state. If keeping optimistic UI, rollback or retry on failure.

## Summary & Verdict

The latest commit fixed several important consistency issues: stale older acks no longer dispatch when the DB guard skips them, implicit self-acks now notify the sender's sessions, and the docs/type cleanup items are done. The module-level auto-ack map also fixes the narrow remount/channel-switch reset from R3.

Two read-state correctness gaps remain:

- The already-escalated auto-ack dedup is only partial because reload/new-tab paths still don't consult persisted read state.
- The same-millisecond monotonicity issue is still unresolved and is now escalated under the re-review rules.

Validation run locally on the current branch:

- `pnpm -r test` — passed: client 6, plugin 38, server 118 tests.
- `pnpm -r build` — passed; existing Vite chunk-size warning only.

**Rate: ⚠️ Needs Changes**
