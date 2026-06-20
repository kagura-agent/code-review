# 🌠 Nova — Review of cove#410

**PR:** fix(plugin): use sendDurableMessageBatch for long message chunking (#391)
**URL:** https://github.com/kagura-agent/cove/pull/410
**Files:** `packages/plugin/src/dispatch.ts`, `packages/plugin/src/dispatch-behavior.test.ts`
**Verdict:** ✅ Ready (with non-blocking suggestions)

---

## Summary

Small, focused fix that closes the silent-deletion bug for >4000-char bot replies by routing both `freshSend` and the long-text `editFinal` fallback through `sendDurableMessageBatch`. The SDK then dispatches markdown-aware chunks back through the already-registered `coveSendText` outbound adapter (`textChunkLimit: 4000`, `chunkerMode: "markdown"` in `channel.ts`). Streaming previews are clamped to exactly 4000 chars (`slice(0, 3999) + "…"`) so the in-place edit no longer 400s while the final delivery is handled by the chunker. The change mirrors the established Discord plugin pattern, introduces no custom chunking logic, and adds five behavioral tests for the new paths plus updates to four existing ones. Integration with `OutboundSessionContext.key` is correct (matches `ctxPayload.SessionKey`).

---

## Critical Issues

_None._ No correctness, security, or data-loss issues found in the diff.

---

## Suggestions (non-blocking)

### S1 — `OutboundSessionContext` is under-populated
`freshSend` only sets `session: { key: ... }`. The SDK's `OutboundSessionContext` also accepts `policyKey`, `conversationType`, `agentId`, `requesterAccountId`, `requesterSenderId`, `requesterSenderName` — all used for silent-reply policy, rate limits, agent-scoped channel prefs, and outbound media policy. Omitting them means those policies will not resolve for chunked sends triggered by `freshSend`, which is a quiet behavior gap vs. paths that go through the standard delivery pipeline.

Consider using `buildOutboundSessionContext({ cfg, sessionKey, isGroup: true, agentId: targetAgent, requesterAccountId: accountId, requesterSenderId: senderId, requesterSenderName: senderName })` so policies apply uniformly. Discord's equivalent likely does this — worth aligning.

### S2 — `bestEffort: true` AND `durability: "best_effort"` both set
Passing both the legacy `bestEffort` boolean and the newer `durability: "best_effort"` is redundant. Not a bug (SDK accepts either), but worth choosing one to avoid future drift if one form is deprecated. Check what the Discord plugin uses and converge.

### S3 — `editFinal` → `freshSend` leaves adapter receipt state stale
When `editFinal` falls back to `freshSend` for >4000-char text, the `deliverWithFinalizableLivePreviewAdapter` caller perceives the in-place edit as succeeded (no throw). But `freshSend` has already deleted the draft and sent N new messages. Any receipt/state the SDK adapter persists keyed off the old draft id will be orphaned. Cosmetic in practice (the user sees the right messages), but if downstream code reads back the "finalized" message id it will hit a deleted message. Consider routing the long-text final path through `deliverNormally` / the adapter's fallback channel instead of swallowing inside `editFinal`, so the adapter's bookkeeping matches reality.

### S4 — Streaming preview truncation can split surrogate pairs / mid-code-fence
`trimmed.slice(0, COVE_TEXT_CHUNK_LIMIT - 1) + "…"` cuts at UTF-16 code-unit 3999. For text containing astral-plane chars (emoji, some CJK ext.), this may split a surrogate pair, producing a lone surrogate before the ellipsis. Also, if a fenced code block opens before 3999 and closes after, the preview renders as broken markdown. Streaming previews are inherently transient and the final is sent via SDK markdown chunking, so this is low-impact — but a small `safeTruncate` helper that respects code points (and ideally fence state) would be more robust. Not a blocker.

### S5 — Preview truncation boundary doc/test mismatch
PR description says "truncated to 3999 chars + …", but the actual implementation produces a 4000-char preview (3999 + 1 char ellipsis). Test I3 asserts `length === 4000`, matching code. Recommend updating the PR text to match the test/code for posterity.

### S6 — Test file missing trailing newline
`packages/plugin/src/dispatch-behavior.test.ts` ends without a final newline (`\ No newline at end of file` in the diff). Minor lint nit; harmless.

### S7 — No test for `editFinal` short-text success path being unchanged for streamed drafts after error
Test I5 covers short-text editFinal, but doesn't assert that the path *did not* take the chunking branch for borderline lengths (3999, 4000, 4001). I4 covers exact-4000 for the preview path but not for `editFinal`. A quick boundary test on `editFinal` at COVE_TEXT_CHUNK_LIMIT would lock in the `>` (strict) comparison.

---

## Positive Notes

- **Right architectural call:** zero custom chunking — delegates to the registered outbound adapter that already declares `textChunkLimit: 4000` + `chunkerMode: "markdown"`. This is exactly the "SDK handles splitting" guidance and matches Discord.
- **Session key is correct:** `agent:${targetAgent}:cove:group:${channelId}` matches `ctxPayload.SessionKey` and `routeSessionKey` further down in the same file — hooks will correlate per-turn state across agent-loop and delivery boundaries as documented in `OutboundSessionContext.key`.
- **`editFinal` long-text branch is the right fix** — without it, finals >4000 would still 400 even after the freshSend fix, because the adapter would otherwise edit-in-place. The fallback closes that hole.
- **Boundary is correct (`>` not `>=`):** at exactly 4000 chars the message is sent without truncation (server's limit, not below), avoiding unnecessary ellipses. Test I4 explicitly locks this.
- **Tests genuinely behavioral:** asserts on `sendDurableMessageBatch` call shape (channel/to/payloads), not just call count. The existing 4 tests were correctly updated (not removed) to match the new contract — no test deletion to hide regressions. `restClient.sendMessage` is also asserted *not* called in I1, locking out regression.
- **Orphan cleanup retained** in `freshSend` — important for the original bug's recovery path; test I1 + H6c still cover this.
- **`lastSentText = trimmed` (full text, not preview)** in `sendOrEdit` is the right choice for dedup — preserves correct dedup semantics even with preview truncation.
- **No floating promises, no `any` regressions, no swallowed errors introduced.** Error handling in `freshSend` is unchanged (relies on SDK to surface errors via its own state machine).
- **PR scope is tight:** only the dispatch file + its test file changed. No drive-by edits, no spec drift.

---

## Verdict: ✅ Ready

Real bug fixed, tests cover the new paths, no security or data-loss risk introduced, integration with SDK contracts looks correct. Suggestions S1 and S3 are worth tracking in follow-up issues (session-context completeness and adapter-state coherence on long-text fallback) but should not block this merge — they apply equally to the Discord plugin and are systemic, not regressions from this PR.
