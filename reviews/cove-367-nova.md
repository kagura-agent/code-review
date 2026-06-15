# 🌠 Nova Review — PR #367

**Title:** feat(plugin): per-channel message queue for sequential dispatch (#291)
**Scope:** +112 / −17, 3 files
**Verdict:** ✅ Ready (minor non-blocking suggestions)

## 1. Summary
Replaces the previous "abort-on-new-message" behavior with a per-channel FIFO `ChannelMessageQueue` so bursts of messages (especially issue-notification storms) no longer cause in-flight replies to be aborted and lost. Implementation is small, focused, and reads cleanly. The queue cooperates correctly with the existing `pendingDispatches` abort-controller set: the queue serializes one dispatch per channel, and `pendingDispatches` remains the mechanism for reconnect/shutdown cancellation. Behavior matches the PR description (FIFO, max 5, drop-oldest on overflow, clear on reconnect/shutdown).

## 2. Critical Issues
None — no functional bugs or security risks found that would block merge for a personal project.

## 3. Product Impact
- **Behavior change (intentional):** rapid follow-up messages no longer cancel the bot's in-progress reply. Users may now see the bot complete an "outdated" reply before responding to the newer message. This is the explicit goal and improves issue-notification UX.
- **Drop-oldest on overflow** (`message-queue.ts:38`): under sustained bursts (>5 queued), the *oldest queued* message is silently dropped (with a warn log, no user-visible signal). For issue-notification bursts this is fine; for human conversation it could look like the bot "skipped a message" without acknowledgement. Worth keeping in mind if a human ever fires 6+ messages back-to-back.
- **Reply ordering**: replies are now strictly serialized per channel. Slow dispatches will visibly delay subsequent messages instead of pre-empting. Expected, but a change in feel.

## 4. Suggestions (non-blocking)
- `message-queue.ts:81` — `clearAll()` clears `this.queues` but leaves `this.processing` flags untouched (comment notes this is intentional so in-flight dispatch finishes naturally). After in-flight `dispatchFn` resolves, `processNext` will see the empty queue and `delete(channelId)` the flag, so this is correct. Worth keeping the comment; consider also leaving a note that the in-flight dispatch is cancelled via the `pendingDispatches` AbortController in `channel.ts:263`, not by the queue itself — the cooperation between the two layers is the only mildly subtle part.
- `message-queue.ts:62` (`processNext` recursion) — uses `await this.processNext(...)` at the tail. Safe under async/await microtask scheduling (no stack growth), but a `while` loop reads slightly more obviously and avoids the appearance of recursion. Cosmetic.
- `message-queue.ts:23` — `this.queues` map entries are never removed for idle channels (only `this.processing` is). Minor memory creep for long-lived processes with many channels. Could `this.queues.delete(channelId)` inside `processNext` when the queue empties.
- `message-queue.ts:46` — `log?.info?.` on every enqueue. With bursty traffic this can be noisy; consider `info` only when `queue.length > 1` (i.e. actual queueing happened) and `debug`/silence for the immediate-dispatch case.
- `MAX_QUEUE_SIZE = 5` (`message-queue.ts:19`) — hardcoded module constant. Fine for now; if the threshold ever needs per-account tuning, lifting into config is trivial.
- `dispatch.ts:72` — the old code deleted superseded controllers; the new code still does `pendingDispatches.set(channelId, abortController)` on every dispatch. Since the queue guarantees only one dispatch runs at a time per channel, there will normally be at most one entry per channel — but check that the dispatch path still deletes/cleans the entry in `finally` (not visible in this diff). If `dispatchMessage` doesn't clean it up, the map will hold stale (already-settled) controllers indefinitely. Worth a quick glance at the unchanged tail of `dispatch.ts` before merge.
- **Tests:** PR description lists manual test steps but no automated tests for `ChannelMessageQueue`. The class is pleasantly pure (one injected `dispatchFn`, no I/O) — a small unit test exercising FIFO order, drop-oldest, and the "enqueue during processing" path would lock in behavior cheaply. Non-blocking for personal-project bar.

## 5. Positive Notes
- Nice separation of concerns: `ChannelMessageQueue` is a small, dependency-injected class with no Cove- or Discord-specific knowledge beyond the `Message` type.
- The `enqueue → processNext` start condition is implemented correctly without a lock — relies on JS single-threaded execution and a synchronously-set `processing` flag, which is the right idiom here.
- Reconnect path properly clears both `pendingDispatches` (aborts in-flight) and `messageQueue` (drops queued) — no risk of zombie replies after a hard reconnect.
- Shutdown path (`channel.ts:378-381`) mirrors reconnect cleanup correctly.
- PR is small, well-scoped, with a clear problem statement and reproducible manual test plan. Closes the linked issue #291 cleanly.

---
**Path:** `/home/kagura/.openclaw/workspace/code-review/reviews/cove-367-nova.md`
