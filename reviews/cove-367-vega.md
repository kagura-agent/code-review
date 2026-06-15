## Summary
This PR introduces a bounded per-channel message queue to prevent new incoming messages from aborting in-progress dispatches. The `ChannelMessageQueue` implementation is clean, logically sound, and safely integrates with the plugin's reconnect and shutdown lifecycles without leaking memory.

## Critical Issues
None.

## Product Impact
Highly positive. This solves the frustrating "lost reply" issue when the bot receives a burst of messages, queuing them sequentially up to 5 per channel and ensuring the bot finishes its current thought before moving to the next.

## Suggestions
- **Avoid floating Promises:** In `enqueue()`, the call to `this.processNext(channelId);` is a floating promise. Although `processNext` wraps the dispatch in a try/catch, adding a `.catch()` to the invocation (e.g., `this.processNext(channelId).catch(err => this.log?.warn?.(err));`) is a best practice to prevent Node.js unhandled rejection crashes if an error is ever thrown synchronously before the first `await`.
- **Use a `while` loop instead of recursion:** In `processNext`, it's generally cleaner for message loops to use a `while` loop rather than recursively calling `await this.processNext(channelId);`. While V8 handles async recursion well, a loop avoids unnecessary Promise chain allocations.
- **Unit Testing:** `ChannelMessageQueue` is nicely decoupled. Adding a quick unit test file (e.g., `message-queue.test.ts`) would be a great non-blocking addition to lock in the FIFO order and size limit behavior.

## Positive Notes
- State clearing on `clearAll()` and `reconnect` is handled beautifully. By leaving the `processing` flag alone and just clearing the queue arrays, in-flight tasks finish naturally and gracefully exit the loop.
- The `MAX_QUEUE_SIZE = 5` is a smart, simple guardrail against unbounded memory growth from spam or bursts.

**Rate:** ✅ Ready
