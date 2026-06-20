# Consolidated Review: PR #410

**fix(plugin): use sendDurableMessageBatch for long message chunking (#391)**

## Reviewers

| Reviewer | Verdict |
|----------|---------|
| 🌟 Stella (GPT-5.5) | ⚠️ Needs Changes |
| 🌠 Nova (Claude Opus 4.7) | ✅ Ready |
| 💫 Vega (Gemini 2.5 Pro) | ✅ Ready |

## Overall Verdict: ✅ Ready

**2/3 Ready.** Stella's critical (draft deletion before batch send confirmation) is a valid observation but does not represent a regression — the old `restClient.sendMessage` path had the identical delete-then-send-with-possible-failure pattern, and the explicit `bestEffort: true` + `durability: "best_effort"` semantics indicate fire-and-forget intent (matching the Discord plugin). The SDK's durable batch sender handles retries internally. Downgraded to suggestion.

## Consensus Findings

All three reviewers agree:
- **Correct architectural choice** — delegates chunking to SDK's registered outbound adapter (`textChunkLimit: 4000`, `chunkerMode: "markdown"`), zero custom splitting logic
- **Session key is correct** — `agent:${targetAgent}:cove:group:${channelId}` matches `ctxPayload.SessionKey` and `routeSessionKey`
- **editFinal long-text fallback is the right fix** — prevents >4000 char edits from 400ing
- **Tests are thorough and behavioral** — assert on call shapes, lock boundaries, cover new paths

## Suggestions (non-blocking)

### S1 — Draft deletion ordering (Stella critical → downgraded)
`freshSend` deletes the orphan draft before `sendDurableMessageBatch`. If the batch send fails silently (returns `{ status: "failed" }` without throwing), both draft and replacement are lost. However: (1) the old code had the same delete-before-send pattern with `restClient.sendMessage`, (2) `bestEffort: true` + `durability: "best_effort"` explicitly communicate fire-and-forget semantics — the SDK retries internally, (3) the Discord plugin uses the identical pattern. Consider a follow-up to check the return status and restore/log on failure, but this is not a regression.

### S2 — OutboundSessionContext under-populated (Nova)
`freshSend` only sets `session: { key }`. The SDK context also accepts `policyKey`, `agentId`, `requesterAccountId`, etc. — omitting them means outbound policies (rate limits, media policy) won't resolve for chunked sends. Worth aligning with a `buildOutboundSessionContext()` helper in a follow-up.

### S3 — Redundant bestEffort + durability (Nova)
Both legacy `bestEffort: true` and newer `durability: "best_effort"` are set. SDK accepts either; pick one to avoid drift.

### S4 — editFinal → freshSend leaves adapter receipt state stale (Nova)
When editFinal falls back to freshSend for >4000 chars, the adapter caller perceives edit as succeeded but the old draft id is now deleted and N new messages exist. Any downstream code reading the "finalized" message id will hit a deleted message. Cosmetic in practice — consider routing through adapter's fallback channel.

### S5 — Preview truncation can split surrogate pairs (Nova)
`slice(0, 3999)` cuts at UTF-16 code units. For astral-plane chars this may produce a lone surrogate. Low impact (streaming previews are transient), but a `safeTruncate` helper would be more robust.

### S6 — Missing trailing newline in test file (Nova)
Minor lint nit.

### S7 — Boundary test for editFinal at exact limit (Nova)
Test I4 covers preview at 4000, but no test for `editFinal` at the `>` boundary (4000 vs 4001). Would lock in the strict-greater comparison.

## Positive Notes

- Tight scope: only dispatch file + its test file, no drive-by edits
- Mirrors established Discord plugin pattern exactly
- `lastSentText = trimmed` (full text, not preview) preserves correct dedup semantics
- Orphan cleanup retained in freshSend — important for recovery path
- No floating promises, no `any` regressions, no swallowed errors introduced
- PR closes a real user-facing bug (silent message deletion) with minimal risk
