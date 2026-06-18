# Stella review — kagura-agent/cove PR #400

PR: https://github.com/kagura-agent/cove/pull/400  
Title: `refactor(plugin): adopt SDK outbound adapter framework, Discord parity (#398) — DRAFT`

## Verdict: ⚠️ Needs Changes

This is a useful refactor direction, and the added behavioral tests are a strong safety net. However, I found two behavior-preservation regressions in the inbound/final-send path. Since this PR is explicitly a refactor, these should be fixed before merge.

## Findings

### 1. Correctness — fresh/fallback final sends can target literal `channel:<id>` instead of the Cove channel id

- **Files/lines:** `packages/plugin/src/dispatch.ts:104-108`, `packages/plugin/src/channel.ts:47-50`, `packages/plugin/src/channel.ts:59-62`
- **Severity:** High

`freshSend()` now calls `sendDurableMessageBatch()` with `to: \`channel:${channelId}\`` and passes a `deps.cove` shim that strips the prefix. But this PR also registers `message: coveMessageAdapter` via `createChannelMessageAdapterFromOutbound()`. The SDK message path prefers the channel message adapter, which calls `coveSendText(ctx)` directly; it does not use the `deps.cove` shim.

`coveSendText()` then sends `ctx.to` as-is:

- `dispatch.ts:105` passes `channel:<id>`.
- `channel.ts:50` sends that value directly to `client.sendMessage(...)`.

Previously, the fallback/fresh-send path called `restClient.sendMessage(channelId, text)` with the raw Cove channel id. With this refactor, no-draft final replies and final-edit fallbacks can be posted to a non-existent/incorrect `channel:<id>` target.

**Why this matters:** this changes runtime behavior for exactly the failure/no-preview paths that the refactor is trying to preserve. It may be missed by current tests because `sendDurableMessageBatch` is mocked in `dispatch-behavior.test.ts` and the test only asserts that it was called, not which lower-level Cove target receives the send.

**Suggested fix:** normalize Cove targets in `coveSendText()` (strip `channel:` before calling `sendMessage`), or pass raw `channelId` from `freshSend()` if Cove does not require the OpenClaw target prefix. Add a test that exercises the real `coveSendText`/message-adapter path or asserts target normalization.

---

### 2. Correctness / Product Impact — inbound context no longer includes `ChannelId`

- **Files/lines:** `packages/plugin/src/dispatch.ts:155-169`
- **Severity:** Medium

The previous `dispatchInboundDirectDmWithRuntime()` call populated `extraContext.ChannelId` for the agent turn. The new `ctxPayload` includes `To`, `SessionKey`, `ChatType`, `SenderId`, and `SenderName`, but does not include `ChannelId`.

For a behavior-preserving refactor, this is a context contract change: prompts, tools, or downstream runtime code that expect `ChannelId` will stop seeing it even though the conversation is still a Cove channel turn.

**Suggested fix:** add `ChannelId: channelId` to `ctxPayload` and add/adjust a dispatch behavior test to assert that this context key is preserved.

## Category review

- **Correctness:** Needs changes due to the target-prefix regression and dropped `ChannelId` context key.
- **Security:** No new obvious credential exposure or permission expansion found in the changed plugin code. `allowUnsafeExternalContent` behavior for image URLs appears preserved.
- **Performance:** No major concerns. The refactor keeps batching/queueing and uses the SDK send path only for final fresh/fallback delivery.
- **Readability:** Mixed but acceptable for a migration PR. The extracted `build-context.ts` helpers are clear. `channel.ts` is much denser after compaction; future maintenance would benefit from keeping behavior-preserving code readable rather than highly compressed.
- **Testing:** Good breadth: `pnpm -F openclaw-cove test` reports 102 passing / 4 skipped, and `check` + `build` pass locally. Missing coverage for the real fresh-send target normalization and the full preserved context payload.
- **Product Impact:** If merged as-is, some agent replies in Cove can fail or land in the wrong target on no-preview/fallback sends, and agents may lose channel identity context.

## Local verification

Ran from `~/repos/forks/cove` with `https_proxy=http://127.0.0.1:1083`:

- `pnpm -F openclaw-cove test` ✅ 8 files passed, 102 tests passed, 4 skipped
- `pnpm -F openclaw-cove check` ✅ `tsc --noEmit`
- `pnpm -F openclaw-cove build` ✅ esbuild completed
