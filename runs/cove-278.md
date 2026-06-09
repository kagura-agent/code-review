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

## Round 4
- **Date:** 2026-06-09
- **Verdict:** ⚠️ Needs Changes (1 lint blocker)
- **R3 cleanup:** Dead code removed ✅
- **New work:** Shared IntersectionObserver + explicit root + Date.parse
- **Stella:** ❌ — scrollContainerRef.current read during render (lint error, verified)
- **Nova:** ✅ Approve — noted same issue as non-blocking perf concern
- **Vega:** crashed (no output)
- **Consolidator verdict:** lint error is blocking (same class as R2#2)
- **Language:** English ✅

## Round 5
- **Date:** 2026-06-09
- **Verdict:** ✅ Ready to Merge (2/2 Approve, Stella timeout)
- **R4 blocker:** scrollContainerRef.current read during render → ✅ Fixed (callback ref + useState)
- **Nova:** ✅ Approve — thorough fresh review, all hook hygiene verified
- **Vega:** ✅ Approve — confirmed lint fix, listed follow-ups
- **Stella:** timeout (GPT-5.5 LLM request timed out)
- **All R1-R4 blockers resolved across 5 rounds**
- **Language:** English ✅
