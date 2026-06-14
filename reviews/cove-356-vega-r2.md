# Code Review: PR #356 (Round 2)

**Reviewer:** Vega 💫
**Target:** kagura-agent/cove

## 1. R1 Issue Status
- 🔴 **Cross-channel sidebar bug**: ✅ **Fixed**. The client correctly checks `data.channel_id === activeChannelId` in `CHANNEL_FILE_CREATE`, `CHANNEL_FILE_UPDATE`, and `CHANNEL_FILE_DELETE` gateway event subscriptions (`gateway-subscriptions.ts`). This ensures file fetch triggers only happen for the channel currently being viewed.
- 🟡 **Cache unbounded**: ✅ **Fixed**. A proper LRU eviction strategy was added in `cove-md-cache.ts`. It correctly tracks `lastAccessedAt` and evicts the oldest entries when the cache exceeds `MAX_ENTRIES` (500).
- 🟡 **Other R1 Items (Deferred)**: The create-vs-update distinction was added (`channel-files.ts` now checks `repos.channelFiles.get` before upsert). In-flight deduplication and test coverage remain deferred as non-blocking optimization/maintenance tasks.

## 2. New Issues
None found.
- **Security Check**: `channelFileCreate`, `channelFileUpdate`, and `channelFileDelete` server dispatchers correctly use `broadcastToGuildWithChannelFilter` to prevent information disclosure (filenames, sizes) to members without channel access.
- **Resilience Check**: Negative caching is implicitly supported (if `cove.md` isn't found, `null` is cached, avoiding 404 spamming). On fetch error, stale cache is correctly returned.

## 3. Summary + Verdict
The author has successfully addressed the primary functional and security blockers from Round 1. The WS events now safely broadcast and only update the active client UI. The plugin cache is bounded and prevents memory leaks.

**Verdict**: ✅ **Ready**
