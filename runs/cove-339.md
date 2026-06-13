# Run Record: cove #339

- **PR:** kagura-agent/cove#339 — feat: @mention with autocomplete and highlight
- **Date:** 2026-06-13
- **Rounds:** 2

## Round 1
- **Verdict:** ⚠️ Needs Changes (unanimous)
- **Blockers:** 3 critical (replaceAll corruption, webhook skip, dangling autocomplete)
- **Consensus rate:** High — all 3 found C1, a11y, badge overflow

## Round 2
- **Verdict:** ✅ Ready (2-1 split: Nova ✅, Vega ✅, Stella ⚠️)
- **All R1 criticals fixed:** replaceAll → regex+boundary, webhook → resolveMentions, onBlur → 150ms delay
- **Split:** Stella raised 2 new blockers (non-numeric IDs, MESSAGE_UPDATE still broken) — Nova and Vega disagreed on both
- **Resolution:** 2-1 majority = Ready. Non-numeric ID issue needs verification. MESSAGE_UPDATE appears fixed per Nova's detailed analysis of active-channel guard.
- **Remaining non-blocking:** a11y (escalated 3x), trigger regex, no tests, useMemo, Set cap
- **Recommendation:** Merge + file follow-up tracking issue

## Reviewer Notes
- **Stella:** Most thorough on edge cases, found valid non-numeric ID concern, but may over-flag on MESSAGE_UPDATE
- **Nova:** Best at verifying fixes with code-level detail, balanced verdict
- **Vega:** Concise and accurate, good at confirming fixes without over-flagging

## Ground Truth

- **Human reviewer:** daniyuu
- **Human verdict:** Approved (no findings)
- **Our R1 verdict:** ⚠️ Needs Changes (3/3 unanimous)
- **Our R2 verdict:** ✅ Ready (2-1: Nova ✅, Vega ✅, Stella ⚠️)
- **Accuracy:** Correct — all R1 criticals were real bugs, fixed before merge
- **Blind spots:** None — human approved without independent findings
- **Effective dimensions:** replaceAll-mention-corruption, webhook-mention-resolution, dangling-autocomplete-global-keys, mention-badge-active-channel, mention-count-cap
- **Noise:** Stella R2 over-scoped on non-numeric user IDs (unverified assumption) and MESSAGE_UPDATE badge (overruled 2-1 by Nova+Vega)
- **Calibration:** Iterative review was the quality gate. Human rubber-stamped.

### Unique finds per reviewer
- **Stella:** Webhook mentions skip (R1, unique), MESSAGE_UPDATE active-channel badge (R1, unique)
- **Nova:** Self-mention highlight on own message, mentionMapRef channel-switch leak, MessageItem new Map() per render, Message.mentions type contract, mention_count not decremented on delete
- **Vega:** No onBlur → dangling autocomplete steals global keys (R1, unique)

## Process Notes
- Re-review protocol worked well — previous review included, escalation rules followed
- Human approved after R2 without comments
