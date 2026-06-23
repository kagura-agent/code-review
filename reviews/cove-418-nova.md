# 🌠 Nova — Round 3 Re-review (cove#418)

**Verdict: ✅ Ready (with non-blocking suggestions)**

Both R2 must-fix issues are addressed in commit 6af55588. No new defects introduced. Remaining items are the same non-blocking suggestions carried from R2.

---

## R2 issues — disposition

### 1. `?.` silent no-op on `sendText` — ✅ FIXED
**R2 ask:** Replace `outboundBridge.sendText?.()` with an explicit guard throw or narrowed type, so a regression in the adapter doesn't silently drop replies.

**Current code** (`dispatch.ts:111–112`):
```ts
if (!outboundBridge.sendText) throw new Error("cove: outbound adapter missing sendText");
await outboundBridge.sendText({ cfg, to: channelId, accountId, text });
```
Explicit guard with a loud throw — exactly the fix R2 asked for. The silent-drop failure mode is gone. ✅

**Tiny polish (not blocking):** the guard runs on every `freshSend` call. A `const send = outboundBridge.sendText; if (!send) throw …;` extracted once when `outboundBridge` is created would narrow the type cleanly and avoid the per-call check. Pure micro-tidy; leave as-is if you prefer.

### 2. Dead import `sendDurableMessageBatch` in `dispatch.ts` — ✅ FIXED
**R2 ask:** Drop the now-unused import after the helper moved to `outbound.ts`.

**Current code** (`dispatch.ts:5`):
```ts
import { createTypingCallbacks, deliverWithFinalizableLivePreviewAdapter, defineFinalizableLivePreviewAdapter } from "openclaw/plugin-sdk/channel-message";
```
`sendDurableMessageBatch` is no longer imported. ✅

---

## R2 suggestions — disposition (non-blocking)

### S2. `cfg as any` cast in `sendCoveDurableBatch` — ⚠️ STILL PRESENT (unaddressed)
`outbound.ts:27` still does `cfg: opts.cfg as any`, and the wrapper accepts `cfg: unknown`. This narrowly defeats type-checking for the most security/config-relevant parameter. Per the escalation rule I'm noting it as **still open**, not raising severity — the SDK's `sendDurableMessageBatch` signature is the proper fix surface, not this adapter. Acceptable to defer, but worth filing a follow-up if SDK types are reachable.

**Minimum-cost fix in this PR:** parameterize the helper as `cfg: Parameters<typeof sendDurableMessageBatch>[0]["cfg"]` and remove the cast. If SDK doesn't export the type, leave it and open a ticket.

### S4. No adapter unit tests — ⚠️ STILL OPEN
`outbound.ts` has zero direct test coverage. `dispatch-behavior.test.ts` exercises it indirectly. Two cases worth a focused test (small, mocked `sendDurableMessageBatch`):
1. `sendText` forwards `to / accountId / text` and builds the expected session key (`agent:${agentId}:cove:group:${to}`).
2. `sendMedia` with no text → logs warn, does **not** call `sendDurableMessageBatch`, returns `{}`.

Not blocking, but the adapter is the new contract surface — it should have its own test file.

### `sendMedia` silent success on media-only — ⚠️ STILL OPEN
```ts
async sendMedia(sendCtx) {
  log?.warn?.(`cove: sendMedia not yet supported…`);
  if (sendCtx.text) {
    await sendCoveDurableBatch({...});
  }
  return {};
}
```
Two behaviors I want to point out clearly:

- **Capability mismatch:** `deliveryCapabilities.durableFinal = { text: true }` advertises no media support, yet `sendMedia` is implemented. If the SDK gates dispatch by capability, this method is dead. If it doesn't, callers may invoke `sendMedia`, get `{}` (looks like success), and lose their media. Either:
  - **Remove `sendMedia`** entirely until the REST API supports it (cleanest — capability already says "no"), or
  - **Return a signaled-failure result** (e.g. `{ ok: false, reason: "unsupported" }` if the SDK result type allows), or at minimum **throw** when media is non-empty and text is absent.
- The warn-and-return-`{}` path silently drops media even on a media-only call. That's a soft data-loss failure mode for any caller that bypasses the capability check.

My preference: drop `sendMedia` from this PR. The capability already declares text-only; the stub is premature abstraction (per AI failure-modes checklist) and ships a quietly-lossy code path. Re-add it in the PR that implements REST media upload.

This wasn't blocking in R2 and I'm holding to that — but it's the single weakest spot in the diff and worth resolving before media support lands.

---

## Fresh review of new code (commit 6af55588)

### `outbound.ts`
- **Module shape:** clean separation, single responsibility, good doc comments. ✅
- **Session-key construction:** matches the pre-refactor call site exactly (`agent:${agentId}:cove:group:${to}`). Behavior-preserving. ✅
- **`accountId ?? undefined`:** correct null→undefined normalization for the SDK signature. ✅
- **`log` typed as `(...a: any[]) => void`:** loose but consistent with the surrounding plugin. Non-issue.
- **`CoveOutboundAdapterContext.agentId` is `string`:** good — no fallback that could produce `agent:undefined:cove:…` session keys.

### `dispatch.ts`
- `outboundBridge` is constructed once per `dispatchMessage` invocation. Fine — cheap. No leak; the bridge holds no resources beyond closure references.
- Closure captures `targetAgent` and `log` correctly. No stale-state risk across the abortable lifecycle.
- The throw on missing `sendText` will surface as an `cove: error in [${channelId}]: …` via the outer catch — same surfacing as other dispatch errors. ✅

### Correctness / Security / Performance
- **Correctness:** behavior-preserving for the existing text path. Verified by diffing the original `sendDurableMessageBatch` call against `sendCoveDurableBatch` — identical args.
- **Security:** no new data flows. `cfg as any` is a type-system concern, not a runtime one.
- **Performance:** one extra allocation (the adapter object) per dispatch. Negligible.
- **No floating promises**, no missing `await`, no resource leaks.

### API Design
- The capability/`sendMedia` mismatch (see above) is the only API-design wart. Everything else is idiomatic SDK-adapter shape.

### Product Impact
- Text reply path unchanged externally.
- Media calls (if any caller invokes them despite the capability) silently drop. Same risk surface as before — pre-PR there was no media support at all, so net-neutral, but the new code makes it look like there is.

---

## Summary

R2's two must-fix items are properly addressed. The remaining items are the same non-blocking suggestions from R2; I'm flagging them as still-open per the no-downgrade rule but not raising them to needs-changes — they don't gate this PR.

**Recommendation:** ✅ Approve and merge. Open a follow-up issue for:
1. Removing the `sendMedia` stub (or making it loud) until REST media support lands.
2. `outbound.ts` unit tests.
3. SDK-typed `cfg` to drop the `as any`.
