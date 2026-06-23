# Stella Review — Round 3 — kagura-agent/cove#418

Verdict: ⚠️ Needs Changes

## R2 re-check

1. `dispatch.ts:111` optional chaining silent no-op — ✅ Addressed in `6af55588`.
   - Current code explicitly guards `if (!outboundBridge.sendText) throw new Error(...)` before calling `sendText`.
2. Dead `sendDurableMessageBatch` import in `dispatch.ts` — ✅ Addressed in `6af55588`.
   - The import list no longer includes `sendDurableMessageBatch`.

R2 suggestions status:
- `cfg as any` remains in `sendCoveDurableBatch`.
- No adapter unit tests were added.
- `sendMedia` still logs and returns `{}` for media-only sends, which can look like success while dropping the media.

## Blocking findings

### 1. Typecheck fails in the new outbound helper

**Location:** `packages/plugin/src/outbound.ts:26-34`

The PR currently does not pass TypeScript checking. `sendCoveDurableBatch` passes `durability: "best_effort"` into `sendDurableMessageBatch`, but the installed SDK type for `DurableMessageBatchSendParams` does not accept a `durability` property.

Evidence from the current PR branch:

```text
$ pnpm -F openclaw-cove check
src/outbound.ts(33,5): error TS2353: Object literal may only specify known properties, and 'durability' does not exist in type 'DurableMessageBatchSendParams'.
```

There are other pre-existing/current check failures in `dispatch.ts` around `channel-outbound` types, but this one is directly in the newly added `outbound.ts` helper. Please update the call to the supported SDK API shape (or update the SDK dependency/types if the runtime API intentionally changed) so the plugin typecheck can pass.

## Non-blocking but should fix soon

### `sendMedia` should not silently succeed for unsupported media-only sends

**Location:** `packages/plugin/src/outbound.ts:60-70`

The adapter exposes `sendMedia`, logs that media is unsupported, sends only `text` if present, and then returns `{}` even when there is no text fallback. For a media-only payload this looks like a successful adapter call while the requested media is dropped.

Because `deliveryCapabilities.durableFinal` only declares `{ text: true }`, this is not advertised as a durable media capability, but the method is still present and callable. Safer options:

- omit `sendMedia` until Cove REST media upload exists; or
- throw/fail explicitly when `sendCtx.text` is empty; and only return success for the text-fallback path.

## Testing

Ran:

```text
export https_proxy=http://127.0.0.1:1083
pnpm -F openclaw-cove check
```

Result: failed, including the new `outbound.ts(33,5)` type error above.

## Summary

Round 2's two requested fixes were addressed. I still cannot mark this ready because the current PR branch fails TypeScript checking in the newly added outbound adapter helper. Once that is fixed, I would like to see at least a minimal unit test around `sendText` delegation and unsupported `sendMedia` behavior, but the immediate blocker is the compile error.
