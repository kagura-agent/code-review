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

## Round 3
- **Date:** 2026-06-09
- **Verdict:** ✅ Ready to Merge (2/3 Approve, 1/3 Needs Changes)
- **R2 issues:** All 3 resolved ✅
- **Stella:** ✅ Approve — verified lint/tsc/build all pass, dead code warning noted
- **Nova:** ✅ Approve — detailed timing analysis of restoringRef, all fixes verified correct
- **Vega:** ⚠️ — escalated all R2 suggestions + dead code finding (cappedSetAdd unused)
- **Dead code verified:** cappedSetAdd/SET_CAP/SET_EVICT in MessageList.tsx unused (LazyMessageItem has own eviction)
- **Language:** English ✅
