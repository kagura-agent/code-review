# 🌟 Stella — Review: cove PR #423

**PR:** refactor(plugin): adopt SDK createChannelRunQueue for message dispatch (#421)
**Branch:** `refactor/421-adopt-sdk-run-queue` → `main`
**Stats:** +633 / -416 across 9 files (spec doc accounts for 403 of additions)

---

## Verdict: ✅ Approve

This is a well-executed architectural alignment. The code replaces a bespoke queue+pendingDispatches system with battle-tested SDK primitives, eliminates a real failure class (`isCurrent()` false-positive drops), and brings Cove to parity with Discord plugin patterns. The spec is thorough and the implementation follows it faithfully.

---

## Correctness

### 🟡 Minor: Queue depth tracking race on early-return paths

**File:** `channel.ts` L143–155 (trackEnqueue/trackDequeue)

The `trackEnqueue` increments the counter, then checks if it exceeds `QUEUE_DROP_THRESHOLD`. If it does, it decrements and returns `false`. But if the `runQueue.enqueue()` call or the `dispatchMessage()` inside it throws *before* reaching the `finally { trackDequeue(channelId) }`, the counter stays permanently elevated.

This is low-impact because:
- `onError` in runQueue catches task failures
- The dispatch itself has a try/catch that resolves cleanly on abort

But if `runQueue.enqueue` itself throws (SDK bug / deactivated queue), the counter leaks. Consider wrapping the enqueue in try/catch in `onFlush` to call `trackDequeue` on enqueue failure.

### ✅ `isAborted()` inversion is correct throughout

All `if (!isCurrent()) return` → `if (isAborted()) return` and `if (isCurrent()) fn(...)` → `if (!isAborted()) fn(...)` inversions are semantically correct. Verified in dispatch.ts L26, L53, L103, L130, L139, L148, L152, L158, L171.

### ✅ `editFinal` throws on abort — correct

`editFinal` (dispatch.ts L130) now throws instead of silently returning. This is the correct Discord-parity behavior that allows the SDK's `deliverWithFinalizableLivePreviewAdapter` to fall back to `deliverNormally`. The catch block at L305 correctly handles this by checking `abortSignal?.aborted`.

### ✅ Orphaned draft cleanup logic is sound

`finally` block (dispatch.ts L309–315): `!finalReplyDelivered && !finalizedViaPreviewMessage && draftMessageId` is the correct three-way guard. The `finalizedViaPreviewMessage` flag at L134 prevents double-delete of in-place finalized drafts.

---

## Security

No concerns. No new auth paths, no credential handling changes, no user input flowing to eval/exec.

---

## Performance

### ✅ `mergeAbortSignals` is efficient

The `utils.ts` implementation correctly short-circuits for 0/1 signals and uses native `AbortSignal.any()` when available (Node 20+). The polyfill path with manual listeners is correct and cleans up via `{ once: true }`.

### 🟡 Minor: `queueDepth` Map never shrinks

**File:** `channel.ts` L145

`queueDepth` keys are never deleted — once a channel has been seen, its entry persists at `0`. For a long-running plugin with many transient channels, this is a minor memory leak. Not a blocker (channels are finite in Cove), but a `Map.delete` when depth hits 0 in `trackDequeue` would be cleaner.

---

## Readability

### ✅ Spec-to-implementation traceability is excellent

Each numbered change in the spec maps clearly to a section of the diff. The inline comments (e.g., "Discord's syntheticMessage pattern", "Discord parity") make the rationale obvious to future readers.

### 🟡 Suggestion: The `onFlush` callback (channel.ts ~L156–195) is 40 lines deep inside the debouncer config object. Consider extracting it into a named function (`async function handleDebouncerFlush(entries)`) at the same scope level for readability. Not a blocker.

---

## Testing

### ✅ Tests properly migrated

- `dispatch-behavior.test.ts`: All `pendingDispatches` patterns correctly replaced with `AbortController` + `abortSignal`. F5/F6/F7 now test the actual abort mechanism instead of map manipulation. Good.
- `dispatch-resilience.test.ts`: Properly repurposed from testing map-based cancellation to testing `mergeAbortSignals` and `isAborted` patterns. Covers edge cases (undefined signal, pre-aborted source, both sources).
- Batch test (D4, G3, G-section) correctly removed — batching now happens at debouncer level which is SDK-tested.

### 🟡 Gap: No test for orphaned draft cleanup (spec test item 7/8)

The spec explicitly calls out testing:
- "Verify orphaned draft cleanup: `!finalReplyDelivered && !finalizedViaPreviewMessage && draftMessageId` → draft deleted"
- "Verify in-place finalized draft is NOT deleted"

These aren't covered in the current test files. They'd require mocking `restClient.deleteMessage` and verifying it's called/not-called in the finally block. Suggestion: add H5d-style tests for this.

### 🟡 Gap: No test for queue depth guard

`trackEnqueue`/`trackDequeue` logic (warn at 10, drop at 20) has no unit test. These are simple functions but the drop-on-overflow behavior is user-visible (messages silently discarded).

---

## Input Validation

### ✅ `debouncer.enqueue({ message })` — message already validated

The messageCreate handler filters bot messages and self-messages before enqueueing. The debouncer's `shouldDebounce` checks content and media presence. Adequate.

---

## API & Interface Design

### ✅ `DispatchMessageOptions` simplification is clean

Removing `pendingDispatches` and `batchedMessages`, adding `abortSignal?: AbortSignal` — this is a strict narrowing of the interface. Callers pass less, dispatch owns less state. Good.

### ✅ `batchMeta` on merged message is well-designed

The `batchMeta` field (channel.ts L183–187) follows Discord's `MessageSids/MessageSidFirst/MessageSidLast` pattern, and is spread into `ctxPayload` only when present (dispatch.ts L270–274). Clean conditional spreading.

---

## Config & Schema Consistency

### 🟡 Note: `QUEUE_DROP_THRESHOLD = 20` vs old `MAX_QUEUE_SIZE = 5`

The old queue had a hard limit of 5 messages. The new depth guard drops at 20. This is a 4x increase in the maximum buffered messages per channel. The spec acknowledges this as "Low impact — serial processing means queue rarely exceeds 1-2 items." Agreed — this is intentional and documented.

---

## Product Impact

### ✅ Eliminates `isCurrent()` failure class

The core motivation (#419) is fully addressed. `isAborted()` backed by `AbortSignal` is a standard, well-understood mechanism that can't produce the false-positive stale detection that `pendingDispatches.get(channelId) === abortController` could.

### ✅ Free status reporting

`setStatus` callback in `createChannelRunQueue` gives `activeRuns`/`busy` visibility for free.

### ✅ Reconnect behavior is safer

Old: abort all pending → messages in flight get killed mid-stream.
New: in-flight dispatches finish naturally. Only truly aborted (via shutdown signal) dispatches get interrupted. This prevents the reconnect-triggered reply drops that were hard to debug.

---

## Summary

| Dimension | Rating |
|-----------|--------|
| Correctness | ✅ Sound (1 minor note) |
| Security | ✅ No concerns |
| Performance | ✅ Good (1 minor note) |
| Readability | ✅ Well-structured |
| Testing | 🟡 Two coverage gaps |
| Input Validation | ✅ Adequate |
| API Design | ✅ Clean simplification |
| Config/Schema | ✅ Documented change |
| Product Impact | ✅ Positive |

**Blockers:** None.

**Suggestions (non-blocking):**
1. Add test coverage for orphaned draft cleanup (spec items 7/8)
2. Add test for queue depth guard drop behavior
3. Consider `queueDepth.delete(channelId)` when depth reaches 0
4. Guard `trackDequeue` if `runQueue.enqueue` throws before task executes
5. Extract `onFlush` into a named function for readability
