## Summary

The refactor keeps the existing dispatch text-send path behaviorally equivalent: `dispatch.ts` now delegates final text replies through a Cove outbound bridge, and local validation passes (`pnpm -F openclaw-cove check`; `pnpm -F openclaw-cove test`, 111 passed / 4 skipped). The main problem is in the new adapter contract rather than the current dispatch call site: it advertises durable media support even though `sendMedia` explicitly discards the media URL and only sends optional text. That makes the new exported adapter unsafe to wire into framework auto-delivery as-is.

## Critical Issues

- **`packages/plugin/src/outbound.ts:37-40`, `57-77` — Media capability is declared but media is not delivered.** `deliveryCapabilities.durableFinal` includes `{ media: true }`, but `sendMedia` logs that media is unsupported, ignores `sendCtx.mediaUrl`, sends only `sendCtx.text` when present, and returns `{}` for media-only sends. Once `createCoveOutboundMessageAdapter()` is used by framework auto-delivery/capability checks, Cove can be selected as media-capable and then silently drop the attachment. This violates the durable final capability contract and creates user-visible data loss for media payloads. Fix by not declaring `media: true` until Cove can actually upload/send media, or make `sendMedia` fail/return an explicit unsupported result and keep media out of durable capabilities until implemented.

## Suggestions

- **Add focused tests for the outbound adapter.** The current plugin suite passes, but there are no direct tests for `createCoveOutboundBridgeAdapter`/`createCoveOutboundMessageAdapter`. A small test should assert the declared capabilities and that text delivery delegates to `sendDurableMessageBatch`; if media remains a stub, assert that it is not advertised as supported.
- **Consider returning the durable `receipt` from `sendDurableMessageBatch`.** `sendText`/text fallback currently return only `{ messageId }`; the SDK bridge can synthesize a receipt from that, but the durable send result already has a richer `receipt`. Returning it would preserve more lifecycle metadata for future message-adapter use.
- **Reduce the local `any` usage if practical.** `sendCtx.cfg as any` and `log?: (...a: any[])` are not causing a compile failure, but the adapter could likely be typed against the actual OpenClaw config/logger types or a narrower `unknown[]` logger signature.
- **Optional cleanup:** the `sendDurableMessageBatch` call is duplicated between `sendText` and the text fallback in `sendMedia`; a tiny private helper would make future changes to session/durability parameters less error-prone.

## Positive Notes

- The dispatch refactor is minimal and keeps the existing final text-send parameters (`channel`, `to`, `accountId`, `bestEffort`, `durability`, session key) intact.
- The new adapter boundary is a reasonable direction for moving Cove toward declarative outbound delivery.
- Typecheck and the plugin test suite both pass locally.

Rate: ⚠️ Needs Changes
