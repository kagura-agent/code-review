# Code Review: PR #356 (cove)

## 1. Summary
This PR successfully introduces real-time file sidebar syncing via WebSocket events (`CHANNEL_FILE_CREATE`, `UPDATE`, `DELETE`) and implements a 60-second in-memory TTL cache for `cove.md` to optimize plugin dispatch latency. The implementation correctly hooks into existing permissions frameworks and state management.

## 2. Critical Issues
None. The code is structurally sound and securely implemented.

## 3. Product Impact
- **Positive UX**: Users will see file changes instantly in the channel files sidebar without needing to manually refresh.
- **Performance Boost**: Bot message dispatch latency will noticeably decrease since `cove.md` context fetches are now cached in-memory with a 60s TTL, avoiding repeated network trips.
- **Resilience**: The stale-while-error fallback in `getCoveMd` ensures bots can still respond even if a transient error occurs during context fetching.

## 4. Suggestions
- **Potential Minor Memory Leak in Cache**: `cove-md-cache.ts` uses a standard `Map` to store cache entries. While keys are deleted explicitly on WS invalidation events, channels that are accessed once and never receive a `cove.md` update will remain in the `Map` indefinitely. For a long-running production server with thousands of channels, this could cause memory to slowly accumulate. **Recommendation (Non-blocking):** Consider using a lightweight LRU cache (like `lru-cache`) or running a periodic `setInterval` to prune expired entries from the map.
- **Buffer Import**: `Buffer.byteLength` is used in `cove-md-cache.ts` without explicit imports. While this works in Node.js environments due to `Buffer` being a global, relying on explicit imports (`import { Buffer } from "node:buffer";`) is generally a safer long-term practice for TS projects.

## 5. Positive Notes
- Event broadcasting securely utilizes `broadcastToGuildWithChannelFilter` to ensure private channel files don't leak metadata to unauthorized guild members.
- Great use of the `dispatcher` optional dependency injection pattern in `channelFilesRoutes`.
- Stale-cache-on-error implementation is a great resiliency pattern for bot operations.

**Rate:** ✅ Ready
