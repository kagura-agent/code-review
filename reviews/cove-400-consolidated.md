# Consolidated Review — PR #400

**PR:** refactor(plugin): adopt SDK outbound adapter framework, Discord parity (#398)
**Reviewers:** 🌠 Nova (Claude Opus 4.7) ⚠️ Needs Changes | 💫 Vega (Gemini 3.1 Pro) ❌ Major Issues | 🌟 Stella (GPT-5.5) ⏱️ Timed out (partial)
**Round:** R1
**Overall Verdict:** ⚠️ Needs Changes

## Summary

This PR implements Phases 0–3 of the SDK outbound adapter migration: extracting `build-context.ts`, wiring `runInboundReplyTurn`, adding chunked delivery via `sendDurableMessageBatch`, and adopting `createChatChannelPlugin`. The spec discipline (SPEC-398.md, 32 behavioral contract tests, explicit baseline) is impressive. However, the `freshSend` path has multiple SDK contract mismatches that will break chunked message delivery in production, and the fully-mocked SDK boundary means these won't be caught by the existing test suite.

## Critical Issues

### C1. `freshSend` deps key mismatch — `cove` vs `sendText` (Nova + Vega consensus)
**File:** `dispatch.ts` freshSend function
```
deps: { cove: (ctx: any) => restClient.sendMessage(...) }
```
The PR's own spec (Section 3.3) and `channel.ts` outbound registration both use `sendText` as the key. The `coveMessageAdapter` (channel.ts) uses `outbound: { sendText: ... }`. But `freshSend` passes `{ cove: ... }`. If the SDK resolves deps by a fixed key (`sendText`), this will silently fail to deliver any chunked message.
**Confidence:** High — verified against PR's own spec and channel.ts outbound adapter.

### C2. `freshSend` formatting key mismatch — `textLimit` vs `textChunkLimit` (Vega, verified)
**File:** `dispatch.ts` freshSend function
```
formatting: { textLimit: COVE_TEXT_CHUNK_LIMIT }
```
But `coveOutbound.base` in `channel.ts` uses `textChunkLimit: COVE_TEXT_CHUNK_LIMIT` and `chunkerMode: "markdown"`. The freshSend path uses `textLimit` (wrong key) and omits `chunkerMode`. This means the SDK won't recognize the chunk limit, potentially sending the entire text as one chunk or using defaults.
**Confidence:** High — `coveOutbound.base` in the same PR contradicts `freshSend`.

### C3. `freshSend` silent fallback `?? text` will re-send full message per chunk (Nova)
**File:** `dispatch.ts` freshSend function
```
ctx.text ?? ctx.body ?? text
```
If the SDK chunk payload lacks both `text` and `body` (empty/malformed chunk), the fallback `?? text` sends the *entire* outer-closure `text` for that chunk. In a multi-chunk scenario, this means the full message gets sent N times. Should throw or skip instead of silently re-sending.
**Confidence:** Medium — depends on SDK chunk payload shape, but defensive coding principle says fail loud.

### C4. `freshSend` deletes draft before sending — message loss on send failure (Stella partial + verified)
**File:** `dispatch.ts` freshSend function
```
if (draftMessageId) {
  try { await restClient.deleteMessage(channelId, draftMessageId); }
  catch (...) { ... }
}
// ... then sendDurableMessageBatch
```
If `sendDurableMessageBatch` fails after the draft is deleted, the user sees nothing — draft gone, new message never sent. Consider sending first, then deleting the draft on success.
**Confidence:** Medium — the old `cleanupAndSend` may have had the same ordering, but worth fixing during refactor.

### C5. `recordInboundSession` method extracted without binding (Nova)
**File:** `dispatch.ts`
```
const recordInboundSession = channelRuntime.session.recordInboundSession;
```
Pulling a method reference off an object loses `this` context. If the SDK implementation is a class method (not an arrow function), internal `this.*` references will throw. Tests don't catch this because `recordInboundSession` is a `vi.fn()`.
**Confidence:** Medium — depends on SDK implementation. Safe fix: use `.bind()` or wrapper arrow function.

## Product Impact

- **Chunked message delivery is broken** — C1+C2 together mean any message >4000 chars going through `freshSend` will likely fail or not chunk correctly. This is new behavior (main doesn't chunk at all), so it's a regression from the PR's stated goal.
- **Streaming edit-in-place preserved** ✅ — The `draftMessageId` + `editMessage` path is intact.
- **Missing chunk limit check** (Vega) — No `text.length <= COVE_TEXT_CHUNK_LIMIT` guard before attempting `editMessage`. Messages >4000 chars will try edit first (API 400), catch, then fall back to `freshSend`. Adds latency + error log noise, but not data loss.
- **PR description says "Phase 0 only"** but diff includes Phases 0–3. Should update.

## Suggestions

1. **`channel.ts` density is hostile to readers** (Nova) — One-line compression of blocks saves baseline lines but hurts maintainability. Prefer real structural extraction over single-line packing.
2. **`any` usage** in `build-context.ts` attachments and `dispatch.ts` `ctxPayload as any` — define proper types once shape is stable.
3. **Test timing fragility** (Nova) — `setTimeout(r, 50)` waits in tests will flake under CI load. Prefer deterministic signals.
4. **`runDispatch` log callback** only handles `error` event — old code distinguished `onRecordError` vs `onDispatchError`. Consider preserving that fidelity.
5. **Dropped inbound fields** (Nova) — `peer.kind`, `conversationLabel`, and structured error hooks from old `dispatchInboundDirectDmWithRuntime` are not passed to `runInboundReplyTurn`. Verify the SDK doesn't need them for DM-vs-group routing or ledger recording.
6. **F4/F8 deferred tests** — file a follow-up issue so they don't get lost.
7. **SPEC-398-DELTAS.md** has overlapping content with SPEC-398.md — collapse before merge.
8. **Add chunk limit guard** before editMessage attempt — skip straight to `freshSend` for text > 4000 chars.

## Positive Notes

- **Spec-driven development** — SPEC-398.md with explicit contract coverage matrix, phase-by-phase plan, and honest accounting of what's deferred is exceptional discipline.
- **`build-context.ts` extraction** — Pure-function carve-out with comments tying each function back to original line ranges. Clean and verifiable.
- **32 behavioral contract tests** — Comprehensive coverage of dispatch behavior with clear naming (F1–F8).
- **`message-queue.test.ts`** tests the real `ChannelMessageQueue` class, not mocks. G1/G2/G4/G5 coverage is solid.
- **`guardFwd` helper** — Nice readability win replacing ~7 `if (!isCurrent()) return;` guards.
- **Learning from PR #399** — Explicit "no simultaneous import+delete" rule and documented failure modes from the previous attempt show good engineering discipline.
- **`createFinalizableDraftLifecycle` adoption** removes bespoke draft-management logic — net code reduction.

---

**Recommendation:** Fix C1 (deps key) and C2 (formatting key) — these are the blocking issues that will break chunked delivery. C3–C5 are important but lower risk. A single integration smoke test against the real SDK would close the contract-verification gap that lets C1/C2 slip through mocked tests.
