# Run Record: cove #339

- **PR:** kagura-agent/cove#339 — feat: @mention with autocomplete and highlight
- **Date:** 2026-06-13
- **Round:** 1
- **Verdict:** ⚠️ Needs Changes (unanimous)
- **Blockers:** 3 critical (replaceAll corruption, webhook skip, dangling autocomplete)
- **Consensus rate:** High — all 3 found C1, a11y, badge overflow
- **Unique finds:** Stella (webhook + MESSAGE_UPDATE ack), Nova (self-mention, mentionMapRef channel switch, type contract), Vega (onBlur dangling)
- **Notes:** Clean server architecture, good security posture. Client input handling is the weak spot.
- **Prompt changes:** None needed this round
- **Human feedback:** Pending
