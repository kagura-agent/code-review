# 🌠 Nova Review — PR #423: Adopt SDK `createChannelRunQueue` for message dispatch

**PR:** [kagura-agent/cove#423](https://github.com/kagura-agent/cove/pull/423)
**Branch:** `refactor/421-adopt-sdk-run-queue` → `main`
**Size:** +633 / -416 (9 files; ~403 of the additions are the spec doc)
**Verdict:** ✅ **Approve** (with minor suggestions)

---

## Summary

Replaces the custom `ChannelMessageQueue` + `pendingDispatches` / `isCurrent()` with the SDK's `createChannelRunQueue` and `createChannelInboundDebouncer`. Eliminates `message-queue.ts` entirely. The refactor aligns Cove with Discord plugin architecture and fixes the #419 failure class where `isCurrent()` could silently drop final replies.

Overall this is a clean, well-spec'd architectural alignment. The implementation matches the spec closely, tests are properly updated, and the behavioral changes are intentional improvements.

---

## Correctness

### 🟡 Attachment loss on single-message flush (`channel.ts:174`)

```typescript
const mergedMessage = { ...last.message, content: combinedContent, attachments: [] };
```

`attachments: []` is unconditionally set even when `entries.length === 1`. For batched messages this is correct (media messages bypass debouncing per `shouldDebounceTextInbound`), but for the single-message flush path — a text-only message that waited for the debounce timeout with no siblings — the original message's attachments are replaced with `[]`.

In practice this is **likely safe** because `shouldDebounceTextInbound` returns `false` for messages with attachments (`hasMedia: true`), causing them to flush immediately as standalone entries. However, the defense-in-depth here is fragile: it relies entirely on `shouldDebounceTextInbound` correctly rejecting all attachment messages. A safer pattern:

```typescript
const mergedMessage = entries.length === 1
  ? last.message  // preserve original shape for non-batched
  : { ...last.message, content: combinedContent, attachments: [] };
```

**Severity:** Low (defensive improvement, not a current bug)

### ✅ `editFinal` throw on abort — correct

The change from silent return to `throw new Error("cove: dispatch aborted")` in `editFinal` (dispatch.ts:128) is correct. The adapter's `handlePreviewEditError: () => "fallback"` ensures the SDK catches this and falls back to `deliverNormally`, which itself checks `isAborted()` and short-circuits. No unhandled throw path.

### ✅ Orphaned draft cleanup — correct

The `finally` block (dispatch.ts:308-315) correctly gates on `!finalReplyDelivered && !finalizedViaPreviewMessage && draftMessageId`. Both flags are set at the appropriate points:
- `finalReplyDelivered` after `freshSend` and after `deliver`
- `finalizedViaPreviewMessage` after successful `editMessage` in `editFinal`

The `.catch()` on `deleteMessage` prevents cleanup failures from propagating.

### ✅ `isAborted()` graceful degradation

`const isAborted = () => Boolean(abortSignal?.aborted)` correctly returns `false` when `abortSignal` is `undefined`, matching the spec's graceful degradation requirement.

---

## Security

No concerns. No new auth paths, no user input passed to eval/exec. The `mergeAbortSignals` polyfill is straightforward signal composition.

---

## Performance

### ✅ Queue depth guard

The manual `trackEnqueue`/`trackDequeue` + thresholds (warn@10, drop@20) compensate for the SDK's unbounded queue. The counters are correctly decremented in `finally` blocks.

### 🟡 Minor: `queueDepth` map never shrinks

`queueDepth.set(channelId, depth - 1)` leaves entries at `0` rather than deleting them. Over a long uptime with many distinct channels, this map grows. Non-issue in practice (channels are finite), but a `Map.delete` when depth hits 0 would be tidier.

**Severity:** Negligible

---

## Readability

Clean and well-organized. The spec document is thorough and the code matches it closely. Good inline comments explaining Discord parity decisions. The test renames (e.g., `H5a: stale dispatch` → `H5a: aborted dispatch`) improve clarity.

---

## Testing

### ✅ Properly migrated

Tests correctly replace `pendingDispatches` manipulation with `AbortController` + `abortSignal` patterns. The new F6 test (graceful degradation with no signal) is a good addition.

### 🟡 Missing: debouncer integration test

The debouncer logic in `channel.ts` (merge, batchMeta, trackEnqueue/trackDequeue) has no direct test coverage in this PR. The old `message-queue.test.ts` tested queue serialization and batching; its replacement (the debouncer + runQueue combo) lacks equivalent integration tests.

The spec lists test cases 2, 3, 9 that would cover this but they aren't implemented in this diff. Presumably these are deferred to a follow-up — would be good to have a tracking issue.

**Severity:** Low (existing SDK tests cover the underlying mechanisms; this is a coverage gap for Cove-specific wiring)

### ✅ `mergeAbortSignals` well-tested

`dispatch-resilience.test.ts` comprehensively tests all branches: undefined signals, single signal passthrough, both-signal abort, pre-aborted source, empty array.

---

## Input Validation

No new external input paths. The `trackEnqueue` overflow guard provides backpressure against message floods.

---

## API & Interface Design

### ✅ `DispatchMessageOptions` simplification

Removing `pendingDispatches` and `batchedMessages` from the interface is a clean win. The new `abortSignal?: AbortSignal` is the minimal surface.

### 🟡 `batchMeta` as untyped property on message

```typescript
mergedMessage.batchMeta = { MessageSids, MessageSidFirst, MessageSidLast };
```

This is set via object spread and accessed later as `(message as any).batchMeta` in dispatch.ts. The `any` cast works but loses type safety. Consider extending the `Message` type or using a separate parameter.

**Severity:** Low (style preference for a small team project)

---

## Config & Schema Consistency

No new config keys introduced. The debouncer inherits timing config from `cfg` via the SDK's `createChannelInboundDebouncer`, matching Discord's behavior.

---

## Product Impact

Positive:
- Eliminates the #419 failure class (dropped final replies)
- Gains SDK-managed status reporting (`activeRuns`/`busy`) for free
- ~100 lines of custom code deleted
- Better architectural alignment = easier future maintenance

Behavioral changes are intentional improvements documented in the spec's comparison table.

---

## Final Notes

This is a well-executed architectural refactor. The spec is clear, the implementation matches it, tests are properly updated, and the behavioral changes are improvements. The main suggestion (attachment handling on single-message flush) is defensive hardening rather than a bug fix. Ship it.
