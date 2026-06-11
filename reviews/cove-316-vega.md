1. **Summary**: 
This PR introduces the foundation for Discord-compatible channel permission overwrites, focusing on an MVP to control bot visibility. The schema migrations, repository methods, and UI components are well-structured and clearly implemented. However, the PR is missing critical enforcement on the REST API side and lacks authorization checks for modifying permissions, meaning it does not fully secure channels or protect against unauthorized permission changes.

2. **Critical Issues**:
- **Incomplete Access Control (REST API bypass)**: The `VIEW_CHANNEL` filtering is only implemented in `packages/server/src/ws/dispatcher.ts`. This prevents bots from receiving live WebSocket events, but does not stop them from interacting with the channel via REST. Bots without permission can still fetch history (`GET /channels/:id/messages`), send messages (`POST /channels/:id/messages`), and discover the channel (`GET /guilds/:id/channels`). Access control must be enforced in the REST routes or repository layer.
- **Privilege Escalation (Missing Authorization Check)**: In `packages/server/src/routes/permissions.ts`, the `PUT` and `DELETE` endpoints only verify that the requester is a member of the guild (`requireGuildMember`). This allows *any* user in the server to change channel permissions. An explicit check for `MANAGE_CHANNELS` or server admin rights is required before allowing modifications.
- **Missing Auth Tests**: Per the review standard, new access controls require positive and negative test cases. There are no negative tests ensuring that a non-admin/non-manager is rejected with a 403 when trying to update permissions.

3. **Product Impact**:
- While the UI promises that "Bots without access will not receive messages from this channel," the lack of REST API filtering means bots can still interact with hidden channels if they poll or are triggered by other means, breaking the core product guarantee of this MVP.

4. **Suggestions**:
- **N+1 Query Risk**: In `packages/server/src/repos/channels.ts`, the `list()` method maps over every channel and calls `this.permissionsRepo.listByChannel(channel.id)`. This creates an N+1 query problem when listing channels for a guild. Consider fetching all overwrites for the guild's channels in a single query and grouping them in memory.

5. **Positive Notes**:
- Clean UI integration in `ChannelSettings.tsx` that provides a clear, user-friendly toggle for bot visibility.
- Solid test coverage for the dispatcher filtering logic and cascading database deletes.
- Good use of `BigInt` bitmasks for permissions, perfectly aligning with Discord's API specification and future-proofing the system.

Rate the PR: ❌ Major Issues
