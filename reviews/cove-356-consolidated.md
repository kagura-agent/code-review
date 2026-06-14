# PR #356 Consolidated Review — `feat: WS events for channel files + cove.md plugin cache`

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)

---

## 🔴 Critical — Client file sidebar refreshes wrong channel's files (Stella)

**File:** `packages/client/src/lib/gateway-subscriptions.ts:221-245`

The WS event handlers check only `store.filesOpen`, then call `fetchFiles(data.channel_id)`. Gateway broadcasts events for any visible channel in the guild. A user with the sidebar open on channel A can receive a file event for channel B — the handler will load channel B's file list into the store, corrupting channel A's sidebar.

**Fix:** Compare `data.channel_id` with the current active channel before mutating the store. Ignore events for other channels.

---

## Consensus Findings

### 🟡 No tests for new features (Nova + Stella)

No tests for:
- WS event dispatch (channelFileCreate/Update/Delete)
- Bot permission filtering on file events
- cove-md-cache (TTL, stale-on-error, invalidation)
- Client subscription behavior

Nova suggests extending existing `channel-files.test.ts` and adding `cove-md-cache.test.ts`.

### 🟡 Unbounded cache Map growth (All 3)

`Map<channelId, CacheEntry>` never prunes stale entries. Long-running bots across many channels accumulate entries. Suggest LRU cap or periodic pruning.

---

## Suggestions (non-blocking)

- **Create-vs-update race** — Two concurrent PUTs for new file both see `existing=null`, both emit CREATE (Nova)
- **No in-flight dedup** — Cold-cache burst fires parallel fetches for same channel (Nova)
- **`cove.md` filename constant** — Magic string repeated across files (Nova)
- **No-op PUTs still broadcast** — Consider short-circuiting (Nova)
- **Stale-on-error retry noise** — Every dispatch after TTL retries 2s fetch + logs warning; consider backoff (Stella)

---

## Positive Notes (unanimous)

- ✅ **Perfect pattern mirroring** — channelFileCreate/Update/Delete mirrors messageCreate/Update/Delete exactly
- ✅ **Permission filtering reused** — `broadcastToGuildWithChannelFilter` means no new permission code paths, no leak risk
- ✅ **Stale-on-error cache** — thoughtful resilience for transient failures
- ✅ **Clean 3-function cache API** — getCoveMd, invalidateCoveMd, invalidateAllCoveMd
- ✅ **dispatch.ts leaner** — 11 lines of inline fetch replaced by 1-line cached call
- ✅ **End-to-end cache coherence** — WS event → invalidate → next dispatch fresh
- ✅ **Client `filesOpen` guard** — no wasted refreshes when sidebar closed
- ✅ **Backward compatible** — `dispatcher?` optional parameter

---

## Verdict Summary

| Reviewer | Rating | Key Concern |
|----------|--------|-------------|
| 🌟 Stella | ⚠️ Needs Changes | Cross-channel sidebar corruption |
| 🌠 Nova | ⚠️ Needs Changes (soft) | Missing tests |
| 💫 Vega | ✅ Ready | No blocking issues |

### Overall: ⚠️ Needs Changes

The cross-channel sidebar issue (Stella) is a real bug — events for channel B can overwrite channel A's file list. One-line fix: gate on active channel ID. The missing tests are the other concern.

**Before merge:**
1. Gate client WS handlers on active channel ID
2. Add basic tests (WS dispatch + cache)

**Can defer:**
3. Cache LRU/pruning
4. In-flight dedup
5. Create-vs-update race
