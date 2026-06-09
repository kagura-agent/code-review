# cove#278 — MessageList scroll rewrite
- **Date:** 2026-06-09
- **Round:** 1
- **Verdict:** ⚠️ Needs Changes (3/3)
- **Stella:** ⚠️ — deep-history restore fragile, channelSwitchRef RAF timing
- **Nova:** ⚠️ — channelSwitchRef dead code (detailed), deep-history restore, comprehensive suggestions
- **Vega:** ⚠️ — scroll listener not attached on first visit (unique find)
- **Consensus issues:** deep-history restore (2/3), channelSwitchRef dead code (2/3)
- **Unique finds:** Vega found scroll listener attachment bug (strong, verified)
- **Language:** English (new rule applied)
- **Ground truth:** pending

## Round 2
- **Date:** 2026-06-09
- **Verdict:** ⚠️ Needs Changes (3/3)
- **R1 issues:** All 3 resolved ✅
- **New blocking:** stale-cache clobber (Nova+Stella), lint error (Stella, verified), unbounded state (3/3 escalated)
- **Stella unique:** lint failure on ref mutation during render — verified real
- **Nova unique:** pendingScrollToBottomRef cross-channel race, detailed restoringRef timing analysis
- **Language:** English ✅
