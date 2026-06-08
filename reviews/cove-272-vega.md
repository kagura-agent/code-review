# Review of kagura-agent/cove#272 - Round 3 (Vega)

## R2 Issues Check

### 🔴 Must Fix:
1. **Client count drift for other users** — ✅ Fixed. The server now calculates the exact `count` and broadcasts it in `MESSAGE_REACTION_ADD/REMOVE` payloads, and the client directly applies the absolute count instead of incrementing/decrementing.
2. **getUsersForReaction unbounded + N+1** — ✅ Fixed. Replaced with a single `JOIN` query against `users` table including `LIMIT 25` and `after` cursor support.

### 🟡 Should Fix:
3. **LRU eviction bug** — ✅ Fixed. `SentMessageTracker.add` correctly deletes and re-adds existing entries to refresh recency without evicting other items unnecessarily.
4. **React key collision** — ✅ Fixed. Updated to `key={r.emoji.id ?? r.emoji.name}` in `ReactionPills` component.
5. **Auto-scroll over-fires** — ✅ Fixed. Replaced object reference dependency with a primitive string `lastMsgReactionKey` derived from message ID and reaction count sum.

## Conclusion
All previously reported issues have been successfully addressed. The new code looks clean and solid. 
LGTM! Approved.