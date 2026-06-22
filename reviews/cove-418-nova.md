# 🌠 Nova — Round 2 Review (PR #418)

**Repo:** kagura-agent/cove
**PR:** #418 — refactor(plugin): define outbound message adapter with sendText/sendMedia (#401)
**Round 1 verdict:** ⚠️ Needs Changes
**Round 2 verdict:** ⚠️ Needs Changes (one new minor issue + two unresolved suggestions; previous critical issues addressed)

---

## Round 1 Follow-up

### C1 — `deliveryCapabilities.durableFinal.media` must be `false` → ✅ Addressed
`outbound.ts:53` now declares only `durableFinal: { text: true }`. The `media` key is omitted entirely (commit `2d344af` claims explicit `false`, but omission is semantically equivalent for an optional `{ text?: boolean; media?: boolean }` shape — both read as falsy).

Minor nit: if the SDK type declares `durableFinal: { text: boolean; media: boolean }` (non-optional), omitting `media` will not satisfy the type. Worth confirming once with the SDK type def; if so, set `media: false` explicitly for clarity and type safety. **Not blocking** unless TS build complains.

### C2 — Result schema mismatch (`result.results?.[0]?.messageId`) → ✅ Addressed (vacuously)
The previously-flagged code path that read `result.results?.[0]?.messageId` lived inside the now-removed dead helper `createCoveOutboundMessageAdapter` (per commit `2d344af`, S3). The live `sendText`/`sendMedia` implementations don't read any messageId from the result — they return `{}`. The caller (`freshSend` in `dispatch.ts:111`) discards the return value entirely. No mismatch remains.

### C3 — `outboundBridge.sendText!` non-null assertion → ⚠️ Partially addressed; new minor issue
The bang is gone — `dispatch.ts:111` now uses optional chaining: `await outboundBridge.sendText?.({...})`.

**However**, optional chaining is the wrong fix for this site. `outboundBridge` is constructed three lines above (line 101) by `createCoveOutboundBridgeAdapter`, which **always** returns an object with `sendText` defined. The `?.` therefore silently no-ops a code path that the author actually wants to be unconditional. If a future refactor accidentally removes `sendText` from the returned adapter, every Cove reply would be silently dropped with no log, no throw, no draft cleanup signal — and the deleted draft above would leave the channel showing nothing.

**Recommended fix (one of):**
1. Destructure with a runtime check at adapter creation:
   ```ts
   const outboundBridge = createCoveOutboundBridgeAdapter({ agentId: targetAgent, log });
   if (!outboundBridge.sendText) throw new Error("cove: outbound adapter missing sendText");
   ```
   then call `await outboundBridge.sendText({...})` unconditionally.
2. Or narrow the local return type of `createCoveOutboundBridgeAdapter` to a subtype where `sendText` is required (e.g. `ChannelMessageOutboundBridgeAdapter & Required<Pick<ChannelMessageOutboundBridgeAdapter, "sendText">>`).

This is a small but real correctness concern — silent no-op on a delivery path is exactly the failure mode the original `!` was masking.

### S1 — Deduplicate sendText/sendMedia → ✅ Addressed
`sendCoveDurableBatch` helper extracted cleanly; both methods now share one delegation site.

### S2 — `cfg as any` casts → ⚠️ Not addressed (per escalation rule: bumped to Suggestion → still Suggestion; see note)
`outbound.ts:26` still has `cfg: opts.cfg as any`. The helper signature also uses `cfg: unknown`, so the lie is two-step (`unknown` → `any`). Per the re-review escalation rule this would normally bump to Critical, but I'm leaving it as a **Suggestion** because:
- It's a thin shim around an SDK call whose own `cfg` parameter is already loosely typed (the original line in `dispatch.ts` used `cfg: any` too).
- Fixing it properly requires either importing the SDK's `cfg` type or threading a generic — both legitimate cleanup, not bug fixes.

**Recommended:** type `cfg` as `Parameters<typeof sendDurableMessageBatch>[0]["cfg"]` (or import the SDK type) and drop the cast. If that's awkward, at minimum change the helper's `cfg: unknown` to `cfg: any` so the cast at the call site disappears — `unknown` → `any` is the worst of both worlds.

### S3 — Remove dead `createCoveOutboundMessageAdapter` → ✅ Addressed
Confirmed gone from `outbound.ts`. The exported surface is now exactly `CoveOutboundAdapterContext` + `createCoveOutboundBridgeAdapter`.

### S4 — Add unit tests for adapter → ⚠️ Not addressed (escalation declined — see note)
No new `outbound.test.ts`. Escalation declined to Critical because:
- `sendText` is exercised end-to-end through `dispatch-behavior.test.ts` (e.g. cases H4a, I1) — the test mocks `sendDurableMessageBatch` and asserts it's called with `channel: "cove"`, the right session key, etc. Coverage is indirect but real.
- `sendMedia` has **zero coverage**, including the silent-fallback-to-text branch.

**Recommended:** add a minimal `outbound.test.ts` with at least:
1. `sendText` calls `sendDurableMessageBatch` with `channel: "cove"`, the expected session key `agent:${agentId}:cove:group:${to}`, and `durability: "best_effort"`.
2. `sendMedia` with `text` present → calls `sendDurableMessageBatch` once with text payload, logs a warn.
3. `sendMedia` without `text` → does NOT call `sendDurableMessageBatch`, logs a warn.

Keeping this a Suggestion, but it's the most valuable follow-up.

### S5 — `TODO(#401)` for media stub → ✅ Addressed
Comment present at `outbound.ts:70`.

---

## New Issues (fresh review of the round-2 diff)

### N1 ⚠️ Dead import in dispatch.ts
`dispatch.ts:5` still imports `sendDurableMessageBatch`:
```ts
import { createTypingCallbacks, deliverWithFinalizableLivePreviewAdapter, defineFinalizableLivePreviewAdapter, sendDurableMessageBatch } from "openclaw/plugin-sdk/channel-message";
```
After the refactor, `sendDurableMessageBatch` is no longer referenced anywhere in `dispatch.ts` (it's only used inside `outbound.ts`). This is dead code — drop it from the import list. Linters with `no-unused-imports` will flag it; tsc with `noUnusedLocals` will too.

### N2 💡 (Suggestion) `sendMedia` silently degrades media→text without signaling caller
```ts
async sendMedia(sendCtx): Promise<ChannelMessageOutboundBridgeResult> {
  log?.warn?.(`cove: sendMedia not yet supported ...`);
  if (sendCtx.text) {
    await sendCoveDurableBatch({...});
  }
  return {};
}
```
The caller asked for media (with optional text caption); they get text-only delivery (or *nothing* if no text), and the return value `{}` looks like success. The result shape from `ChannelMessageOutboundBridgeResult` likely has a field for "partial delivery" or "unsupported feature" — using it would let upstream code surface a useful signal (e.g. retry to a different channel, or warn the user).

At a minimum, consider:
- Returning a result that indicates media was dropped (if the result type supports it), **or**
- Throwing a typed `UnsupportedMediaError` so the caller can choose to fall back rather than this method silently choosing for them.

Not blocking — the current behavior is "graceful degradation," and Cove is documented as text-only — but the silent-success return value is the same anti-pattern as `?.` in C3: hides a real condition.

### N3 💡 (Suggestion) `accountId` null vs undefined normalization
`outbound.ts:30`: `accountId: opts.accountId ?? undefined`. The call site (`dispatch.ts:111`) passes `accountId` (a `string`, always defined per the `DispatchMessageOptions` interface). The `?? undefined` guard is defensive but the type already says `string | null | undefined`, which is wider than what the call site actually passes. Tighten `CoveOutboundAdapterContext` / `sendCoveDurableBatch` to `accountId: string` since that's the only thing the bridge ever passes; or keep it loose if the adapter is meant to be reusable from other call sites (none currently exist).

---

## Style / Nits

- `outbound.ts:21` `log?: { warn?: ...; info?: ... }` — `info` is declared but unused in this file. Drop it, or commit to logging successful sends at info level. Right now neither path logs success.
- `outbound.ts:11-15` type-only imports are correctly using `import type` ✅.
- File-level docstring at top is excellent and survives the refactor accurately.

---

## Testing

- I ran `gh pr diff 418` and inspected the working tree at HEAD `2d344af`.
- Did **not** run `pnpm test` (subagent scope kept to read-only review). The previous round's tests in `dispatch-behavior.test.ts` continue to exercise the `freshSend` path (which now goes through `outboundBridge.sendText`), and the mock at line 44 returns `{ status: "sent", outcomes: [] }` — which is fine because nothing reads the return value. So the existing suite should still pass without modification.
- No new tests were added (S4 unresolved).

---

## Summary

The author addressed all three Round 1 Critical issues meaningfully:
- C1 ✅ via capability omission
- C2 ✅ vacuously (dead-code carrier removed)
- C3 ⚠️ technically fixed (bang gone) but `?.` introduces a different silent-failure mode

Two Round 1 Suggestions remain (S2 `any` cast, S4 adapter tests) — both reasonable to defer but worth tracking.

One genuinely new issue this round (N1 dead import) is trivial to fix and should land before merge.

**Verdict:** ⚠️ **Needs Changes** — small scope:
1. **Must fix:** N1 (drop unused `sendDurableMessageBatch` import in `dispatch.ts`).
2. **Should fix:** C3 follow-up (replace `?.` with an explicit narrowing/check at adapter construction).
3. **Nice to have:** S4 (3 unit tests for the new file).

If only N1 and C3 land, I'm happy with ✅ Ready on the next pass.
