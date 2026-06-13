# Run Record: cove #346

- **PR:** kagura-agent/cove#346 — feat: NEW separator line and unread banner
- **Date:** 2026-06-13
- **Round:** 1
- **Verdict:** ⚠️ Needs Changes (unanimous)
- **Blockers:** 4 critical (NEW line unreachable for lastReadIdx=-1, no indicators for null lastReadId, banner persists on bottom-entry, Mark as Read doesn't ack)
- **Consensus rate:** High — all 3 found C1 (lastReadIdx=-1 rendering gap)
- **Nova standout:** Found all 4 blockers including the subtle banner-persistence on bottom-entry and the Mark as Read semantics gap. Most thorough analysis.
- **Stella standout:** Clean framing of the never-read channel edge case. Suggested explicit firstUnreadMessageId approach.
- **Vega standout:** Found batch pill counter bug (increment by 1 vs actual delta) and channel-switch race condition. Noted banner action discrepancy with PR description.
- **Architecture assessment:** Frozen-snapshot design is correct and well-documented. Issues are in edge case handling, not fundamental design.
- **Human feedback:** Pending
