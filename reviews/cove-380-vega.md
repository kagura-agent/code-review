# Code Review: PR #380 (batch merge queued messages)

**Rate:** ⚠️ Needs Changes

## Overview
The logic for batching queued messages into a single agent turn is a great addition and functionally looks sound. By draining pending items from the queue while the agent is busy and concatenating them as context for the final message, we avoid spamming the agent and ensure it sees the full context of a rapid burst of messages. 

However, there are several severe code quality regressions and type safety issues introduced in this PR that need to be addressed before merging.

## Issues to Address

### 1. Code Style and Documentation Regressions (`message-queue.ts`)
This file looks like it was partially minified or hastily edited:
- **Lost Documentation:** The very helpful module-level JSDoc explaining the purpose of the sequential queue has been deleted. The docstrings for `clearAll`, `clear`, and `size` were also removed. Please restore them.
- **String Concatenation:** Modern template literals (e.g., `` `cove: enqueued message...` ``) were replaced with clunky string concatenation (`'cove: ...' + channelId`). Revert back to template literals for readability.
- **Single-line Blocks:** Readable multi-line `if` statements were compressed into single lines (e.g., `if (!queue) { queue = []; this.queues.set(channelId, queue); }`). This makes the code significantly harder to read and maintain.

### 2. Constructor Overload Hack (`message-queue.ts`)
The `ChannelMessageQueue` constructor signature was changed to accept either the `log` object directly or an `opts` object:
```typescript
if (opts && 'batchDispatchFn' in opts) { ... } else { this.log = opts as any; }
```
This is messy. Since `message-queue` is internal, it is better to refactor the constructor to exclusively take an options object, e.g., `constructor(options: { dispatchFn, batchDispatchFn?, log? })`, and update the callers accordingly, rather than relying on `in` checks and `as any` casting.

### 3. Type Safety (`dispatch.ts` & `channel.ts`)
Adding custom properties to the message via `Object.assign({}, primary, { _batchedMessages: earlier })` and then reading it via `(message as any)._batchedMessages` works at runtime but bypasses TypeScript's type checking.
Instead of using `any`, consider defining an extended interface:
```typescript
interface BatchedMessage extends Message {
  _batchedMessages?: Message[];
}
```
Then typecast `message as BatchedMessage` to keep type safety intact.

## Summary
The functional approach is correct, but the PR needs a clean-up pass to fix code formatting, restore lost documentation, and improve TypeScript typings and the constructor signature.