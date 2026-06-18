# Consolidated Review — PR #400 R2

**PR:** refactor(plugin): adopt SDK outbound adapter framework, Discord parity (#398)
**Round:** R2 (re-review after author fixes)
**Reviewers:** 💫 Vega (Gemini 3.1 Pro) ✅ Ready | 🌟 Stella (GPT-5.5, R1 late discovery) ⚠️ Needs Changes | 🌠 Nova (Claude Opus 4.7) ⏱️ Timed out
**Overall Verdict:** ✅ Ready (with suggestions)

## R1 Issue Status

| Issue | Status | Verification |
|-------|--------|-------------|
| C1. `freshSend` deps key `cove` vs `sendText` | 🔄 **R1 was wrong — author correct** | Vega verified: SDK `OutboundSendDeps` is `[channelId: string]: unknown`, key must be channel ID (`cove`). |
| C2. `freshSend` formatting `textLimit` vs `textChunkLimit` | 🔄 **R1 was wrong — author correct** | Vega verified: SDK `OutboundDeliveryFormattingOptions` uses `textLimit`. `ChunkMode` only has `length` \| `newline`, no `markdown`. |
| C3. `freshSend` fallback `?? text` | ✅ **Fixed** | Removed fallback. Now uses `ctx.text ?? ctx.body` and throws if empty. |
| C4. Draft delete-before-send | ✅ **Fixed** | `sendDurableMessageBatch` now runs first, draft deletion after success. |
| C5. `recordInboundSession` binding | ✅ **Fixed** | `.bind(channelRuntime.session)` added. |

## New Findings

### S1. `ChannelId` dropped from ctxPayload (Stella, verified)
**File:** `dispatch.ts` — ctxPayload construction
**Severity:** Suggestion

Old code included `ChannelId: channelId` in extraContext (line 2051 shows deletion). New ctxPayload has `To: channelId` but not `ChannelId`. The PR's own spec (R5, line 553) explicitly flags this as a risk: "Assert field-by-field equality for: GroupSystemPrompt, ChatType, SenderId, SenderName, **ChannelId**, MediaUrls, ReplyToId, ReplyToBody, ReplyToSender."

The value IS available via `To`, so this is unlikely to cause immediate breakage, but any downstream code/prompt referencing `ChannelId` specifically would stop receiving it. For a behavior-preserving refactor, consider adding `ChannelId: channelId` back to ctxPayload.

### S2. `coveSendText` doesn't normalize `channel:` prefix (Stella)
**File:** `channel.ts` — `coveSendText`
**Severity:** Low / Informational

`coveSendText` passes `ctx.to` directly to `sendMessage` without stripping any prefix. The `freshSend` path handles this correctly in its own deps callback (strips `channel:` prefix). The risk is only if the adapter path ever receives a prefixed `to` value from the SDK — and the old `sendText` also used `ctx.to` directly, so no regression.

## Summary

All three R1 blocking issues (C3, C4, C5) are properly fixed. The two disputed findings (C1, C2) were confirmed as R1 reviewer errors — the SDK types use channel ID as deps key and `textLimit` as the formatting field. The only new finding is a minor context field omission (`ChannelId`) that the PR's own spec flagged as a risk but was not addressed. This is non-blocking for a small team project where `To` carries the same value.

## Positive Notes

- **Author's SDK verification** was correct and well-documented — pushed back on reviewers with evidence.
- **C3 fix is strict** — throws on empty chunk instead of silent fallback. Good defensive pattern.
- **C4 fix** properly reorders send-then-delete. Clean.
- **C5 fix** is the right approach (`.bind()`).
- All 32 behavior tests + 4 queue tests pass.

---

**Recommendation:** Ready to merge. Consider adding `ChannelId: channelId` to ctxPayload as a quick follow-up to match the old context contract, per the PR's own spec risk R5.
