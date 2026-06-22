# 🌠 Nova Review — cove#418

**PR:** refactor(plugin): define outbound message adapter with sendText/sendMedia (#401)
**Diff:** 2 files, +95/-10
**Rating:** ⚠️ Needs Changes (small, easy fixes; could also be argued as ✅ with follow-up issues, see below)

## Summary

Clean structural refactor that introduces `packages/plugin/src/outbound.ts` declaring a `ChannelMessageOutboundBridgeAdapter` for Cove with `sendText` and `sendMedia` capabilities, and rewires `dispatch.ts:freshSend` to call through it. The intent is good — moves Cove toward the declarative SDK pattern already used by `coveMessageAdapter` in `channel.ts`, and prepares the seam for real media support. The actual delivery path is unchanged (still `sendDurableMessageBatch` with identical args), which the PR description correctly claims. However the new file has a couple of real defects that warrant a small fix before merge: (1) `sendText` is declared on the bridge but called as `outboundBridge.sendText!(...)` in dispatch — the non-null assertion hides a contract that should be enforced; (2) the bridge return value reads `result.results` and `result.status === "sent"` — fine for the "sent" branch but it silently returns `messageId: undefined` for `partial_failed` (which also has `results`) and for the existing test mock shape `{ status: "sent", outcomes: [] }`, meaning the test mock and the production code now disagree on the result schema; (3) `deliveryCapabilities.durableFinal: { text: true, media: true }` declares media support that does not actually exist — this is a lie to the SDK capability layer.

## Critical Issues

### C1. `deliveryCapabilities.durableFinal.media: true` advertises a capability that is a stub (`packages/plugin/src/outbound.ts:39`)

```ts
deliveryCapabilities: {
  durableFinal: { text: true, media: true },
},
```

`sendMedia` logs a warning and falls back to text — it does not deliver media. Declaring `media: true` in `deliveryCapabilities.durableFinal` will mislead any SDK-level capability check / proof verification (`verifyDurableFinalCapabilityProofs`, `listDeclaredDurableFinalCapabilities`) and any caller that branches on "this channel supports media." If/when something upstream starts to rely on this declaration to e.g. attach a real image, Cove will silently drop the image and ship text. Set it to `media: false` (or omit) until the REST API actually supports uploads. This is the kind of stale-capability lie that PR #401 is supposed to fix, not introduce.

### C2. Result schema mismatch with existing test mock (`packages/plugin/src/outbound.ts:53,74` vs. `dispatch-behavior.test.ts:44`)

New code:
```ts
const messageId = result?.status === "sent" ? result.results?.[0]?.messageId : undefined;
```

Existing test mock (unchanged in this PR):
```ts
sendDurableMessageBatch: vi.fn(async () => ({ status: "sent", outcomes: [] })),
```

The SDK type (`DurableMessageBatchSendResult` in `channel-outbound-4IYEUpcr.d.ts:41`) actually defines `results: OutboundDeliveryResult[]` and `payloadOutcomes?` — there is no top-level `outcomes` field. So:
- In production: `result.results?.[0]?.messageId` may work, but if the result branch is `"partial_failed"` (which also carries `results`), `messageId` collapses to `undefined` even though a message was actually sent before the partial failure. Worth handling.
- In the existing test mock: `outcomes: []` was apparently a shorthand that the old inline call site never read; now the new bridge reads `result.results`, which is `undefined` in the mock, so `messageId` is `undefined`. Tests still pass only because nothing currently asserts on the returned `messageId`. This is a latent footgun: the first test that asserts on the receipt id will fail mysteriously.

Suggested fix: extend the read to also cover `"partial_failed"`, and either (a) update the test mock to use `results: [{ messageId: "stub" }]`, or (b) widen the type guard:

```ts
const sent =
  result?.status === "sent" || result?.status === "partial_failed";
const messageId = sent ? result.results?.[0]?.messageId : undefined;
```

(Optional but recommended given the SDK contract.)

### C3. `outboundBridge.sendText!` non-null assertion in dispatch (`packages/plugin/src/dispatch.ts:111`)

```ts
await outboundBridge.sendText!({ cfg, to: channelId, accountId, text });
```

`sendText` is `?:` optional on `ChannelMessageOutboundBridgeAdapter` (see SDK `channel-outbound-4IYEUpcr.d.ts:106`). The `!` works today because *this* concrete factory always sets it, but the assertion couples dispatch to that internal invariant and silently breaks if the adapter is ever refactored to construct conditionally. Two clean options:

- Make the contract local & non-optional. Either narrow the return type of `createCoveOutboundBridgeAdapter` to a stricter shape (`Required<Pick<ChannelMessageOutboundBridgeAdapter, "sendText" | "sendMedia">> & ChannelMessageOutboundBridgeAdapter`), or expose a thin `sendText(text)` method on a wrapper object so dispatch never sees the optional.
- At minimum, replace `!` with a guard: `if (!outboundBridge.sendText) throw new Error(...)`.

This is the kind of "trust me, it's there" the AGENTS validation-discipline rule warns about.

## Suggestions

### S1. `createCoveOutboundMessageAdapter` is dead code (`outbound.ts:86–91`)

The exported `createCoveOutboundMessageAdapter` is not imported anywhere in the diff or in the repo at this PR (`grep` shows zero callers). `channel.ts` still has its own inline `coveMessageAdapter` built with the local `coveSendText` (REST `sendMessage` directly, not durable). So the new "full adapter" export is YAGNI right now — a premature abstraction in service of a use case that hasn't shipped. Either (a) wire `channel.ts` to use it (which would unify the two parallel outbound paths, and is probably the real point of #401), or (b) drop it from this PR and add it in the PR that actually consumes it. Shipping unused factories accretes maintenance debt — this is the "premature abstraction" failure mode flagged in the review standard.

### S2. Two near-identical send blocks inside `sendMedia` and `sendText` (`outbound.ts:43–55, 64–76`)

The text-only delivery path is duplicated verbatim between `sendText` and the `sendMedia` fallback. Extract:

```ts
const sendTextBatch = async (sendCtx, text) => { /* sendDurableMessageBatch + messageId extract */ };
```

Small file so it isn't dramatic, but the duplication will rot — when result-status handling needs updating (see C2) you have to remember to fix both.

### S3. `cfg: sendCtx.cfg as any` (`outbound.ts:44, 65`)

The `as any` casts on `cfg` are because `ChannelMessageSendTextContext<unknown>` has `cfg: unknown`, but `sendDurableMessageBatch` wants a typed config. Two clean fixes:

- Parameterize: `ChannelMessageOutboundBridgeAdapter<CoveConfig>` where `CoveConfig` is the resolved Cove config type, so `sendCtx.cfg` is correctly typed downstream.
- Or, accept the `as any` but localize it behind a `resolveCfg(sendCtx.cfg)` helper.

`any` without justification is called out in the TypeScript-specific rules; both casts are easy to fix.

### S4. JSDoc says "stub pending REST API support" but never points at how to track it

Add a `// TODO(#401-or-issue-#XXX):` linking to the tracking issue, so the stub does not silently outlive its purpose. The `log?.warn?.(...)` is also fire-and-forget — consider returning a structured `{ supported: false }` or throwing on a flag, but at minimum keep the TODO discoverable via grep.

### S5. Log line in dispatch is now slightly less honest (`dispatch.ts:110`)

```ts
log?.info?.(`cove: reply → [${channelId}] (${text.length} chars)`);
```

This logs *before* the bridge call. If `sendText` becomes a no-op on a future capability/durability check, the log will lie. Move below the `await` (or rephrase to `cove: sending reply → ...`). Trivial.

### S6. `accountId ?? undefined`

Both branches do `accountId: sendCtx.accountId ?? undefined`. The original inline call used `accountId` directly (which was already `string | null | undefined` from `DispatchMessageOptions`). The `??` normalization is fine but make sure the `sendDurableMessageBatch` type actually wants `undefined` over `null` — if it accepts both, the change is noise.

## Positive Notes

- ✅ Honest scoping: PR description correctly says "structural refactor, no behavior change" and the delivery args (`channel`, `to`, `payloads`, `bestEffort`, `durability`, `session.key`) are byte-identical to the previous inline call. This is what a refactor PR should look like.
- ✅ Single source of truth for the session-key template — it's now in one place (well, two: text + media fallback, see S2) rather than re-keyed at the dispatch site.
- ✅ JSDoc on `outbound.ts` is genuinely useful: explains the relationship to the SDK pattern, the stub status of `sendMedia`, and the durability choice.
- ✅ Test count unchanged (111 still pass per PR body) — refactor preserved coverage of the dispatch-behavior tests that already mock `sendDurableMessageBatch`. The mock-shape drift (C2) is a separate problem, not a regression in coverage.
- ✅ `createCoveOutboundBridgeAdapter` is the right unit of testability — it can be instantiated with a stub `agentId` and `log` and exercised in isolation, which is exactly what the PR description claims.
- ✅ Direction is right: this moves Cove toward the same declarative outbound shape `channel.ts` is already using elsewhere. The eventual unification (S1) is the payoff.

## Verdict

⚠️ **Needs Changes** — small but real. The blockers are C1 (capability lie) and C3 (`!` non-null assertion). C2 is a latent test-mock drift that won't bite today but will burn whoever next asserts on the result. Suggestions are non-blocking polish. With C1 fixed (and ideally C2/C3), this is a clean refactor and ✅ ready.
