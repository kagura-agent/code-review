# Stella R3 Final Re-review — kagura-agent/cove PR #399

## Verdict

**Request changes.** R3 fixes the edit-queue/finalization race mechanics, but several previously escalated issues remain unaddressed, and there is one new R3 blocker in the preview clamp.

Validation run locally on PR head `0150bd8`:

- `pnpm -F openclaw-cove test -- --runInBand` ✅ 82 passed
- `pnpm -F openclaw-cove check` ✅ passes

Passing tests do not cover the blocking delivery paths below.

---

## Previous issues checklist

### R1 findings

- **C1: Dead adapter code** — ✅ Resolved enough structurally; the plugin now has an outbound adapter wired under `base.outbound`.
- **C2: Draft streaming removed** — ✅ Mostly resolved; draft streaming is restored via `createFinalizableDraftLifecycle`, and R2's edit queue/final race mechanics are addressed.
- **C3: Tool progress no-op** — ✅ Resolved; tool progress updates are wired into draft updates.
- **C4: Tests don't test changed behavior** — ❌ **Still not addressed; remains Critical.** The new tests mostly assert wrapper presence or test copied mini-reproductions, not production delivery behavior.
- **C5: No error recovery** — ✅ Resolved for final-edit failure; fallback sends chunks and best-effort deletes the orphan draft.

### R2 findings

- **N1: `editQueue` const never reassigned / concurrent drafts** — ✅ Resolved. `editQueue` is now `let` and chained sequentially in `dispatch.ts:115-123`.
- **N2: `finalizeDraft` races late partials** — ✅ Resolved in the implementation. Final delivery sets final state, seals the draft, then awaits `editQueue` before final edit/send (`dispatch.ts:195-197`). Needs a real production-path test, but the code path is fixed.
- **N3/N4: `coveOutbound` half-dead; `chunkerMode` / `deliveryCapabilities` not in actual adapter** — ❌ **Not addressed; escalated to Critical.** See Finding 2.
- **N5: Chunk limit hardcoded in multiple places** — ❌ **Not addressed; escalated to Critical.** See Finding 3.
- **M2: `onCompactionStart` lost preview update** — ✅ Resolved. `onCompactionStart` now calls `draft.update(combined)` (`dispatch.ts:254-258`).
- **C4 escalated: Tests still don't exercise delivery behavior** — ❌ **Still not addressed; remains Critical.** See Finding 4.

---

## Findings

### 1. Critical — R3 preview clamp still exceeds Cove's 4000-character limit

**Location:** `packages/plugin/src/dispatch.ts:129-130`

```ts
const preview = trimmed.length > COVE_TEXT_CHUNK_LIMIT
  ? trimmed.slice(0, COVE_TEXT_CHUNK_LIMIT - 30) + '\n\n… (streaming, full reply on completion)'
  : trimmed;
```

The suffix is **41 UTF-16 code units / characters**, not 30:

```text
"\n\n… (streaming, full reply on completion)".length === 41
```

So for long streamed text, the preview can be `3970 + 41 = 4011` characters. This directly contradicts the R3 claim that message truncation was fixed. If Cove enforces the 4000-character message limit, the streaming preview edit/send can still fail, set `draftState.stopped = true`, and disable live preview for long outputs.

**Fix:** compute the suffix length instead of guessing:

```ts
const streamingSuffix = '\n\n… (streaming, full reply on completion)';
const preview = trimmed.length > COVE_TEXT_CHUNK_LIMIT
  ? trimmed.slice(0, COVE_TEXT_CHUNK_LIMIT - streamingSuffix.length) + streamingSuffix
  : trimmed;
```

Add a production-path test that feeds >4000 chars through `onPartialReply` and asserts every `sendMessage`/`editMessage` preview payload length is `<= COVE_TEXT_CHUNK_LIMIT`.

---

### 2. Critical — Previous R2 N3/N4 still unaddressed: actual outbound adapter drops `chunkerMode` and `deliveryCapabilities`

**Location:** `packages/plugin/src/channel.ts:81-90`, `packages/plugin/src/channel.ts:207-212`

`coveOutbound` declares the important SDK metadata:

```ts
const coveOutbound = {
  deliveryMode: "direct" as const,
  chunker: chunkTextForOutbound,
  chunkerMode: "markdown" as const,
  textChunkLimit: COVE_TEXT_CHUNK_LIMIT,
  deliveryCapabilities: { durableFinal: { ... } },
  sendText: async (ctx: any) => { ... },
};
```

But the plugin actually exposes only this subset:

```ts
outbound: {
  deliveryMode: "direct",
  sendText: coveOutbound.sendText,
  chunker: coveOutbound.chunker,
  textChunkLimit: coveOutbound.textChunkLimit,
},
```

So `chunkerMode: "markdown"` and `deliveryCapabilities` remain dead declarations. This was already called out in R2 as High; by the escalation rule, it is now Critical.

**Fix:** either expose the complete adapter directly:

```ts
outbound: coveOutbound,
```

or include the missing fields explicitly. Also add a test asserting `coveChannelPlugin.outbound.chunkerMode === "markdown"` and `coveChannelPlugin.outbound.deliveryCapabilities?.durableFinal?.text === true`.

---

### 3. Critical — Previous R2 N5 still unaddressed: chunk limit is duplicated and not resolved from effective channel config

**Locations:**

- `packages/plugin/src/channel.ts:79`
- `packages/plugin/src/dispatch.ts:28`
- Used in final fallback/chunking at `dispatch.ts:39`, streaming clamp at `dispatch.ts:129-130`, and final edit decision at `dispatch.ts:201`.

There are still two separate `COVE_TEXT_CHUNK_LIMIT = 4000` constants in different modules. More importantly, the dispatch path does not use the same effective outbound limit the SDK/config may use for delivery. If `channels.cove.textChunkLimit` or future account-specific limits are configured differently, then:

- preview streaming can still exceed the actual platform/configured limit,
- final short-vs-chunked decisions can be wrong,
- fallback chunking can disagree with the adapter's outbound delivery behavior.

This is the same category as R2 N5, so it escalates.

**Fix:** define one exported source of truth, or resolve the effective text chunk limit in `dispatchMessage` from config/account and pass it to preview/final/fallback paths. Then test that custom `channels.cove.textChunkLimit` is honored by both adapter delivery and draft/fallback delivery.

---

### 4. Critical — Previous C4 still not addressed: tests do not exercise production delivery behavior

**Locations:**

- `packages/plugin/src/dispatch-behavior.test.ts:222-245`
- `packages/plugin/src/edit-queue.test.ts:17-45`, `packages/plugin/src/edit-queue.test.ts:214-233`

The new `dispatch-behavior` tests do not actually invoke the wrapped `dispatchReplyWithBufferedBlockDispatcher`, `dispatcherOptions.deliver`, or `replyOptions.onPartialReply` callbacks. The two delivery-labeled tests only assert that a function exists:

```ts
expect(capturedDispatchParams.runtime.channel.reply.dispatchReplyWithBufferedBlockDispatcher).toBeDefined();
```

The edit queue and cleanup fallback tests use copied mini-reproductions rather than the real `dispatchMessage` implementation. One reproduction even disagrees with production behavior: the test helper deletes the draft before sending (`edit-queue.test.ts:215-222`), while production intentionally sends first then deletes (`dispatch.ts:38-45`). These tests would not have caught Finding 1, the missing adapter metadata in Finding 2, or config-limit drift in Finding 3.

**Fix:** add tests against the real wrapped runtime path:

1. Mock `originalDispatcher` so it captures `dispatcherOptions.deliver` and `replyOptions` from the patched runtime.
2. Call `replyOptions.onPartialReply({ text: longText })`, wait for draft flushing, and assert real `restClient.sendMessage/editMessage` calls.
3. Call `dispatcherOptions.deliver({ text }, { kind: "final" })` for short and long final text and assert final edit vs chunked send/delete behavior.
4. Assert adapter metadata on `coveChannelPlugin.outbound`.

---

## Non-blocking notes

- The R3 edit queue structure is materially better than R2: `let editQueue` plus `await draft.seal(); await editQueue` closes the primary late-partial race.
- `onCompactionStart` now refreshes the draft preview, which addresses the previous medium issue.
- The fallback order in production (`send` then `delete`) is reasonable for avoiding a no-message gap; the tests should be updated to match it.
