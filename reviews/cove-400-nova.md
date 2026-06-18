# 🌠 Nova Review — PR #400 (cove)

**PR:** refactor(plugin): adopt SDK outbound adapter framework, Discord parity (#398)
**URL:** https://github.com/kagura-agent/cove/pull/400
**Verdict:** ⚠️ Needs Changes

## Summary

This PR claims to be "Phase 0 only — zero implementation changes," but the actual diff implements Phases 0 through 3: it rewires `dispatch.ts` from `dispatchInboundDirectDmWithRuntime` to a new `runInboundReplyTurn` adapter, replaces the orphan-cleanup helper with chunked `sendDurableMessageBatch`, extracts `build-context.ts`, and refactors `channel.ts` to `createChatChannelPlugin` + `createChannelMessageAdapterFromOutbound`. The behavioral test scaffolding (32 dispatch tests + 4 queue tests) is solid, but a few non-trivial correctness risks slipped in during the silent transition to "Phase 1–3 already done," and the code-density refactor of `channel.ts` regresses readability significantly. I judge by the diff, not the description.

## Critical Issues

### 1. `recordInboundSession` extracted without binding (`dispatch.ts`)
```ts
const recordInboundSession = channelRuntime.session.recordInboundSession;
...
recordInboundSession,
```
Pulling a method off `channelRuntime.session` as a bare reference loses `this`. If the SDK implementation is a class method (and not an arrow function or already pre-bound), the first internal `this.*` reference will throw. Fix: `channelRuntime.session.recordInboundSession.bind(channelRuntime.session)` or wrap with `(...args) => channelRuntime.session.recordInboundSession(...args)`. Tests do not cover this because `recordInboundSession` is a `vi.fn()`.

### 2. `runDispatch` payload shape diverges from the previous dispatcher contract (`dispatch.ts`)
Old call site spread the inbound params plus override:
```ts
originalDispatcher({ ...params, dispatcherOptions: {...}, replyOptions: {...} })
```
New call site:
```ts
runDispatch: () => originalDispatcher({ ctx: ctxPayload, cfg, dispatcherOptions, replyOptions })
```
The previous shape relied on `dispatchInboundDirectDmWithRuntime` to construct `params` (with runtime/route/peer/etc.) before delegating to `dispatchReplyWithBufferedBlockDispatcher`. Now we hand it a flat `{ ctx, cfg, dispatcherOptions, replyOptions }` and trust the SDK to be happy with that. The test mock makes this look fine because `dispatchReplyWithBufferedBlockDispatcher` is `vi.fn(...)`, so no actual contract is exercised. Please verify against the real SDK signature (or include an integration test) before merging — this is the easiest place for the refactor to silently break production.

### 3. `peer` / `senderAddress` / DM-ledger inputs dropped from the inbound call
The previous `dispatchInboundDirectDmWithRuntime` invocation passed `peer: { kind: "group", id: channelId }`, `senderAddress`, `recipientAddress`, `conversationLabel`, `provider`, `surface`, `extraContext`, `onRecordError`, `onDispatchError`. The new `runInboundReplyTurn` is given only `channel`, `accountId`, `raw`, and an adapter that returns `ctxPayload`. Several of those old fields (ChatType, SenderId, SenderName, etc.) are folded into `ctxPayload`, but `peer.kind`, `conversationLabel`, and the structured error hooks are not. If those drive DM-vs-group routing, security policy, or ledger recording in the SDK, the behavior change is silent. The `log` callback inside `resolveTurn` only handles `event.error`, but the old code distinguished record vs dispatch errors. At minimum, surface both classes of errors (`event === "recordError"` / `"dispatchError"`) to preserve logging fidelity.

### 4. `freshSend` `deps.cove` fallback can silently re-send the full text per chunk
```ts
deps: {
  cove: (ctx: any) =>
    restClient.sendMessage(ctx.to?.replace('channel:', '') ?? channelId,
                           ctx.text ?? ctx.body ?? text),
}
```
Two issues:
- `ctx.to?.replace('channel:', '')` assumes the SDK always uses the `channel:` prefix. If the SDK ever passes a bare id or a different prefix, the message is sent to the wrong channel (or to a literal id like `user:abc`). Use a stricter parser or assert the prefix.
- `?? text` falls back to the *entire* outer-closure text whenever the SDK chunk lacks both `text` and `body`. If chunking ever produces an empty/oddly-shaped payload, you re-send the full message once per chunk instead of erroring or skipping. Drop the `?? text` fallback (or `throw` with a descriptive message) so this fails loudly rather than spamming the channel.

### 5. Outbound adapter return shape changed (`channel.ts`)
Previous `outbound.sendText` returned `{ channel: "cove", messageId }`. The new `coveSendText` returns only `{ messageId }`, and the SDK adapter is constructed via `createChannelMessageAdapterFromOutbound({ id: "cove", outbound: { sendText: async (ctx) => coveSendText(ctx) } })`. If any SDK consumer (or the `attachedResults` machinery in `coveOutbound`) destructures the channel field from the response, it will now see `undefined`. Either restore `channel: "cove"` in the return value or confirm the SDK no longer needs it.

## Product Impact

- **Streaming edit-in-place** still appears preserved (the `draftMessageId` + `editMessage` path is intact), matching the "Hard constraint" in the PR description. ✅
- **Reconnect abort** behavior preserved in `channel.ts` (loop over `pendingDispatches` + `messageQueue.clearAll()`). ✅
- **Chunking** is now active for the fresh-send fallback. Previously, an oversized first-time reply would have been rejected by the REST API; now it splits. This is a real user-visible behavior change that the PR description doesn't call out.
- **Reaction notification log line** dropped the `tracked=...` field — minor observability regression.
- **PR is in "draft"** and only one phase is supposedly committed — but the diff says otherwise. Reviewers reading the description will under-estimate scope. Please update the PR body to reflect that Phases 1–3 are in-tree.

## Suggestions (non-blocking)

- **`channel.ts` density is hostile to readers.** Compressing every block into one-line statements (e.g. the `SentMessageTracker`, the resolver, the reaction handler) saves baseline lines but hurts maintainability. The Phase-3 baseline target (≤1662 lines) shouldn't be paid in legibility. Prefer real structural extraction (e.g. move resolver/reaction handler to their own files) over single-line packing. The blame view will be painful when something breaks.
- **`any` usage** in `build-context.ts` for attachments — once the shape is stable, define a `MessageAttachment` type in `@cove/shared` and replace the `(a: any)` filters/maps. Same in `dispatch.ts` `ctxPayload as any`.
- **Test fragility:** several tests use `await new Promise((r) => setTimeout(r, 50))` to wait for `dispatchMessage` to reach a state. Under CI load this can flake. Prefer awaiting a deterministic signal (e.g. resolve a `defer()` from inside the `runInboundReplyTurn` mock when it reaches `resolveTurn`).
- **`createTypingCallbacks` mock fidelity:** the mock returns `{ onReplyStart, onCleanup }`, but the real return object likely includes additional fields used in the dispatcher (e.g. `onReplyEnd`, `onError`). If dispatch.ts ever calls one of those, the test passes while production crashes.
- **`runDispatch` log callback** only handles `error`. Consider matching the old `onRecordError` / `onDispatchError` separation: `if (event.event === "recordError") log?.error?.("cove: record error..."); else if (event.event === "dispatchError") log?.error?.(...)`.
- **F4 / F8 deferred tests** — the rationale is fair, but please file a follow-up issue so they don't fall off the floor after Phase 3 lands.
- **`SPEC-398-DELTAS.md` duplicates content** — Phase 0.6 status block is followed by the original Phase 0 deltas table, with overlapping rows. Collapse to one source of truth before merge.
- **`pendingDispatches.set(channelId, abortController)`** — there's no read of the *previous* entry's abort handle (so a stale concurrent dispatch on the same channel keeps running in the background). The old behavior was the same, so this isn't a regression, but worth a TODO since `isCurrent()` only prevents UI side-effects, not the underlying SDK turn.

## Positive Notes

- **`build-context.ts` extraction** is exactly the kind of pure-function carve-out that makes the rest of the refactor easier to verify. Good comments tying each function back to original `dispatch.ts` line ranges.
- **`SPEC-398.md` / DELTAS** discipline is impressive — explicit contract coverage matrix, honest accounting of what's deferred and why, baseline pinned at a known commit. Most refactor PRs ship blind.
- **`message-queue.test.ts`** correctly tests the real `ChannelMessageQueue` class instead of mocking it. G1/G2/G4/G5 coverage is clean.
- **`guardFwd` helper** in `dispatch.ts` is a nice readability win — replaced ~7 `if (!isCurrent()) return;` prefixes with a single `guardFwd(fn)` wrapper. Apply the same pattern to `onPartialReply` and `onToolStart` for full consistency.
- **`createFinalizableDraftLifecycle`** adoption removes a non-trivial amount of bespoke draft-management logic — net win.
- **PR self-criticism** about #399 (`import → immediately delete` anti-pattern, editQueue race) shows good engineering discipline; the explicit "no commit simultaneously imports and deletes" rule for this branch is a useful guardrail.

---

**Recommendation:** Address the 5 Critical items (especially #1 binding, #2 dispatcher signature, #3 dropped inbound fields, and #4 silent-fallback in `freshSend`) before flipping out of draft. The test suite, while comprehensive at the unit level, cannot catch the contract-shape regressions in items #2/#3/#5 because the SDK boundary is fully mocked — a single integration smoke test against the real SDK would close that gap and unblock merge.
