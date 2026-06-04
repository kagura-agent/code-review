### Code Review: PR #179 (cove) - "scope gateway events by guild membership"

**1. Summary**
The PR successfully implements guild-based isolation for WebSocket gateway events. By scoping messages, typing indicators, and presence updates to `session.guildIds`, it resolves the security and privacy issue where authenticated users could receive events from guilds they were not members of, fully aligning the gateway behavior with the REST API.

**2. Critical Issues**
None. The security boundaries are correctly enforced. The `removeSession` logic smartly broadcasts the offline presence before fully deleting the session so that `getSessionGuildIds` can still resolve the user's shared guilds.

**3. Product Impact**
- **Enhanced Privacy**: Users only see events from their own guilds.
- **Dynamic Guild Membership Gap**: Because `session.guildIds` is only populated during the `IDENTIFY` payload on connection startup, if a user joins or leaves a guild while actively connected, their current session will not update. They won't receive live events for newly joined guilds until they reconnect (or conversely, will continue to receive events for a left guild). 

**4. Suggestions**
- **Dynamic Guild Updating**: Consider exposing methods like `session.addGuild(id)` and `session.removeGuild(id)`, and hooking them into the `GUILD_MEMBER_ADD` and `GUILD_MEMBER_REMOVE` flows so users don't need to refresh their clients when joining/leaving servers.
- **Broadcast Performance (O(N))**: `broadcastToGuild` currently iterates over *all* connected `sessions`. If concurrent connection count grows significantly, consider maintaining a `guildSessions` map (`Map<string, Set<GatewaySession>>`) to make broadcasts O(K) where K is members in the guild, rather than O(N) where N is total server connections.
- **Channel Lookup Overhead**: `resolveGuildForChannel` hits `channelsRepo.getById(channelId)` on every single message event. If this is a database call, it could become a performance bottleneck. Consider an LRU cache for `channelId -> guildId` mappings, or passing `guild_id` directly in the `Message` and `Channel` payloads if possible.

**5. Positive Notes**
- **Comprehensive Testing**: `gateway.test.ts` is excellently written. Validating the isolation boundaries (non-members not receiving, multi-guild users receiving both) provides strong confidence in this critical security path.
- **Clean Architecture**: Injecting `ChannelsRepo` into the dispatcher keeps the WebSocket layer decoupled and easily testable (as demonstrated by `mockChannelsRepo`).

**Rating**: ✅ Ready