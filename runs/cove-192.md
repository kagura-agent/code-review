# Code Review Run: cove PR #192

**Date:** 2026-06-05
**PR:** feat: read state & unread indicators
**Verdict:** ⚠️ Needs Changes (3/3 unanimous)

## Reviewers
| Reviewer | Model | Verdict | Runtime | Tokens |
|----------|-------|---------|---------|--------|
| Stella | GPT-5.5 | ⚠️ | 3m53s | 62k |
| Nova | Claude Opus 4.7 | ⚠️ | 3m42s | 43k |
| Vega | Gemini 3.1 Pro | ⚠️ | 4m31s | 24k |

## Consensus (3/3)
- C1: Unread lost on reload (readStates populated but unreadChannels reset)
- C2: No tests for ack endpoint / MESSAGE_ACK dispatch
- C3: Auto-ack race on channel switch (messages not loaded yet)

## Majority (2/3)
- C4: messageId not validated on ack endpoint (Stella + Nova)
- C5: No auto-ack for incoming messages in active channel (Stella + Vega)

## Unique Finds
- **Stella:** Detailed product impact analysis of auto-ack .catch(() => {}) silently swallowing failures
- **Nova:** FK cleanup story, READY payload growth concern, dead type alias, CONTRIBUTING.md bash fence issue, type-cast `server as any`
- **Vega:** Suggested moving auto-ack to channel view component for access to loading state

## Reviewer Assessment
- **Stella:** Strong product-impact reasoning. Identified all 3 consensus issues + unique persistence concern. Most thorough analysis of the "when does ack actually fire" flow.
- **Nova:** Most comprehensive — found all consensus + majority issues, plus 7 suggestions. File-by-file verdict useful. Best at surfacing non-obvious implications (READY payload growth, orphan rows).
- **Vega:** Concise and accurate. Hit all consensus issues. Fewer suggestions but each was actionable. Fastest to the point.

## Prompt Evolution
- No blind spots found — existing prompt dimensions (correctness, testing, input validation, product impact) covered all findings
- "Product Impact" dimension (added in previous evolution) proved valuable — all reviewers used it effectively for the reload/reconnect scenario

## Process Notes
- Stella's completion event didn't trigger a wake (had to check via subagents list) — minor process issue
- Total wall-clock ~5min for all 3 reviews — acceptable
- Review plan correctly flagged all high-risk files

## Round 2 (2026-06-05)

### R1 Resolution: All 5 Criticals Fixed ✅

### New Findings
- N1 (Vega): Own messages cause unread on reload — functional flaw
- N2 (Stella+Nova): Ack cursor monotonicity race
- N3 (Vega): Multi-device self-message sync
- N4 (Nova): Ack write amplification on mount
- N5 (Stella): Active-channel ack ignores viewport

### Verdict: 2/3 ✅ Ready, 1/3 ⚠️ Needs Changes → Consolidated ⚠️
- Vega caught a genuine new bug (N1) that Stella and Nova missed
- Nova most thorough again — file-by-file, multiple cleanup items
- Stella strongest on product-impact reasoning

### Reviewer Assessment Update
- **Vega**: R2 star — found the self-message unread bug that both other reviewers missed. Proves value of multi-model review.
- **Nova**: Consistent depth champion. N2 race analysis shows strong concurrent-systems reasoning.
- **Stella**: Solid but missed N1. Good viewport observation (N5).
