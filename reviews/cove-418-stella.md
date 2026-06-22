# 🌟 Stella — Round 2 Re-review: kagura-agent/cove#418

Verdict: ⚠️ Needs Changes

I re-read the current PR diff plus `packages/plugin/src/outbound.ts` and `packages/plugin/src/dispatch.ts`. I also checked the existing plugin integration in `packages/plugin/src/channel.ts` because this PR claims to define the outbound message adapter. Local verification passed:

- `pnpm -F openclaw-cove check` ✅
- `pnpm -F openclaw-cove test -- outbound dispatch-behavior.test.ts` ✅ (Vitest pattern also ran the existing plugin suite; 111 passed, 4 skipped)

## Previous Round Items

### C1: `deliveryCapabilities.durableFinal.media: true` while `sendMedia` is a stub
Status: Addressed for the declared durable capability.

`outbound.ts` now declares only:

```ts
deliveryCapabilities: {
  durableFinal: { text: true },
}
```

So the adapter no longer advertises durable media support. The `sendMedia` stub also has a `TODO(#401)`.

Caveat: `sendMedia` still exists and returns success `{}` after dropping media-only sends. This is acceptable only while the bridge is not exposed as the registered channel adapter. If it is wired into `createChannelMessageAdapterFromOutbound`, media-only calls would appear successful while sending nothing.

### C2: Result schema mismatch (`result.results?.[0]?.messageId` vs mock `{ status, outcomes }`)
Status: Addressed for the current dispatch path.

The current code no longer reads `result.results?.[0]?.messageId`; `sendCoveDurableBatch` awaits `sendDurableMessageBatch` and `sendText` returns `{}`. Existing dispatch tests pass with the current mock.

Caveat: as an outbound bridge API, returning `{}` discards receipts/message IDs from `sendDurableMessageBatch`. That is not a regression in `dispatch.ts`, but it will matter if this bridge is registered as a framework message adapter.

### C3: `outboundBridge.sendText!` non-null assertion on optional SDK field
Status: Mostly addressed.

The non-null assertion is gone. Current code uses optional chaining:

```ts
await outboundBridge.sendText?.({ cfg, to: channelId, accountId, text });
```

This avoids the unsafe assertion. A stronger shape would be better because `freshSend` should not silently no-op if `sendText` is ever absent, but the current factory does return `sendText`, so I am not blocking on this alone.

### S1: Deduplicate `sendText`/`sendMedia` internals
Status: Addressed.

`sendCoveDurableBatch` centralizes the shared durable send logic.

### S2: `cfg as any` type casts
Status: Not addressed → escalated per Round 2 rule.

`outbound.ts` still has:

```ts
cfg: opts.cfg as any,
```

The helper accepts `cfg: unknown` and then casts to `any` at the SDK boundary. This is exactly the previous concern and remains unjustified. Please type the adapter/helper against the SDK config type expected by `sendDurableMessageBatch` instead of erasing it. If importing the concrete `OpenClawConfig` type is undesirable, use the SDK generic consistently so the type relationship is explicit rather than hidden behind `any`.

### S3: `createCoveOutboundMessageAdapter` dead code — remove or wire in
Status: Partially addressed.

The new factory is now used by `dispatch.ts` for `freshSend`, so it is no longer completely dead. However, it is still not wired into the registered Cove channel message adapter (see Critical issue below).

### S4: Add unit tests for adapter
Status: Not addressed → escalated per Round 2 rule.

There is still no dedicated test for `createCoveOutboundBridgeAdapter` / `sendMedia` / `deliveryCapabilities`. Existing `dispatch-behavior.test.ts` covers the fresh-send path indirectly through `sendDurableMessageBatch`, but it does not verify the adapter contract:

- `deliveryCapabilities` must not advertise media.
- `sendText` must call durable send with the expected Cove defaults/session key.
- `sendMedia` must not pretend media delivery succeeded, especially for media-only sends.
- returned bridge results/receipts should be intentional.

For a PR whose main artifact is an outbound adapter, this needs direct unit coverage.

### S5: Add TODO(#401) link for media stub
Status: Addressed.

`sendMedia` includes `TODO(#401)`.

## Critical Findings

### 1. The new outbound bridge is not wired into the registered Cove channel adapter

`dispatch.ts` now uses `createCoveOutboundBridgeAdapter` for the inbound final fresh-send path, but `channel.ts` still registers the channel message adapter with the old inline text-only bridge:

```ts
const coveMessageAdapter = createChannelMessageAdapterFromOutbound({
  id: "cove",
  outbound: { sendText: async (ctx: any) => coveSendText(ctx) },
});
```

And `coveOutbound` remains:

```ts
attachedResults: { channel: "cove", sendText: coveSendText },
```

Product/API impact:

- The PR title says it defines an outbound message adapter with `sendText`/`sendMedia`, but the plugin's registered message adapter is still text-only.
- Framework auto-delivery / external outbound paths will not see the new `deliveryCapabilities` or `sendMedia` behavior.
- The new bridge is only used as a local helper inside `dispatch.ts`, not as the Cove channel's outbound adapter contract.

Please either wire the new bridge into the registered channel adapter, or narrow the PR claim/scope to “refactor dispatch fresh-send through a helper”. As written, the main adapter API is not actually adopted by the channel.

### 2. `sendMedia` can silently drop media-only sends while returning success

Current `sendMedia` logs a warning, optionally sends fallback text, and then returns `{}`:

```ts
if (sendCtx.text) {
  await sendCoveDurableBatch(...);
}
return {};
```

For media-only input, this sends nothing and still resolves successfully. If/when this bridge is wired into `createChannelMessageAdapterFromOutbound`, callers may observe a successful `send.media` result even though no media or text was delivered.

Given media support is explicitly not available yet, safer behavior is one of:

1. Do not expose `sendMedia` until Cove REST supports it; keep only `durableFinal: { text: true }` and `sendText`.
2. If `sendMedia` must exist as a stub, return/throw a failure for media-only sends so the framework cannot treat dropped content as delivered.
3. Only allow text fallback when text is present, and make the return value clearly represent the text send receipt rather than `{}`.

## Non-blocking Notes

- The header comment still says “Declares sendText and sendMedia capabilities,” which is now misleading because durable media capability is intentionally not declared. Consider changing it to “methods” or explicitly saying media is not advertised as durable capability yet.
- `sendText` currently discards the `sendDurableMessageBatch` result and returns `{}`. That preserves current dispatch behavior, but it is a weak bridge result if this becomes the actual message adapter.

## Recommendation

Block this round until the adapter integration and adapter tests are fixed. The Round 1 critical runtime issues are mostly addressed, but the new adapter is still not the channel's registered adapter, and the media stub can report success after dropping content.
