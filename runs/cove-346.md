# Run Record: cove #346

- **PR:** kagura-agent/cove#346 — feat: NEW separator line and unread banner
- **Date:** 2026-06-13
- **Rounds:** 3

## Round 1
- **Verdict:** ⚠️ Needs Changes (unanimous)
- **Blockers:** 4 critical (NEW line unreachable, null lastReadId, banner persistence, Mark as Read no ack)

## Round 2
- **Verdict:** ⚠️ Needs Changes (unanimous, Vega ❌)
- **R1 criticals all fixed.** New blocker: O(N²) render regression (all 3 found)
- **Other new:** Unread count lies (Nova), pill positioning (Nova)

## Round 3
- **Verdict:** ✅ Ready (2-1: Nova ✅, Vega ✅, Stella ⚠️)
- **R2 blockers all fixed:** O(N²) hoisted, pill repositioned, "+" suffix added
- **Stella's remaining concern:** Stale cache freezing unread computation — valid edge case but recoverable, not blocking
- **Nova N3-1:** "+" suffix disappears after loading older history — good catch, low priority

## Reviewer Notes
- **Nova:** Consistently most thorough. Found unique issues in every round. Good at distinguishing blocker vs follow-up.
- **Stella:** Solid at tracing code paths and edge cases. Tends to block on theoretical concerns that others find acceptable.
- **Vega:** Clean and decisive. Correctly escalated O(N²) in R2, correctly downgraded in R3.

## Process Notes
- 3 rounds is the most for any cove PR so far. Spec doc commitment in R2 was a turning point.
- Human feedback: Pending
